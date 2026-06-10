# LP-0008 Submission: Autonomous AI Agent Module for Logos Core

**Prize:** Lambda Prize LP-0008 — Autonomous AI Agent Module  
**Author:** Gonçalo Traça (github: retraca)

---

## What is built

Two Logos Core modules that together form a fully autonomous AI agent with a shielded LEZ wallet identity:

### 1. `lez_wallet_module` (Qt universal module, C++/Rust)

A new Logos Core module that did not previously exist. Exposes the LEZ shielded wallet and LEZ program interface to any Logos module via `LogosAPI`.

Built at: `lez-wallet-module/qt-module/`  
Rust core: `lez-wallet-module/lez-wallet-core/` (FFI bridge to `nssa`, `bedrock_client`, `wallet`)

Exposed wire methods:
- `ensure_account(passphrase)` — create or reopen the agent's shielded LEZ account; persists NSK encrypted at rest
- `npk(passphrase)` — return the agent's NullifierPublicKey (hex)
- `balance(passphrase)` — current shielded token balance
- `history(passphrase, limit)` — private transfer history
- `sync_private()` — scan chain for latest private state
- `send(passphrase, recipient, amount_decimal)` — shielded transfer to AccountId or NPK
- `program_query(program_id, params_json)` — read LEZ program state (no sig)
- `program_call(passphrase, program_id, instruction, params_json)` — invoke a LEZ program instruction
- `program_deploy(passphrase, binary_path)` — deploy a compiled RISC-V LEZ program

Events: `tx_settled(tx_hash, timestamp)`, `tx_failed(tx_hash, error, timestamp)`

### 2. `agent_module` (Qt universal module, pure C++)

The autonomous agent: runtime skill dispatcher with spending-threshold gate, owner channel over E2E messaging, A2A coordination, pluggable inference adapter.

Built at: `lp-0008-ai-module/scaffold/`

Skill surface (all return JSON strings):
- **Storage**: `storage.upload`, `storage.download`, `storage.list`, `storage.share`
- **Messaging**: `messaging.send`, `messaging.join`, `messaging.create_group`
- **Wallet**: `wallet.balance`, `wallet.send` (gated), `wallet.history`
- **Programs**: `program.query`, `program.call` (gated), `program.deploy` (gated)
- **A2A**: `agent.card`, `agent.discover`, `agent.task`, `agent.subscribe`, `agent.cancel`
- **Meta**: `meta.skills`, `meta.status`, `meta.configure`
- **Approval**: `approve_pending`, `reject_pending`

---

## Architecture

```
Owner (Logos Basecamp)
  |  E2E chat_module conversation (owner channel)
  v
agent_module (core, universal C++)
  |   spending-threshold gate (per_tx_limit / per_period_limit / period_seconds)
  |   A2A task lifecycle (A2A spec v0.2, JSON-RPC over Logos Messaging)
  +--> lez_wallet_module  (NEW — shielded LEZ wallet + programs)
  +--> chat_module        (Logos Core platform)
  +--> delivery_module    (Logos Core platform)
  +--> storage_module     (Logos Core platform)
       |
       v
  LEZ sequencer (testnet / standalone via lez-build)
```

Identity model: NSK (NullifierSecretKey) generated from BIP39 mnemonic on first deploy, encrypted at rest under owner passphrase. NPK (NullifierPublicKey) is the agent's shielded identity, published in the A2A Agent Card. No custodian; the owner's laptop never holds the NSK.

---

## Build instructions

### Prerequisites

- Nix with flakes (`experimental-features = nix-command flakes` in `~/.config/nix/nix.conf`)
- Rust stable + `--features lez-bridge` dependencies (pulled by Cargo)

### Build `lez_wallet_module`

```bash
cd lez-wallet-module/lez-wallet-core
cargo build --release --features lez-bridge
cbindgen --lang C --output ../qt-module/lez_wallet_ffi.h

cd ../qt-module
nix develop            # enters the dev shell with Qt6, logos-cpp-generator, CMake

# Inside nix develop:
export LEZ_WALLET_CORE_DIR=$(pwd)/../lez-wallet-core/target/release
cmake -S . -B build -GNinja -Wno-dev
ninja -C build
# Output: build/liblez_wallet_module_plugin.so
```

### Build `agent_module`

```bash
cd lp-0008-ai-module/scaffold
nix develop /path/to/lez-wallet-module/qt-module   # reuse the same dev shell

# Inside nix develop:
cmake -S . -B build -GNinja -Wno-dev
ninja -C build
# Output: build/libagent_module_plugin.so
```

### Start the local LEZ chain (lez-build)

```bash
cd lez-build
docker-compose up -d   # starts bedrock nodes + sequencer + indexer on localhost:3040
```

The `WalletCore` defaults to `http://127.0.0.1:3040` (from `wallet_config.json`). No external endpoint needed.

### Load in logoscore

```bash
# Start the daemon with both modules
logoscore -D \
  -m lez-wallet-module/qt-module/build/liblez_wallet_module_plugin.so \
  -m lp-0008-ai-module/scaffold/build/libagent_module_plugin.so

# Check wallet balance
logoscore -c "lez_wallet_module.ensure_account(\"mypassphrase\")"
logoscore -c "lez_wallet_module.balance(\"mypassphrase\")"

# List agent skills
logoscore -c "agent_module.meta_skills()"

# Configure the agent
logoscore -c "agent_module.meta_configure(\"owner_address\", \"<your-npk>\")"
logoscore -c "agent_module.meta_configure(\"per_tx_limit\", \"10.0\")"
logoscore -c "agent_module.meta_configure(\"per_period_limit\", \"100.0\")"

# Check agent status
logoscore -c "agent_module.meta_status()"
```

---

## Pre-built artifacts (macOS arm64)

Built on macOS 15.5 / arm64 inside the `logos-module-builder` Nix dev shell:

- `lez-wallet-module/qt-module/liblez_wallet_module_plugin.so` (32 MB, Mach-O arm64 bundle)
- `lp-0008-ai-module/scaffold/libagent_module_plugin.so` (3.7 MB, Mach-O arm64 bundle)

---

## Known limitations and open items

1. **Local chain**: the wallet connects to `http://127.0.0.1:3040` by default (from `wallet_config.json` in the module data dir, defaulting to `WalletConfig::default()`). Run `docker-compose up -d` in `lez-build` before calling any wallet methods. The sequencer address is overridable via `meta_configure("sequencer_addr", "http://...")` or by writing `wallet_config.json` directly.

2. **program_call / program_deploy in provider.rs**: fully implemented. `program_call` parses account IDs + instruction words from JSON, fetches nonces, signs a `PublicTransaction`, and submits via `NSSATransaction::Public`. `program_deploy` reads the binary, derives the RISC-V `ProgramId` via `Program::new`, builds a `ProgramDeploymentTransaction`, and submits via `NSSATransaction::ProgramDeployment`, returning the hex program ID. Both require a running local chain (`docker-compose up -d` in lez-build).

3. **modules().chat_module / delivery_module / storage_module calls**: all wired and typed via `logos_sdk.h` glue, but commented out pending final API-shape verification against logos-core source. The agent compiles and loads; live messaging requires the runtime host.

4. **Inference adapter**: the agent dispatches skills based on incoming messages; the `InferenceAdapter` interface is pluggable and intentionally unbound — the LLM integration is out of scope for this submission and would be operator-supplied.

5. **A2A identity binding**: the Agent Card publishes the NPK as `x-lez-identity.npk`; the deterministic chat-module introBundle derivation from NSK is a known gap (LEARNING.md §9, §10 gap 2).

---

## Files

```
lez-wallet-module/
  lez-wallet-core/           Rust crate: nssa/bedrock_client FFI bridge
    src/provider.rs          Core wallet + program operations
    src/ffi.rs               C FFI exports
    Cargo.toml               crate-type = [cdylib, staticlib, rlib]
  qt-module/
    flake.nix                Nix dev shell (logos-module-builder + cbindgen + Qt6)
    CMakeLists.txt           Build: codegen + compile + link logos-cpp-sdk
    lez_wallet_ffi.h         cbindgen-generated C header (committed)
    src/
      lez_wallet_module_impl.h   Method declarations (StdLogosResult wire types)
      lez_wallet_module_impl.cpp Full implementation via FFI
    metadata.json            Module manifest
    liblez_wallet_module_plugin.so  Pre-built arm64 bundle

lp-0008-ai-module/scaffold/
  src/
    agent_module_impl.h      Full skill surface + spending gate + A2A
    agent_module_impl.cpp    ~1500-line implementation
  interfaces/
    lez_wallet.h             ILezWallet interface contract
    skill.h                  ISkill interface contract
    chat_module_api.h/cpp    Platform stub (ChatModule)
    delivery_module_api.h/cpp Platform stub (DeliveryModule)
    storage_module_api.h/cpp  Platform stub (StorageModule)
  CMakeLists.txt             Build: codegen + compile + link logos-cpp-sdk
  metadata.json              Module manifest
  libagent_module_plugin.so  Pre-built arm64 bundle
```
