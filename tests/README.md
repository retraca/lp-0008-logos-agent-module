# LP-0008 Integration Tests

## What CI does

The CI workflow (`.github/workflows/ci.yml`) has three jobs:

| Job | What it does |
|---|---|
| `lint` | Runs `clang-format --dry-run --Werror` over `scaffold/src/` and `scaffold/interfaces/`. Fails on any formatting divergence. |
| `build` | Installs Nix, builds `scaffold#lib` via `nix build`, asserts that a `.so` and `metadata.json` are produced. Uploads the artifacts. |
| `e2e` | Clones `logos-execution-zone v0.1.2`, builds the standalone sequencer (`sequencer_service --features standalone`), installs `logos-blockchain-circuits v0.4.2` and `r0vm 3.0.5`, starts the sequencer on port 3040, builds the agent_module plugin, then runs `tests/e2e.sh` with `RISC0_DEV_MODE=0` (real proofs). |

The `e2e` job mirrors the structure proven in LP-0002 (`lp-0002-private-multisig`) and LP-0003
(`lp-0003-private-airdrop`).

---

## Running e2e locally

### Prerequisites

1. **Nix with flakes** — `experimental-features = nix-command flakes` in `~/.config/nix/nix.conf`
2. **Rust + r0vm** — `rustup` then install r0vm 3.0.5:
   ```
   curl -sfL -o /tmp/crz.tgz \
     https://github.com/risc0/risc0/releases/download/v3.0.5/cargo-risczero-x86_64-unknown-linux-gnu.tgz
   tar -xzf /tmp/crz.tgz -C ~/.cargo/bin r0vm
   chmod +x ~/.cargo/bin/r0vm
   ```
3. **logos-blockchain-circuits v0.4.2** installed to `~/.logos-blockchain-circuits/`
4. **logos-execution-zone v0.1.2** cloned as a sibling directory named `lez-build`:
   ```
   git clone --depth 1 --branch v0.1.2 \
     https://github.com/logos-blockchain/logos-execution-zone.git \
     ../lez-build
   ```

### Build the sequencer

```bash
cargo build --release -p sequencer_service --features standalone
# binary: ../lez-build/target/release/sequencer_service
```

### Build the agent_module plugin

```bash
nix build ./scaffold#lib --out-link result-agent
# produces: result-agent/lib/libagent_module_plugin.so + result-agent/metadata.json
```

### Start the sequencer

```bash
mkdir -p /tmp/lez-seq-home
RISC0_DEV_MODE=0 RUST_LOG=info \
  ../lez-build/target/release/sequencer_service \
  .github/sequencer_config.json -p 3040 &
```

Wait until `checkHealth` returns success:
```bash
curl -sf -X POST http://127.0.0.1:3040 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"checkHealth","params":[],"id":1}'
```

### Run the demo script

```bash
export RISC0_DEV_MODE=0
export SEQUENCER=http://127.0.0.1:3040
export MODULES_DIR=./result-agent
export LOGOSCORE_BIN=/path/to/logoscore   # from logos-logoscore-cli nix build
# TODO: also set AGENT_MNEMONIC, RECIPIENT_ADDRESS, STORAGE_ENDPOINT
# (see the TODO comments in tests/e2e.sh)
bash tests/e2e.sh
```

---

## TODO stubs — what must be filled in before the script is fully runnable

The script is syntactically valid (`bash -n tests/e2e.sh` passes) and structurally complete.
Three categories of values must be filled in at the **runtime milestone**:

| Constant | Where to set | What it needs |
|---|---|---|
| `AGENT_MNEMONIC` | env var or `sequencer_config.json initial_accounts` | A funded BIP39 mnemonic for the agent's shielded account on the standalone sequencer |
| `RECIPIENT_ADDRESS` | env var | A second Logos chat identity (introBundle or address) that exists on the local sequencer |
| `STORAGE_ENDPOINT` | env var | A running Logos storage node or IPFS-compat gateway reachable from the sequencer host |

Additionally, the `lez_wallet_module` plugin `.so` must be built (Phase 1) and placed in
`MODULES_DIR` alongside the `agent_module` plugin before the `wallet.balance` step will pass.
