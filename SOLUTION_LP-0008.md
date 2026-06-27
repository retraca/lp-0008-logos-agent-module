# Solution: LP-0008 — Autonomous AI Agent Module for Logos Core

## Summary

A Logos Core module that runs an autonomous AI agent with native access to the full Logos
stack: a shielded LEZ wallet, Logos Storage, and Logos Messaging. The agent holds its own
shielded account, stores and retrieves files on Logos Storage, finds other agents over Logos
Messaging using A2A Agent Cards, runs the A2A task lifecycle, and pays peers from its own funds
within owner-set spending limits. The owner deploys it on a headless node with one command and
reaches it from a separate Logos app over an end-to-end encrypted owner channel. Every proof in
the demos is a real RISC0 STARK proof, `RISC0_DEV_MODE=0`. All 27 success criteria are met.

## Repository

- **Repo:** <https://github.com/retraca/lp-0008-logos-agent-module>
- **License:** MIT

## Approach

The agent is two Logos Core modules. `agent_module` is the runtime: skill dispatch, the
spending gate, the owner channel, and A2A coordination. It sits on top of the unmodified
platform modules (delivery for Waku messaging, storage for Codex, chat for the owner channel).
Identity is a shielded LEZ account, so the agent is indistinguishable on-chain from any other
account holder and needs no custodian.

A2A is the right coordination layer because it is the emerging industry standard, but it leaves
two gaps: payment and encrypted transport. Logos fills both. LEZ provides per-task
micropayment, and Logos Messaging provides the encrypted, server-less transport. We implement
A2A as a transport binding over Logos Messaging: Agent Cards follow the A2A schema (extended
with an `x-lez-identity` npk so a peer knows which shielded account to pay), and tasks follow
the A2A lifecycle. A centralised alternative would reintroduce a server that sees every task,
every file, and every payment, which is the thing this design removes.

Key decisions and what did not work:

- **Discovery transport.** The generated `onMessageReceived` wrapper coerces the byte payload to
  an empty object, so the agent never saw peer cards. We subscribe to the raw `messageReceived`
  event through `LpClient` and decode the `{"_bytes":...}` base64 payload ourselves. Two further
  bugs only surfaced once events arrived: the discovered-peers map and `meta_status` ran on
  different module instances (fixed by holding the map in process globals), and the qt_remote
  `onEvent` connects to a dynamic replica before it initializes (a real SDK bug; patch in
  `patches/`). On macOS the patch is necessary but not sufficient, so we proved the full
  two-agent flow on Linux, which is the environment evaluators clone-and-run.
- **Storage skill.** `uploadUrl` returns a session id and the CID arrives on a later
  `storageUploadDone` event; the first cut left this as a stub. We subscribe to that event,
  resolve the CID, and also caught that `uploadUrl` rejects a zero chunk size. The skill now
  does a real upload to a content address and a byte-exact download.
- **Spending fail-safe (R2).** An over-limit spend is held, never executed. We retry the owner
  notification a few times and record the result on the proposal, so a failure to reach the
  owner is reported rather than silently dropped.
- **Qt version.** A plugin built against the default nixpkgs Qt 6.11 will not load in logoscore
  (Qt 6.9.2): "incompatible Qt library." Building with `--override-input nixpkgs <rev-with-6.9.2>`
  fixes it.
- **CLI arg typing.** logoscore's `call` types a bare numeric arg as a JSON number, but the
  module's config values are strings, so `agent up` sent numbers and the spending limit never
  set. Fixed in `agent-cli` by sending numeric config values as JSON strings.

## Success Criteria Checklist

Full per-criterion evidence is in `SUBMISSION.md` (27 DONE / 0 PARTIAL). In brief:

- **F1-F3:** module loads beside the platform modules unmodified (5 modules, 0 crashed); the
  agent owns and funds its own shielded account; `agent up` deploys and configures in one
  command.
- **F4-F5:** owner channel over Logos Messaging plus the Basecamp owner console; the spending
  gate holds above-limit spends for approval and runs below-limit spends autonomously.
- **F6-F8:** 21 documented skills; A2A-compatible Agent Card + task lifecycle over Logos
  Messaging; two agents discover each other (`peer_count=1`), open a task, and pay autonomously
  with a real proof.
- **F9-F11:** storage, messaging, and blockchain use cases demonstrated; three agents deployed
  one per category (`docs/LOCAL_F10_EVIDENCE.md`, `docs/TESTNET_EVIDENCE.md`); full docs + clean
  public repo.
- **U1-U2, R1-R3, P1, S1-S6:** skill SDK; Basecamp owner console; restart-recovery, fail-safe
  notify/hold, skill isolation; CU costs as real RISC0 cycle counts; testnet, CI green, README,
  reproducible demo script, recorded video.

## FURPS Self-Assessment

### Functionality
Loads in Logos Core with the platform modules unmodified. Holds a shielded LEZ account, sends
and receives, deploys with one command, runs a spending gate, exposes 21 skills, speaks A2A,
discovers peers, runs the task lifecycle, and pays autonomously. Stores and retrieves files on
Logos Storage. Limitation: the full A2A receive path is proven on Linux; on macOS an SDK
qt_remote bug blocks cross-module event receive (diagnosed, patched, documented).

### Usability
One command deploys the agent on a headless node (`agent up`). The owner interacts from a
separate Logos app over an end-to-end encrypted channel; the Basecamp owner console
(`basecamp-app/`) surfaces status, approvals, config, and messaging. New skills plug in through
a documented interface (`docs/SKILL_INTERFACE.md`) without touching the core.

### Reliability
Task state and pending approvals persist to the module data dir and survive a restart. An
above-limit spend that cannot reach the owner is retried, reported, and never executed. A
failing skill returns an error value; it does not crash the module or other skills.

### Performance
The compute unit is the RISC0 guest cycle count. A shielded transfer runs 393,216 total /
about 262,500 user cycles across two proofs; public transactions take the no-proof path at 0
cycles. Full table in `docs/CU_COSTS.md`.

### Supportability
CI runs lint, a nix build of the plugin, and an `e2e-dev` integration test against a standalone
LEZ sequencer on every push; green on `main`. README and `SUBMISSION.md` document deployment
and usage. A reproducible demo script (`tests/demo-real.sh`, `tests/demo-f8-linux-full.sh`)
runs the full flow with `RISC0_DEV_MODE=0`.

## Supporting Materials

- **Demo video (full flow, narrated):** <PASTE YOUTUBE LINK HERE>
  Silent source cuts in the repo: `docs/lp0008-f8-linux-demo.mp4` (comprehensive),
  `docs/lp0008-uc-storage.mp4`, `docs/lp0008-uc-messaging.mp4`, `docs/lp0008-uc-blockchain.mp4`
  (one per use case). Narration script: `docs/F8_LINUX_VIDEO_NARRATION.md`.
- **Architecture + write-up:** `ARCHITECTURE.md`, `SUBMISSION.md`, `docs/SECURITY_MODEL.md`.
- **A2A binding spec:** `docs/A2A_BINDING.md`. **Skill SDK:** `docs/SKILL_INTERFACE.md`.
- **Evidence:** `docs/F8_LINUX_FULL_EVIDENCE.txt`, `docs/TESTNET_EVIDENCE.md`,
  `docs/STORAGE_TESTNET_EVIDENCE.md`, `docs/MESSAGING_TESTNET_EVIDENCE.md`,
  `docs/LOCAL_F10_EVIDENCE.md`, `docs/CU_COSTS.md`.
- **CI:** `.github/workflows/ci.yml` (green on `main`).
