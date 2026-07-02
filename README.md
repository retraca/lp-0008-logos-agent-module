# LP-0008 — Autonomous AI Agent Module for Logos Core

A Logos Core module that gives an AI agent its own shielded LEZ wallet, Logos Storage, and
Logos Messaging address. The agent runs headless on any remote node, is reachable from any
Logos Basecamp instance via end-to-end encrypted chat, and coordinates with peer agents over
the A2A protocol — with Logos Messaging as the transport and LEZ micropayments filling the gap
A2A deliberately leaves open.

The owner deploys with a single CLI command (`agent up`). No server configuration, no exposed
APIs, no custodian.

---

## Architecture

```
        Owner's laptop (Logos Basecamp / basecamp-app/)
+-----------------------------------------------+
|  owner_chat_ui (ui_qml / Basecamp mini-app)   |
|  one-command deploy: agent-cli  `agent up`    |
+-----------------------------------------------+
          |  Logos Messaging (E2E, owner channel)
          v
  Remote node (logoscore -D, headless)
+-----------------------------------------------+
|  agent_module  [core, universal C++]          |
|   runtime loop / skill dispatcher             |
|   owner channel handler + spend-threshold     |
|   A2A binding (cards, task lifecycle)         |
|   pluggable inference adapter                 |
|        |         |          |         |       |
|        v         v          v         v       |
|  chat_module  delivery  storage  lez_wallet   |
|               _module   _module   _module     |
+-----------------------------------------------+
          |
          v  sequencer RPC + Risc0 real proofs
   LEZ sequencer (testnet.lez.logos.co / standalone)
```

Skills are discrete, composable units loaded at runtime without recompiling the core module.
Third parties can add skills by implementing `ISkill` in a separate Logos module; see
[docs/SKILL_INTERFACE.md](docs/SKILL_INTERFACE.md).

---

## What is verified

All evidence files are in `docs/`.

| Capability | Verified | Key evidence |
|---|---|---|
| 6/6 Logos Core modules load, 0 crashed | Yes | `docs/EVIDENCE_LOCAL.md` — agent + lez_wallet + storage + chat + delivery + capability |
| Agent has its own shielded LEZ account | Yes | `docs/TESTNET_EVIDENCE.md` (testnet, since reset) + reproducible local real-proof: the agent funds and holds its own shielded account in `docs/F8_LINUX_FULL_EVIDENCE.txt` |
| Agent can send AND receive tokens (real proofs, `RISC0_DEV_MODE=0`) | Yes | reproducible local real-proof (`docs/lp0008-f8-linux-demo.mp4`, `docs/F8_LINUX_FULL_EVIDENCE.txt`): agent funded 0→100 (receive) and pays a peer 100→95 (send), both `RISC0_DEV_MODE=0`. Historical testnet capture: `docs/TESTNET_EVIDENCE.md` (since reset) |
| Spending threshold: below-limit auto-executes | Yes | `docs/EVIDENCE_LOCAL.md` §A2A — `pending_approval` / `approve_pending` flow with balance changes |
| Spending threshold: above-limit → pending approval → execute | Yes | `docs/SECURITY_MODEL.md` + `docs/EVIDENCE_LOCAL.md` |
| A2A: Agent Card (A2A schema + x-lez extensions), discover/task/subscribe over Logos Messaging | Yes | `docs/EVIDENCE_LOCAL.md` §1a–1c; `docs/A2A_BINDING.md` |
| A2A: autonomous discover → price-resolution → task-open loop (agent-driven) | Yes | `docs/EVIDENCE_LOCAL.md` §1a–1c |
| F8 full flow on Linux: two agents discover, run the A2A task, pay autonomously | Yes | `docs/lp0008-f8-linux-demo.mp4` and `docs/F8_LINUX_FULL_EVIDENCE.txt`: peer_count=1, agent pays the discovered peer with a real proof (agent 100->95, peer 0->5), `RISC0_DEV_MODE=0` |
| Owner cross-instance channel | Yes | `docs/EVIDENCE_LOCAL.md` §3 — 2nd logoscore client over owner token |
| Three testnet agents created + funded with native LEZ (real proofs) | Yes | reproducible local per-category: `docs/LOCAL_F10_EVIDENCE.md` (one agent each for storage/messaging/blockchain). Live LEZ v0.2.0 testnet: `docs/TESTNET_EVIDENCE_V020.md` (3 shielded agents funded, tx RPC-confirmed) |
| Blockchain agent outbound shielded transfer settled on testnet | Yes | reproducible local real-proof: agent pays a discovered peer (real proof, settled) in `docs/lp0008-f8-linux-demo.mp4`. Live LEZ v0.2.0 testnet: `docs/TESTNET_EVIDENCE_V020.md` (3 shielded agents funded, tx RPC-confirmed) |
| Single-command deploy (`agent up`) | Yes | `agent-cli/` |
| Basecamp owner mini-app | Yes | `basecamp-app/` |
| CI lint passes; nix build | Yes | `.github/workflows/ci.yml` |
| Real-proof e2e demo script | Yes | `tests/demo-real.sh` |
| Demo videos (`RISC0_DEV_MODE=0` visible) | Yes; voice narration pending | **`docs/lp0008-agent-demo.mp4`** — the full flow through the agent's own skills (deploy, npk+vpk card, 21 skills, real-proof funding, autonomous F8 pay). Plus 3 use-case cuts (`lp0008-uc-{storage,messaging,blockchain}.mp4`). Silent screencasts; narration scripts in `docs/VIDEO_NARRATION.md`. |

**Notes:**

- **CU costs (P1):** the compute unit is the RISC0 guest cycle count (the zkVM work the network
  verifies per transaction). `docs/CU_COSTS.md` records real cycle counts per operation: a shielded
  transfer runs 393,216 total / about 262,500 user cycles across two proofs; public transactions
  take the no-proof path at 0 cycles. The sequencer RPC carries no CU field, and a builder confirmed
  on Discord that local-sequencer cycle evidence is accepted.
- **Owner UI (U2):** the Basecamp owner console (`basecamp-app/`) ships with build instructions and
  loadable assets. Recording it running needs a local Basecamp build, since released Logos desktop
  builds reject user mini-apps (the same constraint as LP-0002, LP-0003, and LP-0005).
- **Narration:** the demo videos are silent cuts; the builder records the voice-over, which the
  prize requires.

---

## Quick-start deploy

```bash
# 1. Single-command deploy (agent-cli): loads the agent next to the wallet/platform
#    modules and configures the spending threshold in one invocation.
agent up \
  --modules-dir ./result-agent \      # dir of built module bundles (nix build .#lib)
  --owner <YOUR-NPK-HEX> \            # owner account the agent notifies for approvals
  --per-tx-limit 10.0 \              # LEZ; above this, the agent asks the owner
  --per-period-limit 100.0 \
  --detach                          # leave the daemon running in the background
#   global: --sequencer http://127.0.0.1:3040  (default; point at your sequencer)

# 2. Inspect / drive the agent
agent status                         # balance, storage usage, active tasks
logoscore call agent_module meta_skills     # list all 21 skills
# Owner-side chat is the Basecamp owner mini-app (basecamp-app/) over the E2E owner channel.
```

> Funding: the agent's shielded account is funded with a real wallet transfer
> (`wallet auth-transfer send --to <agent-address> --amount N`), not the `agent fund`
> convenience wrapper (which is an unfinished helper — see Known limitations).

### Manual deploy (against a local or hosted sequencer)

```bash
# Build
nix build .#lib
# produces scaffold/build/libagent_module_plugin.so + lez_wallet_module .so

# Start local sequencer (standalone)
cd lez-build
./target/release/sequencer_service /tmp/lez-seq-config.json -p 3040

# Launch daemon with both modules
RISC0_DEV_MODE=0 logoscore -D \
  -m lez-wallet-module/qt-module/build/liblez_wallet_module_plugin.so \
  -m lp-0008-ai-module/scaffold/build/libagent_module_plugin.so

# Configure and verify
logoscore call agent_module meta_configure per_tx_limit 10
logoscore call agent_module meta_skills
logoscore call agent_module meta_status
```

---

## Running tests and the real-proof demo

**Prerequisite — build the stack once (from a clean clone):**

```bash
# Builds the LEZ sequencer+wallet (from logos-execution-zone v0.2.0) and the module bundles,
# then assembles ./runtime-modules. Needs nix + a Rust/risc0 toolchain + logoscore on PATH.
bash scripts/setup.sh
```

Then run the real-proof demo:

```bash
# Lint + build (CI)
nix flake check

# Real-proof end-to-end demo — self-bootstrapping (starts its own sequencer + daemon).
# setup.sh prints the LEZ_BUILD / MODULES_DIR to pass; defaults are auto-detected.
LEZ_BUILD=~/logos-execution-zone MODULES_DIR=./runtime-modules bash tests/demo-real.sh
```

`tests/demo-real.sh` starts its own LEZ sequencer + logoscore daemon, loads the platform + agent
modules (F1), creates the agent's own shielded account (F2), funds it on the live chain, and has
the agent pay a fresh peer from its own funds with a **real RISC0 proof** (F8) — all with
`RISC0_DEV_MODE=0`. It **exits non-zero** if the real-proof payment does not settle, so a passing
run is never a false claim. Override `LOGOSCORE_BIN`, `LEZ_BUILD`, `MODULES_DIR`, `SEQ_CONFIG`,
`SEQ_PORT` for your layout. The settled payment (agent 100→95, peer 0→5) is also recorded in
`docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md`. See `tests/README.md` for what each step asserts.

> `tests/e2e.sh` is a **template** for a fully-scripted multi-agent run and requires configured
> account constants; the runnable real-proof path is `tests/demo-real.sh` (above), and the
> CI integration test is `tests/e2e-dev.sh` (standalone sequencer, runs on every push).

---

## Default skills

| Category | Skills |
|---|---|
| Storage | `storage.upload` `storage.download` `storage.list` `storage.share` |
| Messaging | `messaging.send` `messaging.join` `messaging.create_group` |
| Wallet | `wallet.balance` `wallet.send` `wallet.history` |
| Programs | `program.query` `program.call` `program.deploy` |
| A2A coordination | `agent.card` `agent.discover` `agent.task` `agent.subscribe` `agent.cancel` |
| Meta | `meta.skills` `meta.status` `meta.configure` |

---

## Documentation

| Document | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Component overview, runtime, event loop, reliability design |
| [docs/SKILL_INTERFACE.md](docs/SKILL_INTERFACE.md) | Third-party skill contract (`ISkill`), registration, step-by-step tutorial |
| [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md) | What the agent can/cannot do without owner approval; key model; threat surface |
| [docs/A2A_BINDING.md](docs/A2A_BINDING.md) | A2A transport binding over Logos Messaging; Agent Card schema; task lifecycle; payment model |
| [docs/EVIDENCE_LOCAL.md](docs/EVIDENCE_LOCAL.md) | M6 local evidence: 6/6 modules loaded; A2A flow; real-proof payment settled (tx `96724ec5`) |
| [docs/TESTNET_EVIDENCE_V020.md](docs/TESTNET_EVIDENCE_V020.md) | **Live LEZ v0.2.0 testnet (current):** 3 shielded agents funded + shielded agent→peer payment, all tx RPC-confirmed |
| [docs/TESTNET_EVIDENCE.md](docs/TESTNET_EVIDENCE.md) | Earlier hosted testnet capture: 3 agents created + funded; Blockchain agent send settled (nullifier `43d571cf`) |
| [docs/CU_COSTS.md](docs/CU_COSTS.md) | CU cost documentation and platform limitation (no RPC CU field); timing proxy |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Full deployment guide: prerequisites, build, load, configure |
| [SUBMISSION.md](SUBMISSION.md) | Full success-criteria checklist with per-item evidence and gap mapping |

---

## Testnet agent accounts

Three agents deployed on the live `https://testnet.lez.logos.co` (LEZ `v0.2.0`, real proofs,
`RISC0_DEV_MODE=0`, 2026-07-02). Each holds its own **shielded** account, funded from genesis;
every tx below is confirmed via `getTransaction`. Full detail: [`docs/TESTNET_EVIDENCE_V020.md`](docs/TESTNET_EVIDENCE_V020.md).

| Agent | Shielded account | Funded | Funding tx (on-chain ✓) |
|---|---|---|---|
| Blockchain | `Private/g4zEiJNJDUWfAMC676xgfX6GSNKhY8dZ98mMjW4Qou2` | 100 LEZ | `d02ccbd1c98da606…` |
| Storage | `Private/3bxcGTCZ4kHVcGbzK5fh8QbGYaSoRDrBGYuL47uTHwUj` | 100 LEZ | `7eeb53e0fd8b8ce3…` |
| Messaging | `Private/H8g2yrEcMYp8jn35717GwbXdkSML7YU1gPk74s7b8USU` | 100 LEZ | `ba428afdbf0467ab…` |

Funding source, confirmed RPC-side: `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV`
balance 9998 → 9698, nonce 2 → 5 (three transfers). The Blockchain agent then paid a peer 30 LEZ
from its own shielded funds (tx `7133cbd112a7b860…`, balance 100 → 70).

---

## Status per spec success criterion

| Criterion | Status | Notes |
|---|---|---|
| Module loads alongside wallet/storage/messaging | DONE | 6/6 modules, 0 crashed — `docs/EVIDENCE_LOCAL.md` |
| Agent's own shielded LEZ account; send + receive | DONE | Testnet + local, real proofs — `docs/TESTNET_EVIDENCE.md` |
| Single CLI deploy (`agent up`) | DONE | `agent-cli/` |
| Owner cross-instance channel | DONE | 2nd client over owner token — `docs/EVIDENCE_LOCAL.md` §3 |
| Spending threshold gate | DONE | Below-limit auto; above-limit pending_approval — `docs/EVIDENCE_LOCAL.md` |
| All 21 default skills implemented + documented | DONE | `scaffold/src/agent_module_impl.cpp`; `ARCHITECTURE.md §7` |
| A2A-compatible: Agent Card, task lifecycle, transport binding documented | DONE | `docs/A2A_BINDING.md` |
| Two agents discover + task + pay LEZ autonomously | DONE | Verified live on Linux: `peer_count=1`, A2A task opened, agent pays the discovered peer with a real proof (agent 100->95, peer 0->5). `docs/lp0008-f8-linux-demo.mp4`, `docs/F8_LINUX_FULL_EVIDENCE.txt` |
| 3 illustrative use cases end-to-end | DONE | Blockchain: shielded agent pays a peer on live LEZ `v0.2.0` testnet (`docs/TESTNET_EVIDENCE_V020.md`); Storage: cross-node CID round-trip on Codex testnet; Messaging: two-node Waku relay (`docs/STORAGE_TESTNET_EVIDENCE.md`, `docs/MESSAGING_TESTNET_EVIDENCE.md`) |
| 3 agents (one per skill category) deployed | DONE | Three shielded agents (Blockchain/Storage/Messaging) funded on live LEZ `v0.2.0` testnet, real proofs, tx hashes RPC-confirmed — `docs/TESTNET_EVIDENCE_V020.md`. Also reproducible per-category on a local standalone sequencer (`docs/LOCAL_F10_EVIDENCE.md`). |
| Full documentation | DONE | `docs/` |
| Third-party skill interface (ISkill) | DONE | `scaffold/interfaces/skill.h`; `docs/SKILL_INTERFACE.md` |
| Owner interface from Basecamp | DONE | `basecamp-app/`; owner channel verified |
| Recovers from transient failures (task state persisted) | DONE | Module data dir persistence — `ARCHITECTURE.md §2` |
| Above-threshold tx not executed if owner unreachable | DONE | Retry-then-fail — `docs/SECURITY_MODEL.md` |
| Skill failures isolated | DONE | Each `invoke()` wrapped; errors as values — `docs/SKILL_INTERFACE.md` |
| CU cost documented | DONE | CU = RISC0 guest cycles; real counts per operation in `docs/CU_COSTS.md` (393,216 total / ~262,500 user cycles per shielded transfer) |
| Module deployed + tested on testnet | DONE | Wallet built from LEZ `v0.2.0` (matches the hosted chain — `check-health` ✅); three shielded agents funded + a shielded agent→peer payment on live `testnet.lez.logos.co`, all real proofs, tx hashes RPC-confirmed — `docs/TESTNET_EVIDENCE_V020.md` |
| E2E integration tests in CI | DONE | `e2e-dev` job runs on every push against a standalone LEZ sequencer (`tests/e2e-dev.sh`): health, block production, plugin validity, tx path |
| CI green on default branch | DONE | Lint passes; build via nix |
| README documents end-to-end usage | DONE | This file + `SUBMISSION.md` |
| Reproducible demo script, `RISC0_DEV_MODE=0` | DONE | `tests/demo-real.sh` |
| Recorded video demo (terminal output, `RISC0_DEV_MODE=0`) | Silent cuts done; voice narration pending (builder) | `docs/lp0008-agent-demo.mp4` (the agent flow) + 3 use-case cuts; narration scripts `docs/VIDEO_NARRATION.md` |

---

## License

MIT. See [LICENSE](LICENSE).
