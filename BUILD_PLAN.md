# BUILD_PLAN.md — Honest sequenced plan for LP-0008

Prize: $1,200, effort "Large". This plan is sequenced so the **riskiest unknown (the LEZ
wallet bridge) is de-risked first**, before any polish. Read `LEARNING.md` + `ARCHITECTURE.md`
first. Citations there.

## Honest overall assessment

This is a **3–6 week, senior-level** build for one person, and the dollar prize is far below
the effort. The value is the **reusable Logos-native knowledge and the wallet bridge**, not the
$1,200. The module-system, messaging, and storage layers are well documented and tractable. The
project is dominated by **two hard, under-documented integrations**:
1. A **LEZ shielded-wallet Logos module** that does not exist (LEARNING §6d). Biggest risk.
2. **A2A-over-Logos-Messaging binding + identity binding** (LEARNING §9). Second biggest.
Plus an **environment cost**: nothing in the Qt/Logos-Core chain builds without Nix + Qt6.

Confidence by layer: module/build/run **high**; storage **high**; messaging **medium**
(groups + share are agent-built); LEZ wallet/program module **low** (must build + a live testnet
is needed); A2A binding **medium-low**; single-CLI remote deploy **medium** (wrap existing pieces).

---

## Dev-environment setup (what to install/clone to even start)

This machine today (2026-06-06) has `cargo`, `node`, `python3` but **NOT `nix`, `cmake`, `qmake`/Qt6, `go`**.
You cannot build or load a Logos Core module until the toolchain below exists.

Required:
1. **Nix with flakes** (the primary build tool for the whole ecosystem — dev-guide Prerequisites).
   `experimental-features = nix-command flakes` in `~/.config/nix/nix.conf`. This alone pulls Qt6,
   CMake, Ninja, and the SDK into `nix develop` shells, so #2/#3 may not be separately needed.
2. **Qt 6** (Core + RemoteObjects at minimum) if building outside Nix (the CMake path).
3. **Go** (for `go-wallet-sdk`) — only if you also use the EVM wallet/accounts modules.
4. **Rust + Risc0**: `rustup`, then `curl -L https://risczero.com/install | bash && rzup install`
   (LEZ README) — needed for the LEZ wallet bridge and `RISC0_DEV_MODE=0` proofs.
5. **`logos-blockchain-circuits` release** on disk (`LOGOS_BLOCKCHAIN_CIRCUITS=<path>` or
   `~/.logos-blockchain-circuits/`) — required by the LEZ standalone build chain `scaffold setup`
   invokes (scaffold README).
6. **Docker or Podman** — for `logoscore` docker daemon testing and LEZ standalone runs.
7. **A LEZ testnet endpoint** (URL + any basic-auth) — the prize targets "LEZ testnet". The local
   `lez-build` is standalone-sequencer oriented; confirm the testnet exposes the same RPC and
   accepts `ProgramDeploymentTransaction` (LEARNING §10 unknown).

Clone (the build inputs):
- `logos-co/logos-module-builder`, `logos-cpp-sdk`, `logos-liblogos`, `logos-logoscore-cli`,
  `logos-chat-module`, `logos-delivery-module`, `logos-storage-module`,
  `logos-wallet-module`/`logos-accounts-module` (only if EVM needed), `logos-basecamp`.
- `logos-blockchain/logos-execution-zone` (the LEZ chain; you already have `lez-build`).
- `logos-co/scaffold` (`lgs`) — for LEZ program/localnet bootstrap.
- `logos-co/logos-logoscore-py` — for daemon automation in CI/tests.

Smallest first-success check (do this before writing any agent code):
```bash
nix flake init -t github:logos-co/logos-module-builder   # scaffold a hello core module
git init && git add -A && nix build .#lib
nix build 'github:logos-co/logos-module#lm' --out-link ./lm
./lm/bin/lm methods ./result/lib/*_plugin.* --json       # prove the toolchain works
nix build 'github:logos-co/logos-logoscore-cli' --out-link ./logos
./logos/bin/logoscore -m ./result/modules -l <name> -c "<name>.method(x)" --quit-on-finish
```
If that round-trips, the module path is real on this machine. Then tackle LEZ.

---

## Sequenced phases

### Phase 0 — Toolchain + smoke (0.5 week)
Install Nix/Risc0/Docker; run the first-success check above; stand up a LEZ standalone sequencer
via `lgs setup`/`lgs` (scaffold) and run `examples/program_deployment/run_hello_world_private.rs`
with `RISC0_DEV_MODE=0` to confirm proving works. **Exit:** a hello module loads in logoscore AND
a private LEZ tx proves locally.

### Phase 1 — `lez_wallet_module` (THE hard part) (1.5–2 weeks)
Build the missing Logos Core module exposing the shielded wallet + programs (LEARNING §6d).
- Recommended: a **`logos-rust-sdk` provider module** wrapping `nssa` + `bedrock_client` + the
  `wallet` crate's `WalletCore` (Rust↔Rust, avoids reimplementing tx signing).
- Expose: `account_new_private`, `balance`, `send_shielded(recipient, amount)`,
  `history`, `program_query`, `program_call`, `program_deploy(path)`, `sync_private`.
- Persist NSK encrypted in the module data dir; mnemonic on first init.
- **Exit:** from `logoscore call lez_wallet balance` you get the agent's real testnet balance,
  and a shielded transfer between two agent accounts settles on testnet with `RISC0_DEV_MODE=0`.
- Risk: testnet RPC parity (LEARNING §10). If testnet diverges from `lez-build`, this slips.

### Phase 2 — Storage + Messaging skills (1 week)
- Wire `storage_module` (upload/download/manifests) + agent-side encrypt-before-upload + label
  map + share-over-chat (LEARNING §7 gaps).
- Wire `chat_module` owner channel (`newPrivateConversation`, push events) and `delivery_module`
  topics for groups (build group-key distribution; LEARNING §5 gaps).
- **Exit:** personal-file-vault use case works end-to-end (owner sends file → agent encrypts +
  uploads → returns CID → owner retrieves from another instance).

### Phase 3 — Agent module core + skill dispatch + spending gate (1 week)
- Universal `agent_module` with the runtime loop, owner-channel handler, spending-threshold gate
  (ARCHITECTURE §5), pluggable inference adapter, skill registry via `interface_dependencies`
  (ARCHITECTURE §6), `meta.*` skills, pending-task persistence + failure isolation.
- **Exit:** below-threshold spend auto-executes; above-threshold holds for owner approval over
  chat and refuses if owner is unreachable.

### Phase 4 — A2A binding + multi-agent (1 week)
- Agent Card schema + signing + discovery topic; A2A-over-Messaging transport binding; task
  lifecycle; pay-on-accept via Phase 1 (ARCHITECTURE §8).
- Deploy 3 agents (storage / messaging / blockchain categories per the prize) and demo a paid
  task between two of them with autonomous LEZ payment, no human in the loop.
- **Exit:** two agents discover each other, run an A2A task, transfer LEZ — unattended.

### Phase 5 — Single-CLI remote deploy + Basecamp owner UI + CI/demo (1 week)
- A deploy CLI wrapping SSH/container provisioning + `logoscore -D` + `lgpm` install + initial
  funding (no native primitive; LEARNING §10 gap 6; reuse `logoscore-py` `LogoscoreDockerDaemon`).
- A `ui_qml` owner-chat module for Basecamp (note: released Basecamp rejects user modules — use a
  **local Basecamp build**; LEARNING §8).
- Integration tests against a standalone sequencer in CI (prize requirement), green default branch,
  reproducible demo script with `RISC0_DEV_MODE=0`, recorded video showing proof generation.

---

## Hard parts, ranked
1. **`lez_wallet_module`** (Phase 1) — no module exists; testnet RPC parity unverified; ZK proving
   time/CU costs unknown. This is the make-or-break.
2. **A2A binding + identity binding** (Phase 4 + ARCHITECTURE §3) — authoring a new A2A transport
   binding and deterministically binding the messaging address to the LEZ NPK (no native link).
3. **Group messaging + storage encryption/share** — chat is 1:1 only; storage is plain CID; both
   need agent-built crypto (group keys, file encryption).
4. **Single-CLI remote deploy** — assembled from `logoscore -D` + container/SSH + `lgpm`; no
   one-shot primitive ships today.
5. **Environment + Basecamp caveats** — Nix/Qt6/Risc0 install; released Basecamp won't load
   user modules; LGX `-dev` variant naming bug needs a `postInstall` workaround (LEARNING §8).

## Smaller scope option (if the goal is learning, not the full prize)
Phases 0–3 alone (toolchain → wallet bridge → storage/messaging → agent + threshold) prove the
entire Logos-native stack and yield a reusable `lez_wallet_module`. That is the high-learning,
high-reuse core; A2A multi-agent + remote-deploy + Basecamp polish (Phases 4–5) are the long tail
that the $1,200 does not justify on its own.
