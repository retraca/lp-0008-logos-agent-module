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
pub async fn get_npk(home_dir: &Path, passphrase: &str) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let file = keystore::load(&paths.keystore_path)?;
    let nsk: NskBytes = keystore::decrypt(&file, passphrase)?;
    let npk_bytes = keys::derive_npk(&nsk);
    Ok(keys::to_hex(&npk_bytes))
}

/// Return the agent's shielded account balance as a decimal string (u128).
pub async fn get_balance(home_dir: &Path, passphrase: &str) -> Result<String, ProviderError> {
    let paths = AgentPaths::new(home_dir);
    let account_id = account_id_from_keystore(&paths, passphrase)?;
    let wallet = open_wallet(&paths)?;
    let balance: u128 = wallet.get_account_balance(account_id).await?;
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
    let from_id = account_id_from_keystore(&paths, passphrase)?;
    let wallet = open_wallet(&paths)?;

    // Determine whether recipient is a base58 AccountId (known in local storage)
    // or a hex NPK (foreign account).
    let (hash, _secret) = if let Ok(to_id) = recipient.parse::<AccountId>() {
        let ntt = NativeTokenTransfer(&wallet);
        ntt.send_shielded_transfer(from_id, to_id, amount).await?
    } else if recipient.len() == 64 {
        // Treat as hex NPK. VPK cannot be derived from NPK alone (requires VSK).
        // For foreign NPK-only sends, we require the caller to also provide the VPK
        // as a second hex argument. This path is intentionally unsupported until
        // A2A Agent Cards expose the recipient's VPK.
        //
        // TODO: extend send_shielded signature to accept optional vpk_hex and wire through.
        return Err(ProviderError::Wallet(anyhow::anyhow!(
            "send to raw NPK not yet supported: VPK required but cannot be derived from NPK. \
             Use a base58 AccountId for known LEZ accounts, or extend the API to accept vpk_hex."
        )))
    } else {
        return Err(ProviderError::Keys(crate::keys::KeyDerivationError::InvalidBase58));
    };

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
