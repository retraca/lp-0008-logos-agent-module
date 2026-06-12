# Logos Agent Module — LP-0008

Autonomous AI agent module for Logos Core. Lambda Prize LP-0008 submission.

## What this is

Two Logos Core universal modules that together form a fully autonomous AI agent with a shielded LEZ wallet identity.

### `lez_wallet_module`

A new Logos Core Qt universal module exposing the LEZ shielded wallet to any other module via `LogosAPI`. Previously, no module existed for this. The Rust core (`lez-wallet-core`) wraps `nssa`, `bedrock_client`, and `wallet` behind a C FFI.

Wire methods: `ensure_account`, `npk`, `balance`, `history`, `sync_private`, `send`, `program_query`, `program_call`, `program_deploy`.

Pre-built arm64 bundle: `lez-wallet-module/qt-module/liblez_wallet_module_plugin.so` (33 MB).

### `agent_module`

Autonomous skill dispatcher with spending-threshold gate, owner channel (E2E via `chat_module`), A2A task coordination, and pluggable inference adapter. Implements all 15 default skills across Storage, Messaging, Wallet/Blockchain, A2A, and Meta categories.

Pre-built arm64 bundle: `scaffold/libagent_module_plugin.so` (3.7 MB).

## Quick start

```bash
# Load both modules into Logos Core headless
logoscore -D \
  -m lez-wallet-module/qt-module/liblez_wallet_module_plugin.so \
  -m scaffold/libagent_module_plugin.so

# Create the agent's shielded LEZ account
logoscore -c 'lez_wallet_module.ensure_account("mypassphrase")'

# Configure the agent
logoscore -c 'agent_module.meta_configure("per_tx_limit", "10.0")'
logoscore -c 'agent_module.meta_configure("per_period_limit", "100.0")'
logoscore -c 'agent_module.meta_configure("owner_address", "<your-npk>")'

# Check balance
logoscore -c 'lez_wallet_module.balance("mypassphrase")'

# List skills
logoscore -c 'agent_module.meta_skills()'

# Get A2A agent card
logoscore -c 'agent_module.agent_card()'
```

## Run the demo

```bash
# Against local LEZ chain (docker-compose up in lez-build/)
./demo.sh

# Against testnet
SEQUENCER=https://testnet.lez.logos.co ./demo.sh
```

The demo creates two agent wallets, fetches NPKs, checks balances, deploys a LEZ program, calls it, and queries state.

## Structure

```
lez-wallet-module/
  lez-wallet-core/           Rust crate — NSK keystore, key derivation, WalletCore bridge
    src/provider.rs          All async wallet + program operations
    src/ffi.rs               C FFI exports for Qt module
    tests/integration_test.rs  Integration tests (require local chain)
  qt-module/
    src/lez_wallet_module_impl.{h,cpp}  Qt universal module implementation
    metadata.json            Module manifest
    liblez_wallet_module_plugin.so  Pre-built arm64 bundle

scaffold/                    agent_module
  src/
    agent_module_impl.h      Full skill surface + spending gate + A2A + owner channel
    agent_module_impl.cpp    1492-line implementation
  interfaces/
    lez_wallet.h             ILezWallet interface contract
    skill.h                  ISkill interface contract
    chat_module_api.h/cpp    Platform stub
    delivery_module_api.h/cpp  Platform stub
    storage_module_api.h/cpp   Platform stub
  metadata.json              Module manifest (module.json)
  libagent_module_plugin.so  Pre-built arm64 bundle

lez-build/                   Embedded lez-build workspace (stubs for CI; full tree needed for lez-bridge)
docs/
  DEPLOYMENT.md              Step-by-step deployment guide
ARCHITECTURE.md              Module architecture, skill interface, A2A binding, security model
SUBMISSION.md                Full build instructions and known limitations
LEARNING.md                  Logos stack API research notes (cited by ARCHITECTURE.md)
demo.sh                      End-to-end demo script
```

## Security model

The agent's NSK lives only on the node where `logoscore` runs, encrypted at rest with AES-256-GCM under an Argon2id key derived from the owner passphrase. The owner's laptop never holds the agent's NSK. Above-threshold transactions are never submitted without explicit owner approval over the E2E owner channel.

## Spending threshold

Configured via `meta_configure`. Three parameters:

| Key | Meaning |
|-----|---------|
| `per_tx_limit` | Maximum single-transaction amount (decimal LEZ) for autonomous action |
| `per_period_limit` | Maximum total spend in one rolling period |
| `period_seconds` | Rolling period duration in seconds |

Above-threshold calls queue a pending proposal and notify the owner via the owner channel. `approve_pending(proposal_id)` / `reject_pending(proposal_id)` resolve it.

## A2A compatibility

`agent.card()` returns a spec-compliant A2A Agent Card (A2A 0.2) with LEZ identity extension (`x-lez-identity.npk`) and per-skill LEZ price declarations. Logos Messaging replaces A2A's HTTP transport. On task acceptance the agent submits a shielded LEZ transfer for the declared price before starting work.

## Building from source

See `docs/DEPLOYMENT.md` for full build instructions. The Qt modules require the Logos SDK Nix dev shell; `lez-wallet-core` builds standalone with `cargo build --release` (default features) or with the full lez-build tree (`--features lez-bridge`).

## License

MIT OR Apache-2.0
