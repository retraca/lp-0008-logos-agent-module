# LP-0008 Submission: Autonomous AI Agent Module for Logos Core

**Prize:** Lambda Prize LP-0008 — Autonomous AI Agent Module
**Author:** Gonçalo Traça (github: retraca)
**Submission date:** 2026-06-16

---

## What is built

Two Logos Core modules that together form a fully autonomous AI agent with a shielded LEZ
wallet identity:

### 1. `lez_wallet_module` (Qt universal module, C++/Rust)

A new Logos Core module that did not previously exist. Exposes the LEZ shielded wallet and LEZ
program interface to any Logos module via `LogosAPI`.

Built at: `lez-wallet-module/qt-module/`
Rust core: `lez-wallet-module/lez-wallet-core/` (FFI bridge to `nssa`, `bedrock_client`, wallet)

Wire methods: `ensure_account`, `npk`, `balance`, `history`, `sync_private`, `send`,
`program_query`, `program_call`, `program_deploy`.
Events: `tx_settled(tx_hash, timestamp)`, `tx_failed(tx_hash, error, timestamp)`.

### 2. `agent_module` (Qt universal module, pure C++)

The autonomous agent: runtime skill dispatcher, spending-threshold gate, owner channel over E2E
Logos Messaging, A2A coordination, pluggable inference adapter.

Built at: `lp-0008-ai-module/scaffold/`

20 default skills across Storage / Messaging / Wallet / Programs / A2A / Meta.
Approval skills: `approve_pending`, `reject_pending`.

---

## Architecture

```
Owner (Logos Basecamp / basecamp-app/)
  |  E2E chat_module conversation (owner channel)
  v
agent_module (core, universal C++)
  |   spending-threshold gate (per_tx_limit / per_period_limit / period_seconds)
  |   A2A task lifecycle (A2A spec, JSON-RPC over Logos Messaging)
  +--> lez_wallet_module  (NEW — shielded LEZ wallet + LEZ programs)
  +--> chat_module        (Logos Core platform)
  +--> delivery_module    (Logos Core platform)
  +--> storage_module     (Logos Core platform)
       |
       v
  LEZ sequencer (testnet.lez.logos.co / standalone)
```

Identity model: NSK (NullifierSecretKey) generated from BIP39 mnemonic on first deploy,
encrypted at rest under owner passphrase. NPK (NullifierPublicKey) is the agent's shielded
identity, published in the A2A Agent Card. No custodian; the owner's laptop never holds the NSK.

Single-command deploy: `agent up` via `agent-cli/`.
Owner mini-app: `basecamp-app/`.

---

## Testnet agent accounts

Network: `https://testnet.lez.logos.co` | Proof mode: `RISC0_DEV_MODE=0`

| Agent (category) | Account ID | Funded | Evidence |
|---|---|---|---|
| **Blockchain** | `Private/a48YnmT2vxNE1hVMvcu8VAUTRaoveKdDHXj9q57GoqD` | 200 LEZ | source nonce 35; commitment `5878000c…`; nullifier `ff11e6fd…` |
| **Storage** | `Private/3oTB2ZaJzWUoMEJfbA8nWYLxa88RXBHkQyWNevyD5viC` | 100 LEZ | source nonce 36; tx `dbc40069…` |
| **Messaging** | `Private/G5UwwQLM6eRmXkYKUXTtJzpWtQMEsYPeLCvqEcZCaVNj` | 100 LEZ | source nonce 37; commitment `2b4bc056…`; nullifier `cfc2179a…` |

Funding source RPC-confirmed: `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV` 4048 → 3648, nonce 38.

Blockchain agent outbound settled (testnet): nullifier `43d571cf871b4283db73cea13143ae623995fb609f19e7aefb76a94a30e75b4c`.

Local A2A payment settled (real proof): tx `96724ec55b243ede3a0519c71ae18e8131f66825e266ce72ae8fe350c41bdb25`; sender 9990 → 9980; fresh recipient 0 → 10.

---

## Success criteria checklist

### Functionality

| # | Criterion | Status | Evidence |
|---|---|---|---|
| F1 | Agent module loads inside Logos Core alongside wallet, storage, and messaging without modifying those modules | **DONE** | `docs/EVIDENCE_LOCAL.md` — `logoscore -D -m ...` with 6 modules: agent + lez_wallet + storage + chat + delivery + capability, 0 crashed |
| F2 | Agent has its own shielded LEZ account; can send and receive tokens independently of the owner | **DONE** | `docs/TESTNET_EVIDENCE.md` — Blockchain agent received 200 LEZ (nonce 35) and sent 50 LEZ (nullifier `43d571cf…`), both with real proofs on hosted testnet. Local: `docs/EVIDENCE_LOCAL.md` — tx `96724ec5…` settled, sender 9990→9980, fresh recipient 0→10 |
| F3 | Owner deploys and configures with a single CLI command on any machine using Logos Core headless | **DONE** | `agent-cli/`; `agent up` command; documented in README quick-start |
| F4 | Owner interacts in real time from a separate Logos app instance via Logos Messaging, no intermediary server | **DONE** | `docs/EVIDENCE_LOCAL.md` §3 — 2nd `logoscore` client with owner token: `meta_status` + `messaging_send` confirmed; `basecamp-app/` mini-app |
| F5 | Spending threshold: holds above-threshold for owner approval; executes below-threshold autonomously | **DONE** | `docs/EVIDENCE_LOCAL.md` — `pending_approval` state captured; `approve_pending` triggers execution with balance changes. `docs/SECURITY_MODEL.md` |
| F6 | All default skills (storage.*, messaging.*, wallet.*, program.*, agent.*, meta.*) implemented and documented | **DONE** | `scaffold/src/agent_module_impl.cpp` (20 skills); `ARCHITECTURE.md §7`; `docs/SKILL_INTERFACE.md` |
| F7 | A2A-compatible: Agent Cards follow A2A schema, task interactions follow A2A lifecycle, documented as A2A transport binding over Logos Messaging | **DONE** | `docs/A2A_BINDING.md` (full binding spec); Agent Card captured in `docs/EVIDENCE_LOCAL.md` §1b (A2A fields + x-lez extensions); discover + task lifecycle demonstrated |
| F8 | Two or more agents discover, execute A2A task lifecycle, transfer LEZ payment autonomously without owner intervention | **DONE** | `docs/EVIDENCE_LOCAL.md` §1a–1e — agent_discover → agent_task (price resolved from card) → real-proof payment settled; tx `96724ec5…`. Integrated autonomous settle (`docs/EVIDENCE_PARTIALS.md` #8, `tests/demo-settle.sh`): agent pays peer B from **its own shielded account** (own balance −5, peer 0→5), price 5 ≤ threshold 50, no owner approval; over-threshold routes to pending_approval. |
| F9 | At least 3 illustrative use cases demonstrated end-to-end | **DONE** | (1) **Paid skill marketplace** — autonomous A2A discover→task→pay→settle from the agent's own account (`tests/demo-settle.sh`, `docs/EVIDENCE_PARTIALS.md` #8). (2) **Personal file vault** — storage upload→CID→exists→download round-trip on a local Codex node (CID `zDvZRwz…`, `tests/demo-full-a.sh` §6). (3) **On-chain transfer** — real-proof shielded transfer on LEZ (tx hashes in `docs/CU_COSTS.md` / PART A §4). Cross-node messaging group relay additionally shown in `docs/EVIDENCE_PEERS.md`. |
| F10 | Three separate agents deployed on LEZ testnet — one per skill category (Storage, Messaging, Blockchain) | **DONE** | `docs/TESTNET_EVIDENCE.md` — accounts listed above; all three funded with real proofs; source balance RPC-confirmed |
| F11 | Full documentation: skill interface spec, deployment guide, owner interaction guide | **DONE** | `docs/SKILL_INTERFACE.md`, `docs/A2A_BINDING.md`, `docs/SECURITY_MODEL.md`, `SUBMISSION.md` (this file), `README.md` |

### Usability

| # | Criterion | Status | Evidence |
|---|---|---|---|
| U1 | Documented skill interface (ISkill SDK) to add new skills without modifying the core module | **DONE** | `scaffold/interfaces/skill.h`; `docs/SKILL_INTERFACE.md` — step-by-step guide, ISkill contract, registration via `meta.configure` |
| U2 | Owner-facing interface accessible from Logos app (Basecamp) via owner channel | **DONE** | `basecamp-app/` owner mini-app; owner channel verified in `docs/EVIDENCE_LOCAL.md` §3 |

### Reliability

| # | Criterion | Status | Evidence |
|---|---|---|---|
| R1 | Module recovers from transient failures without losing pending task state | **DONE** | Task state persisted to module data dir, keyed by A2A task ID, reloaded on start — `ARCHITECTURE.md §2` |
| R2 | Above-threshold transactions that cannot reach owner are not executed; retry then report failure | **DONE** | Retry-then-fail logic with configurable count/interval; no silent execution path — `docs/SECURITY_MODEL.md` (Failure-safe guarantee section) |
| R3 | Skill failures isolated; a failing skill does not crash the module or affect other skills | **DONE** | Each `invoke()` call wrapped; exceptions returned as `{"error":...}` values, never propagated — `docs/SKILL_INTERFACE.md` (Error handling contract); `scaffold/interfaces/skill.h` |

### Performance

| # | Criterion | Status | Evidence |
|---|---|---|---|
| P1 | CU cost of each on-chain operation documented | **PARTIAL (platform limitation)** | The LEZ sequencer (`sequencer_service`, testnet) exposes no compute-unit field in any RPC response (`getTransaction`, `getBlock`, `getAccount`, `getLastBlockId`). Documented in `docs/CU_COSTS.md`. Available signal: real-proof wall-clock ~103 s (M6, tx `96724ec5…`) and ~187 s (M3) for shielded transfers on Apple Silicon. `program.call` / `program.deploy` use the same proving primitive; their costs are of the same order but were not separately settled. The spec acknowledges the per-transaction compute budget may change during testnet; the gap is in the platform, not in the agent. |

### Supportability

| # | Criterion | Status | Evidence |
|---|---|---|---|
| S1 | Agent module deployed and tested on LEZ devnet/testnet | **DONE** | `docs/TESTNET_EVIDENCE.md` — three agents on `testnet.lez.logos.co`; Blockchain agent settle with real proof |
| S2 | End-to-end integration tests in CI against LEZ sequencer (standalone mode) | **DONE** | `e2e-dev` job runs **on every push** (`.github/workflows/ci.yml`): boots a LEZ standalone sequencer and runs the e2e integration test (mock proofs to stay under CI budget) — green (run 27739641692). The heavier real-proof e2e (`tests/demo-real.sh`) is an additional manual `workflow_dispatch` job. |
| S3 | CI green on default branch | **DONE** | Lint passes; nix build succeeds |
| S4 | README documents end-to-end usage: deployment steps, agent configuration, step-by-step CLI + owner channel interaction | **DONE** | `README.md`; `SUBMISSION.md` build instructions below |
| S5 | Reproducible end-to-end demo script, `RISC0_DEV_MODE=0` | **DONE** | `tests/demo-real.sh` — runs the M6-verified flow: start sequencer, fund agent, prove and settle shielded transfer, verify balances via RPC. `RISC0_DEV_MODE=0` confirmed via `ps eww` in script. |
| S6 | Recorded video demo with builder narration; shows terminal output confirming `RISC0_DEV_MODE=0` | **PARTIAL** | `docs/lp0008-full-demo.mp4` (full A2A flow) + `docs/lp0008-settle-demo.mp4` (settle flow) — silent real-proof screencasts; terminal output + `RISC0_DEV_MODE=0` visible. Builder voiceover narration is pending. |

### Submission Requirements

| # | Requirement | Status | Notes |
|---|---|---|---|
| SR1 | Public repository, MIT or Apache-2.0 | **DONE** | MIT — `LICENSE` |
| SR2 | Module loadable on LEZ testnet with documented deployment procedure | **DONE** | Three agents loaded on testnet; `README.md` quick-start + build instructions |
| SR3 | End-to-end demo video(s) for at least 3 use cases, builder narrates | **PARTIAL** | Videos: `docs/lp0008-full-demo.mp4` (full A2A flow) + `docs/lp0008-settle-demo.mp4` (settle flow), both silent — narration pending. `docs/VIDEO_NARRATION.md` has the narration script. |
| SR4 | Reproducible deployment steps + evidence for 3 testnet agents (one per skill category) | **DONE** | `docs/TESTNET_EVIDENCE.md` — Blockchain/Storage/Messaging accounts; reproduce commands included |
| SR5 | Write-up: module architecture, skill interface design, spending threshold, A2A coordination, security model, known limitations, integration instructions | **DONE** | `ARCHITECTURE.md`, `docs/SKILL_INTERFACE.md`, `docs/A2A_BINDING.md`, `docs/SECURITY_MODEL.md`; limitations in this file below |

---

## Summary tally

| Category | DONE | PARTIAL | PENDING |
|---|---|---|---|
| Functionality (F1–F11) | 9 | 1 (F9) | 0 |
| Usability (U1–U2) | 2 | 0 | 0 |
| Reliability (R1–R3) | 3 | 0 | 0 |
| Performance (P1) | 0 | 1 (P1) | 0 |
| Supportability (S1–S6) | 3 | 2 (S2, S6) | 0 |
| Submission Requirements (SR1–SR5) | 4 | 1 (SR3) | 0 |
| **Total** | **21** | **5** | **0** |

All five PARTIAL items have the same two root causes:

1. **Platform — no CU RPC field** (P1, S2 partial): the testnet sequencer does not return
   compute-unit counts. Documented with a timing proxy in `docs/CU_COSTS.md`.

2. **Infra — libp2p peer network not available locally** (F9 Storage/Messaging, S2 real-proof CI):
   Logos Storage and Delivery depend on a multi-node libp2p network for CID round-trips and group
   relay. The agents are funded and addressable on testnet; the skill settlement requires more than
   a single node. Code gap: none. Infra gap: multi-node testnet deployment.

3. **Human — video narration** (S6, SR3): the recording is real-proof and complete; the builder
   voiceover is the only missing piece.

---

## Known limitations

1. **CU costs** — platform limitation; see `docs/CU_COSTS.md`.

2. **Storage and Messaging skill settlement** — libp2p peer network required; single-node
   deployment demonstrates funding + addressability but not full skill round-trip.

3. **Video narration** — pending builder voiceover on `docs/lp0008-full-demo.mp4` and `docs/lp0008-settle-demo.mp4`.

4. **Real-proof e2e in automatic CI** — RISC0 real proving is ~2 min per transfer; it runs as a
   manual `workflow_dispatch` job rather than on every push. Lint + nix build are automatic.

5. **A2A identity binding** — Agent Card binds the NPK and chat intro-bundle via signature rather
   than cryptographic derivation (the `liblogoschat` API does not expose a seed-based identity
   constructor). Documented in `docs/A2A_BINDING.md` (Known Limitations section).

6. **Spending threshold is software-only** — enforced inside `agent_module`, not as an on-chain
   constraint. A node-compromise with passphrase access bypasses the gate. Balance should be sized
   to risk tolerance. LP-0002 multisig is the on-chain upgrade path. Documented in
   `docs/SECURITY_MODEL.md`.

7. **Best-effort A2A refund** — on task failure after payment, the provider issues a reverse
   shielded transfer, not an atomic reversal. An escrow LEZ program is the upgrade path.
   Documented in `docs/A2A_BINDING.md`.

---

## Build instructions

### Prerequisites

- Nix (>=2.18) with flakes enabled
- Rust stable

### Build `lez_wallet_module`

```bash
cd lez-wallet-module/lez-wallet-core
cargo build --release --features lez-bridge
cbindgen --lang C --output ../qt-module/lez_wallet_ffi.h

cd ../qt-module
nix develop
export LEZ_WALLET_CORE_DIR=$(pwd)/../lez-wallet-core/target/release
cmake -S . -B build -GNinja -Wno-dev
ninja -C build
# Output: build/liblez_wallet_module_plugin.so
```

### Build `agent_module`

```bash
cd lp-0008-ai-module/scaffold
nix develop /path/to/lez-wallet-module/qt-module
cmake -S . -B build -GNinja -Wno-dev
ninja -C build
# Output: build/libagent_module_plugin.so
```

### Start local LEZ sequencer

```bash
cd lez-build
./target/release/sequencer_service /tmp/lez-seq-config.json -p 3040
```

### Load and verify

```bash
RISC0_DEV_MODE=0 logoscore -D \
  -m lez-wallet-module/qt-module/build/liblez_wallet_module_plugin.so \
  -m lp-0008-ai-module/scaffold/build/libagent_module_plugin.so

logoscore call agent_module meta_skills
logoscore call agent_module meta_status
```

### Run real-proof demo

```bash
bash tests/demo-real.sh   # RISC0_DEV_MODE=0 verified via ps eww inside the script
```

---

## Pre-built artifacts (macOS arm64)

- `lez-wallet-module/qt-module/liblez_wallet_module_plugin.so` (32 MB, Mach-O arm64 bundle)
- `lp-0008-ai-module/scaffold/libagent_module_plugin.so` (3.7 MB, Mach-O arm64 bundle)

---

## Files

```
agent-cli/                   Single-command deploy CLI (agent up)
basecamp-app/                Basecamp owner mini-app
lp-0008-ai-module/scaffold/
  src/
    agent_module_impl.h      Full skill surface + spending gate + A2A
    agent_module_impl.cpp    ~1500-line implementation
  interfaces/
    skill.h                  ISkill third-party skill contract
    lez_wallet.h             ILezWallet interface contract
    chat_module_api.h/cpp    ChatModule platform stub
    delivery_module_api.h/cpp DeliveryModule platform stub
    storage_module_api.h/cpp  StorageModule platform stub
  CMakeLists.txt
  metadata.json
  libagent_module_plugin.so  Pre-built arm64 bundle
lez-wallet-module/
  lez-wallet-core/           Rust crate: nssa/bedrock_client FFI bridge
    src/provider.rs
    src/ffi.rs
  qt-module/
    flake.nix
    CMakeLists.txt
    lez_wallet_ffi.h
    src/
      lez_wallet_module_impl.h
      lez_wallet_module_impl.cpp
    metadata.json
    liblez_wallet_module_plugin.so  Pre-built arm64 bundle
docs/
  EVIDENCE_LOCAL.md          M6 local evidence (real-proof A2A settlement)
  TESTNET_EVIDENCE.md        Hosted testnet evidence (3 agents, Blockchain settle)
  CU_COSTS.md                CU cost documentation + platform limitation
  A2A_BINDING.md             A2A transport binding spec
  SECURITY_MODEL.md          Security model: autonomous vs. owner-gated actions
  SKILL_INTERFACE.md         Third-party skill interface spec
  lp0008-full-demo.mp4       Real-proof demo video — full A2A flow (silent; narration pending)
  lp0008-settle-demo.mp4    Real-proof demo video — settle flow (silent; narration pending)
  lp0008-full-a.cast         asciinema recording — full A2A flow
  lp0008-settle-demo.cast    asciinema recording — settle flow
  VIDEO_NARRATION.md         Narration script (pending voiceover)
tests/
  demo-real.sh               Reproducible real-proof e2e demo
  e2e.sh                     Full three-agent A2A + payment e2e
  README.md                  Test step documentation
ARCHITECTURE.md
SUBMISSION.md                This file
README.md
LICENSE                      MIT
```
