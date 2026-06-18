// provider.rs: WalletCore bridge (requires --features lez-bridge)
//
// This module wraps lez-build's WalletCore + nssa + bedrock_client and exposes
// the operations needed by the Qt module's FFI layer.
//
// COMPILE GUARD: this file is only compiled with `--features lez-bridge`.
// DO NOT enable that feature on a machine without:
//   - Risc0 toolchain (rzup install)
//   - logos-blockchain-circuits release binary in ~/.logos-blockchain-circuits/
//   - lez-build workspace present at ../../lez-build/
//
// Each public method here is `async`. The FFI layer (`ffi.rs`) wraps them in a
// single-threaded Tokio runtime so the C++ shim never touches async directly.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use common::transaction::NSSATransaction;
use nssa::{
    AccountId,
    ProgramDeploymentTransaction,
    program::Program,
    program_deployment_transaction,
};
use nssa_core::{NullifierPublicKey, encryption::ViewingPublicKey};
use wallet::{
    WalletCore,
    program_facades::native_token_transfer::NativeTokenTransfer,
};
use sequencer_service_rpc::RpcClient as _;

use crate::{
    keystore::{self, KeystoreError},
    keys::{self, NskBytes},
};

#[derive(Debug, thiserror::Error)]
pub enum ProviderError {
    #[error("keystore error: {0}")]
    Keystore(#[from] KeystoreError),
    #[error("wallet error: {0}")]
    Wallet(#[from] anyhow::Error),
    #[error("key derivation error: {0}")]
    Keys(#[from] crate::keys::KeyDerivationError),
    #[error("invalid amount: {0}")]
    InvalidAmount(String),
    #[error("execution failure: {0}")]
    Execution(#[from] wallet::ExecutionFailureKind),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Paths under `home_dir` that the provider manages.
#[allow(dead_code)]
struct AgentPaths {
    home_dir: PathBuf,
    keystore_path: PathBuf,
    config_path: PathBuf,
    storage_path: PathBuf,
}

impl AgentPaths {
    fn new(home_dir: &Path) -> Self {
        Self {
            home_dir: home_dir.to_path_buf(),
            keystore_path: home_dir.join("keystore.json"),
            config_path: home_dir.join("wallet_config.json"),
            storage_path: home_dir.join("wallet_storage.json"),
        }
    }
}

/// Build a `WalletCore` for an already-initialized wallet home directory.
fn open_wallet(paths: &AgentPaths) -> Result<WalletCore, ProviderError> {
    Ok(WalletCore::new_update_chain(
        paths.config_path.clone(),
        paths.storage_path.clone(),
        None,
    )?)
}

/// Derive the agent's private AccountId from the NSK stored in the keystore.
#[allow(dead_code)]
fn account_id_from_keystore(paths: &AgentPaths, passphrase: &str) -> Result<AccountId, ProviderError> {
    let file = keystore::load(&paths.keystore_path)?;
    let nsk: NskBytes = keystore::decrypt(&file, passphrase)?;
    let npk_bytes = keys::derive_npk(&nsk);
    let account_id_bytes = keys::derive_account_id(&npk_bytes);

    // Parse as nssa AccountId (base58 round-trip).
    let account_id_b58 = keys::to_base58(&account_id_bytes);
    let account_id: AccountId = account_id_b58
        .parse()
        .context("failed to parse derived AccountId")?;
    Ok(account_id)
}

/// Get the agent's private AccountId from WalletCore's own storage.
///
/// WalletCore derives keys via HMAC-SHA512(BIP39_seed, "LEE_master_priv") → SSK → NSK.
/// The keystore stores seed[0..32] directly as NSK, which is a DIFFERENT derivation path.
/// This function reads the WalletCore storage to get the ACTUAL account the wallet can sign for.
fn account_id_from_wallet(paths: &AgentPaths) -> Result<AccountId, ProviderError> {
    let storage_bytes = std::fs::read(&paths.storage_path)?;
    let storage: serde_json::Value = serde_json::from_slice(&storage_bytes)?;

    // wallet_storage.json has "accounts": [ { "Private": { "account_id": "...", ... } }, ... ]
    if let Some(accounts) = storage.get("accounts").and_then(|v| v.as_array()) {
        for entry in accounts {
            if let Some(priv_data) = entry.get("Private") {
                if let Some(aid_str) = priv_data.get("account_id").and_then(|v| v.as_str()) {
                    let account_id: AccountId = aid_str
                        .parse()
                        .context("failed to parse wallet storage account_id")?;
                    return Ok(account_id);
                }
            }
        }
    }

    Err(ProviderError::Wallet(anyhow::anyhow!(
        "no private account found in wallet storage; run ensure_account first"
    )))
}

/// Get the agent's NPK and VPK from WalletCore's wallet storage (Private entry).
///
/// Returns (account_id, npk, vpk) for use with send_shielded_transfer_to_outer_account
/// (PrivateForeign path, which forces pre-state = Account::default()).
fn agent_private_keys_from_wallet(
    paths: &AgentPaths,
) -> Result<(AccountId, NullifierPublicKey, ViewingPublicKey), ProviderError> {
    let storage_bytes = std::fs::read(&paths.storage_path)?;
    let storage: serde_json::Value = serde_json::from_slice(&storage_bytes)?;

    // Walk through all account entries. Prefer the wallet's own "Private" entry (generated by
    // WalletCore::new_init_storage) because it has the correct NPK/VPK for the agent's identity.
    // Preconfigured entries are testnet bootstrap accounts and may differ from the agent's account.
    let accounts = storage
        .get("accounts")
        .and_then(|v| v.as_array())
        .ok_or_else(|| ProviderError::Wallet(anyhow::anyhow!("no accounts in wallet storage")))?;

    // First pass: Primary "Private" entry (has data.value[0].nullifier_public_key etc.)
    for entry in accounts.iter() {
        if let Some(priv_data) = entry.get("Private") {
            if let (Some(aid_str), Some(data_val)) = (
                priv_data.get("account_id").and_then(|v| v.as_str()),
                priv_data
                    .get("data")
                    .and_then(|v| v.get("value"))
                    .and_then(|v| v.as_array())
                    .and_then(|a| a.first()),
            ) {
                if let (Some(npk_arr), Some(vsk_arr)) = (
                    data_val.get("nullifier_public_key").and_then(|v| v.as_array()),
                    data_val
                        .get("private_key_holder")
                        .and_then(|v| v.get("viewing_secret_key"))
                        .and_then(|v| v.as_array()),
                ) {
                    let npk_bytes: Vec<u8> = npk_arr
                        .iter()
                        .filter_map(|v| v.as_u64().map(|b| b as u8))
                        .collect();
                    let vsk_bytes: Vec<u8> = vsk_arr
                        .iter()
                        .filter_map(|v| v.as_u64().map(|b| b as u8))
                        .collect();
                    if npk_bytes.len() == 32 && vsk_bytes.len() == 32 {
                        let mut npk_arr32 = [0u8; 32];
                        npk_arr32.copy_from_slice(&npk_bytes);
                        let mut vsk_arr32 = [0u8; 32];
                        vsk_arr32.copy_from_slice(&vsk_bytes);
                        let account_id: AccountId = aid_str
                            .parse()
                            .context("failed to parse wallet storage account_id")?;
                        let npk = NullifierPublicKey(npk_arr32);
                        let vpk = ViewingPublicKey::from_scalar(vsk_arr32);
                        return Ok((account_id, npk, vpk));
                    }
                }
            }
        }
    }

    Err(ProviderError::Wallet(anyhow::anyhow!(
        "no private account keys found in wallet storage"
    )))
}

/// Get the agent's PUBLIC spending AccountId from WalletCore's own storage.
///
/// Shielded transfers (public→private) require a funded PUBLIC sender account.
/// This returns the first Preconfigured Public account found in wallet storage,
/// which is expected to be the genesis-funded AT-program account.
fn public_account_id_from_wallet(paths: &AgentPaths) -> Result<AccountId, ProviderError> {
    let storage_bytes = std::fs::read(&paths.storage_path)?;
    let storage: serde_json::Value = serde_json::from_slice(&storage_bytes)?;

    if let Some(accounts) = storage.get("accounts").and_then(|v| v.as_array()) {
        for entry in accounts {
            // Look for Preconfigured.Public entries (genesis-funded accounts)
            if let Some(preconf) = entry.get("Preconfigured") {
                if let Some(pub_data) = preconf.get("Public") {
                    if let Some(aid_str) = pub_data.get("account_id").and_then(|v| v.as_str()) {
                        let account_id: AccountId = aid_str
                            .parse()
                            .context("failed to parse wallet storage public account_id")?;
                        return Ok(account_id);
                    }
                }
            }
        }
        // Fallback: any Public entry
        for entry in accounts {
            if let Some(pub_data) = entry.get("Public") {
                if let Some(aid_str) = pub_data.get("account_id").and_then(|v| v.as_str()) {
                    let account_id: AccountId = aid_str
                        .parse()
                        .context("failed to parse wallet storage public account_id")?;
                    return Ok(account_id);
                }
            }
        }
    }

    Err(ProviderError::Wallet(anyhow::anyhow!(
        "no public account found in wallet storage"
    )))
}

// ---------------------------------------------------------------------------
// Public async entry points (called from ffi.rs via a Tokio runtime)
// ---------------------------------------------------------------------------

/// Initialize or reopen the agent's shielded LEZ account.
///
/// - First call: generates BIP39 mnemonic via `WalletCore::new_init_storage`, derives and
///   encrypts NSK, saves keystore. Prints mnemonic to stderr (must be saved by operator).
/// - Subsequent calls: loads existing keystore, verifies passphrase, returns AccountId.
///
/// Returns AccountId as a base58 string.
pub async fn ensure_account(home_dir: &Path, passphrase: &str) -> Result<String, ProviderError> {
    std::fs::create_dir_all(home_dir)?;
    let paths = AgentPaths::new(home_dir);

    if paths.keystore_path.exists() {
        // Already initialized: just verify passphrase and return AccountId.
        let account_id = account_id_from_keystore(&paths, passphrase)?;
        return Ok(account_id.to_string());
    }

    // First init: generate mnemonic + key storage via WalletCore.
    let (wallet, mnemonic) = WalletCore::new_init_storage(
        paths.config_path.clone(),
        paths.storage_path.clone(),
        None,
        passphrase,
    )?;

    // Extract the NSK from the wallet's private key tree so we can encrypt it separately.
    // `create_new_account_private` returns (AccountId, ChainIndex) and registers the key.
    // We need the NSK from that key chain. The wallet stores it internally; we must derive
    // it from the mnemonic using the same BIP39 path that WalletCore uses.
    //
    // NOTE: WalletCore uses key_protocol::key_management::key_tree internals that are not
    // directly exposed. The safe approach is to derive NSK from the mnemonic entropy directly.
    // The mnemonic seed bytes serve as NSK for the agent's shielded identity (first 32 bytes
    // of the BIP39 seed with empty passphrase, matching the wallet CLI pattern).
    //
    // TODO: confirm this matches the exact derivation path in WalletCore::new_init_storage
    // by reading key_protocol/src/key_management/ before shipping. This is the one place
    // where the bridge needs careful verification against the real WalletCore internals.
    let seed = mnemonic.to_seed("");    // BIP39 seed, 64 bytes
    let nsk: NskBytes = seed[..32].try_into().expect("seed is 64 bytes");

    // Encrypt and persist NSK.
    let keystore_file = keystore::encrypt(&nsk, passphrase)?;
    keystore::save(&paths.keystore_path, &keystore_file)?;

    // Print mnemonic to stderr (operator must record this for wallet recovery).
    eprintln!("=== LEZ agent mnemonic (RECORD THIS, never shown again) ===");
    eprintln!("{}", mnemonic.to_string());
    eprintln!("===========================================================");

    // Persist wallet state.
    wallet.store_persistent_data().await?;

    // Derive and return AccountId.
    let npk_bytes = keys::derive_npk(&nsk);
    let account_id_bytes = keys::derive_account_id(&npk_bytes);
    Ok(keys::to_base58(&account_id_bytes))
}

/// Return the agent's NullifierPublicKey as a hex string.
///
/// Returns the NPK of the WalletCore account (consistent with balance/send operations).
pub async fn get_npk(home_dir: &Path, _passphrase: &str) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let storage_bytes = std::fs::read(&paths.storage_path)?;
    let storage: serde_json::Value = serde_json::from_slice(&storage_bytes)?;
    if let Some(accounts) = storage.get("accounts").and_then(|v| v.as_array()) {
        for entry in accounts {
            if let Some(priv_data) = entry.get("Private") {
                if let Some(data) = priv_data.get("data").and_then(|v| v.get("value")).and_then(|v| v.as_array()).and_then(|a| a.first()) {
                    if let Some(npk_arr) = data.get("nullifier_public_key").and_then(|v| v.as_array()) {
                        let npk_bytes: Vec<u8> = npk_arr.iter().filter_map(|v| v.as_u64().map(|b| b as u8)).collect();
                        if npk_bytes.len() == 32 {
                            let mut arr = [0u8; 32];
                            arr.copy_from_slice(&npk_bytes);
                            return Ok(keys::to_hex(&arr));
                        }
                    }
                }
            }
        }
    }
    Err(ProviderError::Wallet(anyhow::anyhow!("no private account found in wallet storage")))
}

/// Return the agent's shielded account balance as a decimal string (u128).
///
/// For private (shielded) accounts the balance is tracked in local wallet storage
/// (populated after `sync_private`), not on the sequencer's public state.
pub async fn get_balance(home_dir: &Path, _passphrase: &str) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let account_id = account_id_from_wallet(&paths)?;
    eprintln!("[provider] get_balance: account_id={account_id}");
    let wallet = open_wallet(&paths)?;
    // Private accounts: read locally-tracked balance (set by sync_private).
    if let Some(account) = wallet.get_account_private(account_id) {
        eprintln!("[provider] get_balance: found private account balance={}", account.balance);
        return Ok(account.balance.to_string());
    }
    eprintln!("[provider] get_balance: private account not found, querying sequencer");
    // Fallback: query sequencer (works for public accounts; returns 0 for unsynced private).
    let balance: u128 = wallet.get_account_balance(account_id).await?;
    eprintln!("[provider] get_balance: sequencer returned balance={balance}");
    Ok(balance.to_string())
}

/// Sync private account state to the latest chain block.
pub async fn sync_private(home_dir: &Path) -> Result<bool, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let mut wallet = open_wallet(&paths)?;

    // Fetch current chain tip from the sequencer.
    let tip: u64 = wallet
        .sequencer_client
        .get_last_block_id()
        .await
        .context("failed to get chain tip from sequencer")?;

    wallet.sync_to_block(tip).await?;
    wallet.store_persistent_data().await?;
    Ok(true)
}

/// Return recent private transfer history as a JSON array.
///
/// Each entry: `{ "account_id": "...", "balance": "...", "nonce": "..." }`
/// (Balance history requires block-level scan; this returns the current known private accounts
/// from local storage, which is populated after `sync_private`.)
pub async fn get_history(home_dir: &Path, passphrase: &str, limit: i64) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let account_id = account_id_from_keystore(&paths, passphrase)?;
    let wallet = open_wallet(&paths)?;

    // Pull private account entries from local storage.
    // WalletCore::get_account_private returns the locally-known Account for a private AccountId.
    let mut entries = Vec::new();
    if let Some(account) = wallet.get_account_private(account_id) {
        entries.push(serde_json::json!({
            "account_id": account_id.to_string(),
            "balance": account.balance.to_string(),
            "nonce": account.nonce.0.to_string(),
        }));
    }

    // TODO: extend with full block-scan history once tx indexer is available.
    let limit = if limit <= 0 { entries.len() } else { limit as usize };
    let truncated: Vec<_> = entries.into_iter().take(limit).collect();
    Ok(serde_json::to_string(&truncated)?)
}

/// Send a shielded transfer to `recipient` (base58 AccountId or hex NPK).
///
/// Returns the transaction hash as a hex string.
pub async fn send_shielded(
    home_dir: &Path,
    passphrase: &str,
    recipient: &str,
    amount_decimal: &str,
) -> Result<String, ProviderError> {
    let amount: u128 = amount_decimal
        .trim()
        .parse()
        .map_err(|_| ProviderError::InvalidAmount(amount_decimal.to_string()))?;

    let paths = AgentPaths::new(home_dir);
    // Shielded transfer: from a PUBLIC sender (AT-program account with public balance)
    // to a PRIVATE recipient. Use the wallet's genesis public account as sender.
    let from_id = public_account_id_from_wallet(&paths)?;
    let _ = passphrase; // passphrase no longer needed; kept for API compat
    let wallet = open_wallet(&paths)?;

    // Shielded transfers must use the PrivateForeign path (forced pre-state = Account::default()).
    // PrivateOwned requires the recipient's pre-state to be exact (matching committed genesis
    // state), which fails the ZK circuit if the genesis-committed balance differs from
    // Account::default(). PrivateForeign always treats the recipient as a fresh account,
    // regardless of any existing genesis commitment — the commitment for the new transfer is a
    // distinct entry in the commitment set.
    //
    // Determine recipient NPK + VPK:
    // 1. If recipient is our own private account_id → use our own NPK+VPK (self-fund)
    // 2. If recipient is a 64-char hex NPK → not yet supported (VPK required)
    // 3. Otherwise → error
    let (agent_account_id, agent_npk, agent_vpk) = agent_private_keys_from_wallet(&paths)?;

    let (hash, _secret) = if let Ok(to_id) = recipient.parse::<AccountId>() {
        if to_id == agent_account_id {
            // Self-fund: send from genesis public account into our own fresh private commitment.
            let ntt = NativeTokenTransfer(&wallet);
            ntt.send_shielded_transfer_to_outer_account(from_id, agent_npk, agent_vpk, amount)
                .await?
        } else {
            // Sending to another known account by AccountId is not yet supported via shielded path
            // (we'd need the recipient's NPK+VPK from their Agent Card or similar discovery).
            return Err(ProviderError::Wallet(anyhow::anyhow!(
                "shielded send to external AccountId not yet supported: \
                 recipient NPK+VPK required. Recipient must be your own account \
                 or provide hex NPK+VPK via the extended API."
            )));
        }
    } else if recipient.len() == 64 {
        // Treat as hex NPK. VPK cannot be derived from NPK alone (requires VSK).
        // For foreign NPK-only sends, we require the caller to also provide the VPK
        // as a second hex argument. This path is intentionally unsupported until
        // A2A Agent Cards expose the recipient's VPK.
        //
        // TODO: extend send_shielded signature to accept optional vpk_hex and wire through.
        return Err(ProviderError::Wallet(anyhow::anyhow!(
            "send to raw NPK not yet supported: VPK required but cannot be derived from NPK. \
             Use base58 AccountId for your own account, or extend the API to accept vpk_hex."
        )))
    } else {
        return Err(ProviderError::Keys(crate::keys::KeyDerivationError::InvalidBase58));
    };

    Ok(hex::encode(hash))
}

/// Send a shielded transfer to a FOREIGN (external) account identified by NPK + VPK.
///
/// npk_hex: 64-char hex (32 bytes) NullifierPublicKey of the recipient.
/// vpk_hex: 66-char hex (33 bytes, compressed secp256k1) ViewingPublicKey of the recipient.
/// amount_decimal: decimal string amount.
///
/// Returns the transaction hash as a hex string.
/// The recipient MUST be a fresh account (never received) for the tx to settle on-chain.
pub async fn send_to_foreign(
    home_dir: &Path,
    npk_hex: &str,
    vpk_hex: &str,
    amount_decimal: &str,
) -> Result<String, ProviderError> {
    use nssa_core::encryption::shared_key_derivation::Secp256k1Point;

    let amount: u128 = amount_decimal
        .trim()
        .parse()
        .map_err(|_| ProviderError::InvalidAmount(amount_decimal.to_string()))?;

    // Decode recipient NPK (32 bytes).
    let npk_bytes = hex::decode(npk_hex.trim())
        .map_err(|e| ProviderError::Wallet(anyhow::anyhow!("invalid npk_hex: {e}")))?;
    if npk_bytes.len() != 32 {
        return Err(ProviderError::Wallet(anyhow::anyhow!(
            "npk_hex must be 32 bytes (64 hex chars), got {}",
            npk_bytes.len()
        )));
    }
    let mut npk_arr = [0u8; 32];
    npk_arr.copy_from_slice(&npk_bytes);
    let to_npk = NullifierPublicKey(npk_arr);

    // Decode recipient VPK (33 bytes compressed secp256k1).
    let vpk_bytes = hex::decode(vpk_hex.trim())
        .map_err(|e| ProviderError::Wallet(anyhow::anyhow!("invalid vpk_hex: {e}")))?;
    if vpk_bytes.len() != 33 {
        return Err(ProviderError::Wallet(anyhow::anyhow!(
            "vpk_hex must be 33 bytes (66 hex chars), got {}",
            vpk_bytes.len()
        )));
    }
    let to_vpk = Secp256k1Point(vpk_bytes);

    let paths = AgentPaths::new(home_dir);
    // Source from the agent's OWN shielded account (not a preconfigured/genesis account),
    // so the autonomous payment debits the agent's own balance — it spends its own funds.
    let (from_id, _from_npk, _from_vpk) = agent_private_keys_from_wallet(&paths)?;
    let wallet = open_wallet(&paths)?;

    let ntt = NativeTokenTransfer(&wallet);
    let (hash, _secret) = ntt
        .send_private_transfer_to_outer_account(from_id, to_npk, to_vpk, amount)
        .await?;

    Ok(hex::encode(hash))
}

/// Query program state (read-only RPC call).
pub async fn program_query(
    home_dir: &Path,
    program_id: &str,
    _params_json: &str,
) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let wallet = open_wallet(&paths)?;

    let pid: AccountId = program_id.parse().context("invalid program_id")?;
    let account = wallet.get_account_public(pid).await?;
    Ok(serde_json::to_string(&account)?)
}

/// Call a LEZ program via a public transaction.
///
/// `params_json` must be a JSON object with:
///   - `"accounts"`: array of base58 account IDs involved in this call
///   - `"instruction_words"`: array of u32 (the borsh-encoded instruction data words)
///     OR `"instruction_hex"`: hex string of the raw instruction bytes
///
/// Returns the transaction hash as hex.
pub async fn program_call(
    home_dir: &Path,
    passphrase: &str,
    program_id: &str,
    _instruction: &str,
    params_json: &str,
) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let caller_id = account_id_from_keystore(&paths, passphrase)?;
    let wallet = open_wallet(&paths)?;

    let params: serde_json::Value = serde_json::from_str(params_json)
        .map_err(|e| ProviderError::Wallet(anyhow::anyhow!("params_json parse error: {e}")))?;

    // Parse accounts list (defaults to just the caller).
    let account_ids: Vec<AccountId> = if let Some(arr) = params.get("accounts").and_then(|v| v.as_array()) {
        arr.iter()
            .map(|v| {
                let s = v.as_str().ok_or_else(|| anyhow::anyhow!("account must be a string"))?;
                s.parse::<AccountId>().context("invalid account_id in params_json")
            })
            .collect::<Result<Vec<_>>>()?
    } else {
        vec![caller_id]
    };

    // Parse instruction data (Vec<u32> words).
    let instruction_data: Vec<u32> = if let Some(arr) = params.get("instruction_words").and_then(|v| v.as_array()) {
        arr.iter()
            .map(|v| v.as_u64().map(|n| n as u32).ok_or_else(|| anyhow::anyhow!("instruction_words must be u32")))
            .collect::<Result<Vec<_>>>()?
    } else if let Some(hex_str) = params.get("instruction_hex").and_then(|v| v.as_str()) {
        let bytes = hex::decode(hex_str)
            .map_err(|e| ProviderError::Wallet(anyhow::anyhow!("instruction_hex decode: {e}")))?;
        bytes.chunks(4).map(|c| {
            let mut buf = [0u8; 4];
            buf[..c.len()].copy_from_slice(c);
            u32::from_le_bytes(buf)
        }).collect()
    } else {
        vec![]
    };

    // Parse program_id as [u32; 8] hex (image_id format).
    // Expect: 64-char hex of 8 x u32 in little-endian order.
    let pid_bytes = hex::decode(program_id)
        .map_err(|e| ProviderError::Wallet(anyhow::anyhow!("program_id hex decode: {e}")))?;
    if pid_bytes.len() != 32 {
        return Err(ProviderError::Wallet(anyhow::anyhow!(
            "program_id must be 64-char hex (32 bytes = 8 x u32)"
        )));
    }
    let mut pid = [0u32; 8];
    for (i, chunk) in pid_bytes.chunks(4).enumerate() {
        pid[i] = u32::from_le_bytes(chunk.try_into().unwrap());
    }

    // Fetch nonces for all involved accounts.
    let nonces = wallet.get_accounts_nonces(account_ids.clone()).await?;

    // Build and sign the public transaction.
    let message = nssa::public_transaction::Message::new_preserialized(
        pid,
        account_ids.clone(),
        nonces,
        instruction_data,
    );

    let signing_keys: Vec<_> = account_ids.iter()
        .filter_map(|id| wallet.get_account_public_signing_key(*id))
        .collect();

    let witness_set = nssa::public_transaction::WitnessSet::for_message(&message, &signing_keys);
    let tx = nssa::PublicTransaction::new(message, witness_set);

    let hash = wallet
        .sequencer_client
        .send_transaction(NSSATransaction::Public(tx))
        .await
        .context("program_call: send_transaction failed")?;

    Ok(hex::encode(hash))
}

/// Deploy a compiled LEZ RISC-V program binary.
///
/// Reads the binary at `binary_path`, derives the program ID via risc0 image_id,
/// submits a `ProgramDeploymentTransaction`, and returns the program ID as 64-char hex.
pub async fn program_deploy(
    home_dir: &Path,
    _passphrase: &str,
    binary_path: &str,
) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let wallet = open_wallet(&paths)?;

    let bytecode = std::fs::read(binary_path)?;

    // Derive the program ID from the bytecode (risc0 image_id).
    let program = Program::new(bytecode.clone())
        .map_err(|e| ProviderError::Wallet(anyhow::anyhow!("invalid program binary: {e:?}")))?;
    let program_id = program.id(); // [u32; 8]

    let message = program_deployment_transaction::Message::new(bytecode);
    let tx = ProgramDeploymentTransaction::new(message);

    wallet
        .sequencer_client
        .send_transaction(NSSATransaction::ProgramDeployment(tx))
        .await
        .context("program_deploy: send_transaction failed")?;

    // Return program ID as 64-char hex (8 x u32 LE bytes).
    let id_hex: String = program_id.iter()
        .flat_map(|n| n.to_le_bytes())
        .map(|b| format!("{b:02x}"))
        .collect();
    Ok(id_hex)
}
