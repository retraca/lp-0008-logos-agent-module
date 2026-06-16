# LP-0008 — Autonomous AI Agent Module for Logos Core

A Logos Core module that gives an AI agent its own shielded LEZ wallet, Logos Storage, and
Logos Messaging address. The agent runs headless on any remote node, is reachable from any
Logos Basecamp instance via end-to-end encrypted chat, and coordinates with peer agents over
the A2A protocol — with Logos Messaging as the transport and LEZ micropayments filling the gap
A2A deliberately leaves open. The owner deploys with a single CLI command; no server
configuration, no exposed APIs, no custodian.

---

## Architecture

```
        Owner's laptop (Logos Basecamp)
+-----------------------------------------------+
|  owner_chat_ui (ui_qml)                       |
|   one-command deploy CLI                      |
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
          v  sequencer RPC + Risc0 proofs
   LEZ sequencer (testnet / standalone)
```

Skills are discrete, composable units loaded at runtime without recompiling the core module.
See [docs/SKILL_INTERFACE.md](docs/SKILL_INTERFACE.md) for the third-party skill contract.

---

## Quick-start deploy

```bash
# 1. Install Nix with flakes (one-time, any machine)
curl --proto '=https' --tlsv1.2 -sSf https://install.determinate.systems/nix | sh
nix run nixpkgs#nixFlakes -- --version   # verify

# 2. Build the module
nix build .#lib
# produces ./result/lib/agent_module_plugin.so + metadata.json

# 3. Deploy to a remote node (headless logoscore)
logos-agent deploy \
  --node ssh://user@your-node \
  --owner-key ~/.logos/keys/owner.key \
  --spend-threshold 1.0              \   # LEZ; above this requires owner approval
  --module ./result/lib/agent_module_plugin.so

# 4. Interact from Basecamp (any laptop with your keys)
logos-agent chat   # opens owner channel; type `meta.skills()` to list capabilities
```

> Prerequisites: Nix (>=2.18) with flakes enabled. The build pulls Qt6, CMake, and all
> Logos SDK dependencies from the locked flake inputs — no manual toolchain installation.

---

## Documentation

| Document | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Component overview, runtime, event loop, reliability design |
| [docs/SKILL_INTERFACE.md](docs/SKILL_INTERFACE.md) | Third-party skill contract, registration, step-by-step tutorial |
| [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md) | What the agent can/cannot do without owner approval; key model; threat surface |
| [docs/A2A_BINDING.md](docs/A2A_BINDING.md) | A2A transport binding over Logos Messaging; Agent Card schema; task lifecycle |
| [BUILD_PLAN.md](BUILD_PLAN.md) | Phase-by-phase build roadmap; toolchain setup; gap analysis |
| [LEARNING.md](LEARNING.md) | Grounded API citations from the real Logos repos |

---

## Running the end-to-end demo

```bash
# Start a standalone LEZ sequencer (RISC0_DEV_MODE=0 for real proofs)
export RISC0_DEV_MODE=0
# ... follow sequencer setup in BUILD_PLAN.md Phase 0 ...

# Then run the reproducible e2e demo
bash tests/e2e.sh
```

`tests/e2e.sh` deploys three agents (Storage, Messaging, Blockchain skill categories), runs
an A2A task-lifecycle exchange between two of them, verifies LEZ payment, and reports pass/fail.
See [tests/README.md](tests/README.md) for what each step asserts and how to read the output.

Video demo: `docs/lp0008-demo.cast` (asciinema recording) — play with `asciinema play docs/lp0008-demo.cast`.
A full `.mp4` render is linked in the submission write-up (not committed; see [docs/REPO_MANIFEST.md](docs/REPO_MANIFEST.md)).

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

## Status and known limitations

**What is complete (design and interface layer):**
- Full skill surface defined in `scaffold/src/agent_module_impl.h` (20 prize skills)
- Third-party skill contract `scaffold/interfaces/skill.h`
- Proposed `lez_wallet_module` contract `scaffold/interfaces/lez_wallet.h`
- Architecture, security model, A2A binding, and skill interface fully documented

**What is pending (implementation):**
- `scaffold/src/agent_module_impl.cpp` — the runtime implementation (requires the Nix
  toolchain and a working `lez_wallet_module`)
- `lez_wallet_module` itself — the shielded-wallet backend does not yet exist in Logos Core;
  this is the central build gap (see LEARNING.md S6d and BUILD_PLAN.md Phase 1)
- Testnet deployments of the three required agents — pending toolchain setup (BUILD_PLAN Phase 0)
- E2E demo video with terminal output confirming `RISC0_DEV_MODE=0` — pending real testnet run
- CI green on the default branch — `.github/workflows/ci.yml` is ready; will go green once
  `nix build` succeeds against a working implementation

The scaffold compiles to a loadable `.so` that exports the correct Qt Remote Objects interface
and wires the module into `logoscore`'s module registry. It is not yet functionally complete.

---

## License

MIT. See [LICENSE](LICENSE).
