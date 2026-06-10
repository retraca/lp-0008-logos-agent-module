# PLAN.md: lez_wallet_module Implementation Plan

Prepared by Main Abstraction for LP-0008. Date: 2026-06-08.

---

## 1. What This Module Is

`lez_wallet_module` is the missing Logos Core module that bridges the shielded LEZ wallet
(currently a Rust CLI in `lez-build/wallet`) into the Logos Core plugin system. Without it,
the agent module in LP-0008 cannot call `wallet.balance()`, `wallet.send()`, `program.query()`,
`program.call()`, or `program.deploy()`. The module exposes the `ILezWallet` contract (from
`scaffold/interfaces/lez_wallet.h`) so the agent binds it at runtime via `interface_dependencies`.

---

## 2. Component Architecture

```
agent_module (C++ universal, LP-0008 core)
     |
     | LogosAPI inter-module call
     v
lez_wallet_module  <-- THIS BUILD
     |
     | FFI boundary (Rust <-> C via cbindgen)
     v
lez-wallet-core (Rust library crate)  <-- pure Rust, the bulk of the logic
     |
     +-- WalletCore  (from lez-build/wallet/src/lib.rs)
     |      - new_init_storage / new_update_chain
     |      - create_new_account_private
     |      - get_account_balance / get_account_public
     |      - send_privacy_preserving_tx_with_pre_check
     |      - sync_to_block
     |
     +-- nssa_core  (NullifierSecretKey, NullifierPublicKey, AccountId)
     |      - NullifierPublicKey::from(&nsk)
     |      - AccountId::from(&npk)
     |      - base58 Display/FromStr
     |
     +-- bedrock_client  (BedrockClient::post_transaction, get_lib_stream, get_block_by_id)
     |
     +-- encrypted keystore  (in lez-wallet-core, standalone, NO lez-build dep)
            - argon2 KDF on owner passphrase
            - aes-gcm-256 encrypt/decrypt NSK at rest
            - stored as JSON: { version, salt_b64, nonce_b64, ciphertext_b64 }
```

The Qt module (`lez_wallet_module_impl.h/.cpp`) is a thin C++ shim: it loads the compiled
Rust shared library at startup, calls into the FFI, and translates results to `StdLogosResult`.
The heavy logic (keystore, key derivation, RPC calls, ZK proving, transaction construction)
lives entirely in the Rust crate.

---

## 3. Rust Provider Core (`lez-wallet-core`)

### 3a. Keystore (standalone, no lez-build dependency, fast to test)

`src/keystore.rs` implements:

- `Keystore::encrypt(nsk: &[u8; 32], passphrase: &str) -> KeystoreFile`
  1. Generate 16-byte random salt.
  2. Derive 32-byte AES key via `argon2::Argon2::default().hash_password_into(passphrase, salt)`.
  3. Encrypt NSK with `aes_gcm::Aes256Gcm` using a 12-byte random nonce.
  4. Serialize to `{ version: 1, salt_b64, nonce_b64, ciphertext_b64 }` JSON.

- `Keystore::decrypt(file: &KeystoreFile, passphrase: &str) -> Result<[u8; 32]>`
  Inverse: re-derive key, decrypt, return NSK.

These functions depend only on `argon2`, `aes-gcm`, `rand`, `base64`, `serde_json`. No lez-build
tree. Unit tests in `src/keystore.rs` cover encrypt/decrypt round-trip and wrong-passphrase rejection.

### 3b. Key derivation (standalone, same light deps)

`src/keys.rs` re-implements (matching nssa source exactly):

- `derive_npk(nsk: &[u8; 32]) -> [u8; 32]`
  Domain-separated SHA-256: `SHA256("LEE/keys" || nsk || [7] || [0; 23])`.
  Matches `NullifierPublicKey::from(&NullifierSecretKey)` in `nssa/core/src/nullifier.rs`.

- `derive_account_id(npk: &[u8; 32]) -> [u8; 32]`
  Domain-separated SHA-256: `SHA256(b"/LEE/v0.3/AccountId/Private/\x00\x00\x00\x00" || npk)`.
  Matches `AccountId::from(&NullifierPublicKey)` in `nssa/core/src/nullifier.rs`.

- `account_id_to_base58(raw: &[u8; 32]) -> String` (base58 encode, matches nssa Display).

Unit tests in `src/keys.rs` verify the exact known-answer test vectors from `nssa/core/src/nullifier.rs`:
- nsk `[57,5,64,...]` -> npk `[78,20,20,...]` -> account_id `[139,72,194,...]`.

### 3c. Wallet provider (`src/provider.rs`)

This is the bridge to the real `lez-build` crates. It wraps `WalletCore` from
`lez-build/wallet/src/lib.rs`:

```rust
pub struct LezWalletProvider {
    core: WalletCore,          // from lez-build
    account_id: AccountId,     // the agent's private account
    home_dir: PathBuf,
    keystore_path: PathBuf,
}
```

Exposed operations (all `async`, bridged to sync in the FFI layer via `tokio::runtime::Handle`):

- `ensure_account(passphrase) -> String`
  If keystore exists: decrypt NSK, derive NPK/AccountId. If not: call
  `WalletCore::new_init_storage(config_path, storage_path, None, passphrase)` which generates
  a BIP39 mnemonic, creates key storage, then encrypt and persist NSK to keystore file.
  Returns `AccountId.to_string()` (base58).

- `npk() -> String`
  Load NSK from keystore, derive NPK via `NullifierPublicKey::from(&nsk)`, hex-encode.

- `balance() -> String`
  `WalletCore::get_account_balance(self.account_id).await?` returns `u128`. Return as decimal
  string (u128 does not fit `int64_t`, so decimal string is the correct wire representation).

- `sync_private() -> bool`
  `WalletCore::sync_to_block(latest_block_id).await` using `BedrockClient::get_consensus_info()`
  to fetch the current tip. Updates `last_synced_block`.

- `history(limit: i64) -> String`
  After sync, walk `WalletCore::storage().user_data` for private account entries. Serialize last
  `limit` entries as a JSON array `[{ tx_hash, balance_delta, block_id, timestamp }]`.

- `send(recipient: &str, amount_decimal: &str) -> String`
  Parse recipient as `AccountId` (base58) or `NullifierPublicKey` (hex). Parse amount as `u128`.
  Call `NativeTokenTransfer::send_shielded_transfer_to_outer_account(from, to_npk, to_vpk, amount)`.
  Returns tx hash hex. The spending-threshold gate lives in the agent module, not here.

- `program_query(program_id: &str, params_json: &str) -> String`
  Use `sequencer_client.get_account(AccountId::from_str(program_id)?)` (or the appropriate RPC
  call for reading program state). Returns JSON-serialized result.

- `program_call(program_id: &str, instruction: &str, params_json: &str) -> String`
  Build a `SignedMantleTx` from the instruction + params, sign with the agent's key,
  post via `BedrockClient::post_transaction(tx).await`. Returns tx hash hex.
  (The exact instruction encoding follows the `wallet/src/program_facades/` pattern.)

- `program_deploy(binary_path: &str) -> String`
  Read program binary from `binary_path`, construct `ProgramDeploymentTransaction` (as done in
  `lez-build/examples/program_deployment/`), sign and post. Returns program ID (base58).

### 3d. FFI layer (`src/ffi.rs`)

`cbindgen` generates a C header from `#[no_mangle] pub extern "C"` functions. Each function:
- Takes `*const c_char` string args.
- Returns `*mut c_char` (caller must free via `lez_wallet_free_string`).
- Errors returned as JSON: `{ "error": "message" }` (so the C++ shim can detect failure
  without a separate error code channel).

```c
// generated header shape (lez_wallet_ffi.h)
char* lez_wallet_ensure_account(const char* home_dir, const char* passphrase);
char* lez_wallet_npk(const char* home_dir);
char* lez_wallet_balance(const char* home_dir);
char* lez_wallet_history(const char* home_dir, int64_t limit);
bool  lez_wallet_sync_private(const char* home_dir);
char* lez_wallet_send(const char* home_dir, const char* recipient, const char* amount_decimal);
char* lez_wallet_program_query(const char* home_dir, const char* program_id, const char* params_json);
char* lez_wallet_program_call(const char* home_dir, const char* program_id,
                              const char* instruction, const char* params_json);
char* lez_wallet_program_deploy(const char* home_dir, const char* binary_path);
void  lez_wallet_free_string(char* s);
```

The `home_dir` param locates the keystore, config, and chain storage; isolates per-agent state.
Each call spins a `tokio::runtime::Builder::new_current_thread().build()` (or reuses a
thread-local runtime handle). The C++ side never touches async.

---

## 4. Qt Module Shim (`qt-module/`)

### 4a. Why this layer is blocked here

Nix, Qt6, and CMake are not installed on this machine. The shim can be written and reviewed
but not compiled until the toolchain is in place. It is deliberately thin (< 200 lines of C++).

### 4b. `lez_wallet_module_impl.h`

Universal module pattern (`"interface": "universal"` in metadata.json). Inherits
`LogosModuleContext`. No `Q_OBJECT`, no `Q_PLUGIN_METADATA`, no `Q_INVOKABLE`. Public methods
map 1:1 to `ILezWallet`:

```cpp
class LezWalletModuleImpl : public LogosModuleContext {
public:
    StdLogosResult ensure_account();
    StdLogosResult npk();
    StdLogosResult balance();
    StdLogosResult history(int64_t limit);
    bool           sync_private();
    StdLogosResult send(const std::string& recipient, const std::string& amount_decimal);
    StdLogosResult program_query(const std::string& program_id, const std::string& params_json);
    StdLogosResult program_call(const std::string& program_id,
                                const std::string& instruction,
                                const std::string& params_json);
    StdLogosResult program_deploy(const std::string& binary_path);
};
```

`logos-cpp-generator --from-header` generates the Qt plugin wrapper, `ILezWallet` contract
interface, and inter-module glue from this header + `metadata.json`.

### 4c. `lez_wallet_module_impl.cpp`

Loads `liblez_wallet_core.so` / `liblez_wallet_core.dylib` at startup via `dlopen` (or links
statically if bundled in the LGX). Calls the C FFI functions. Wraps results in `StdLogosResult`.
Translates `{ "error": ... }` JSON returns into `StdLogosResult::error(...)`.

### 4d. `metadata.json`

```json
{
  "name": "lez_wallet_module",
  "version": "0.1.0",
  "type": "core",
  "interface": "universal",
  "category": "blockchain",
  "description": "Shielded LEZ wallet and program interface for LP-0008 agent module",
  "main": "lez_wallet_module_plugin",
  "dependencies": [],
  "interface_dependencies": [],
  "capabilities": ["wallet.shielded", "program.call", "program.deploy"],
  "nix": {
    "buildInputs": [],
    "external_libraries": ["liblez_wallet_core"],
    "find_packages": [],
    "extra_cmake_flags": ["-DLEZ_WALLET_CORE_LIB=${LEZ_WALLET_CORE}"]
  }
}
```

---

## 5. Encrypted NSK at Rest

The design stores exactly one file per agent: `<home_dir>/keystore.json`:

```json
{
  "version": 1,
  "salt_b64": "<base64, 16 bytes>",
  "nonce_b64": "<base64, 12 bytes>",
  "ciphertext_b64": "<base64, 32 bytes ciphertext + 16 bytes GCM tag>"
}
```

Security properties:
- NSK never written in plaintext.
- AES-256-GCM provides authenticated encryption (wrong passphrase fails with a MAC error, not
  silently returns bad bytes).
- Argon2id KDF with default parameters (19 MiB memory, 2 iterations) makes brute-force expensive.
- The owner passphrase is supplied at module init time (`ensure_account(passphrase)`) and held
  only in process memory for the duration of that call. It is not stored.

BIP39 mnemonic (for wallet recovery) is printed once at init and must be stored by the operator.
It is not persisted by the module (matches `WalletCore::new_init_storage` behavior).

---

## 6. What Needs Nix/Qt6 vs Pure Rust

### Pure Rust (buildable now, no Qt):

| Component | Location | Status |
| --- | --- | --- |
| Keystore encrypt/decrypt | `lez-wallet-core/src/keystore.rs` | Written, unit-testable with light deps only |
| Key derivation (NSK->NPK->AccountId) | `lez-wallet-core/src/keys.rs` | Written, unit-testable, known-answer tests |
| FFI types and error envelope | `lez-wallet-core/src/ffi.rs` | Written (stubs for provider calls) |
| Provider wrapping WalletCore | `lez-wallet-core/src/provider.rs` | Written, BLOCKED on lez-build compile |
| Cargo.toml (standalone keystore tests) | `lez-wallet-core/Cargo.toml` | Uses only light deps for the test feature |

The keystore and key derivation modules compile and test with only:
`aes-gcm`, `argon2`, `rand`, `base64`, `sha2`, `serde`, `serde_json`, `base58`, `hex`, `thiserror`.

### Requires lez-build compile (Rust, but heavy):

`provider.rs` imports `wallet::WalletCore`, `nssa::AccountId`, `bedrock_client::BedrockClient`,
`sequencer_service_rpc::SequencerClient`. These pull in `risc0_zkvm`, `logos-blockchain-circuits`,
`tokio`, and the full chain. DO NOT run `cargo build` on this machine; it will exceed the 2-minute
watchdog. See BUILD.md for the safe setup path.

### Requires Nix + Qt6 (C++, blocked here):

| Component | Blocked on |
| --- | --- |
| `qt-module/src/lez_wallet_module_impl.h/.cpp` | Qt6 headers (`logos_module_context.h`, `logos_result.h`) |
| `logos-cpp-generator` codegen | Nix dev shell |
| CMakeLists.txt + flake.nix | Nix |
| LGX packaging | `nix build .#lgx` |
| `logoscore` load + call | Nix-built `logoscore` binary |

### Requires live LEZ testnet endpoint:

- Any `BedrockClient::post_transaction` call in production.
- `sync_private()` (needs a real sequencer tip).
- `program_deploy` (needs the chain to accept `ProgramDeploymentTransaction`).
- Risc0 ZK proofs (`RISC0_DEV_MODE=0`) require the `logos-blockchain-circuits` release + rzup.

Local standalone (`lgs setup` + `lgs start-sequencer`) substitutes for testnet during development.
The prize specifically requires testnet for the final demo.

---

## 7. Toolchain Setup Checklist

Complete in this order to reach a green first build:

1. Install Nix with flakes:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   # Add to ~/.config/nix/nix.conf:
   experimental-features = nix-command flakes
   ```

2. Install Risc0 toolchain (separate from Nix):
   ```bash
   curl -L https://risczero.com/install | bash
   rzup install
   ```
   Verify: `cargo risczero --version`.

3. Download `logos-blockchain-circuits` release binary to `~/.logos-blockchain-circuits/`
   (see lez-build README for the exact release tag matching the lez-build checkout).
   Set `LOGOS_BLOCKCHAIN_CIRCUITS=$HOME/.logos-blockchain-circuits` in env.

4. Smoke-test the Logos module toolchain:
   ```bash
   cd /tmp && nix flake init -t github:logos-co/logos-module-builder
   git init && git add -A && nix build .#lib
   ```

5. Smoke-test the LEZ standalone sequencer:
   ```bash
   cd lez-build && cargo run -p scaffold -- setup
   cargo run -p scaffold -- start-sequencer &
   RISC0_DEV_MODE=1 cargo run --example run_hello_world_private
   ```
   Use `RISC0_DEV_MODE=1` first; switch to `RISC0_DEV_MODE=0` for the full ZK path (slow: expect
   minutes per transaction on a dev machine).

6. Build `lez-wallet-core` standalone keystore tests (fast, no lez-build tree):
   ```bash
   cd lez-wallet-module/lez-wallet-core
   cargo test --features standalone-tests -- --nocapture
   ```
   Expected: all keystore + key derivation tests pass in < 5 seconds.

7. Build `lez-wallet-core` full (requires step 2 + 3 + lez-build present):
   ```bash
   cd lez-wallet-module/lez-wallet-core
   cargo build --release
   ```

8. Build Qt module (requires step 1 + 4 + step 7 artifact):
   ```bash
   cd lez-wallet-module
   nix develop
   cmake -B build -GNinja -DLEZ_WALLET_CORE_LIB=$(pwd)/lez-wallet-core/target/release
   ninja -C build
   ```

9. Inspect + load:
   ```bash
   lm methods ./build/lez_wallet_module_plugin.so --json
   logoscore -m ./modules -l lez_wallet_module -c "lez_wallet_module.ensure_account()" --quit-on-finish
   ```

---

## 8. Effort Estimate (days, one engineer, full toolchain in place)

| Phase | Task | Days |
| --- | --- | --- |
| 0 | Toolchain setup (Nix, Risc0, circuits, smoke tests) | 1.5 |
| 1a | lez-wallet-core: keystore + key derivation (done here, just needs review) | 0.5 |
| 1b | lez-wallet-core: provider wrapping WalletCore + send_shielded + sync | 3 |
| 1c | lez-wallet-core: program_query / program_call / program_deploy | 2 |
| 1d | FFI layer + cbindgen header + Qt shim | 1.5 |
| 1e | Integration test: logoscore call -> real testnet balance | 1 |
| 2 | Storage + Messaging skills in agent_module | 4 |
| 3 | agent_module core: runtime loop, spending gate, skill dispatch, meta.* | 5 |
| 4 | A2A binding: Agent Cards, task lifecycle, discovery, multi-agent LEZ payment | 6 |
| 5 | Single-CLI remote deploy, Basecamp owner UI, CI, demo script, video | 5 |
| - | Buffer (testnet RPC surprises, Risc0 proving time, Basecamp caveats) | 3 |
| **Total** | | **~33 working days (6.5 weeks)** |

Breaking it down more honestly:
- `lez_wallet_module` alone (phases 0 + 1a-1e): **9.5 days** (the make-or-break piece).
- The full LP-0008 prize submission: approximately **33 days** (6.5 weeks) for one senior engineer.

This matches the prior BUILD_PLAN estimate of 3-6 weeks; the lower bound requires no testnet
surprises and a clean Risc0 toolchain install.

---

## 9. Key Risks and Mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Testnet RPC diverges from standalone sequencer | Medium | Build against standalone first; test on testnet only at Phase 1e; document any delta |
| Risc0 proving time exceeds watchdog/CI timeout | Medium | Use `RISC0_DEV_MODE=1` in CI; `RISC0_DEV_MODE=0` in demo video only (prize requirement) |
| Released Basecamp rejects user-installed modules | High (LEARNING.md §8) | Build Basecamp locally from source; document local-build requirement in submission |
| `liblogoschat` configJson schema undocumented | Low-Medium | Read `logos-chat-module` flake/test fixtures; test empirically against a running logoscore |
| LGX `-dev` variant naming bug | Low | Apply the `postInstall` workaround documented in LEARNING.md §8 |
| `WalletCore` API changes between lez-build checkout and testnet | Low | Pin to the exact commit used in the testnet deployment; document the pin |
