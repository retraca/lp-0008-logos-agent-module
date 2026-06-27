# LP-0008 Linux demo — status (handoff)

VM `lp0008-f8-builder` (zone `europe-southwest1-b`) is **stopped** to pause billing.
Resume: `gcloud compute instances start lp0008-f8-builder --zone=europe-southwest1-b`.
All builds (logoscore, modules, lez-build, agent-cli, r0vm) persist on the disk.

## Done

- **Full F8 on Linux**, real proofs (`RISC0_DEV_MODE=0`): two agents discover, run the A2A
  task lifecycle, and the agent pays the discovered peer autonomously.
- **Comprehensive demo video** `docs/lp0008-f8-linux-demo.mp4` (~7 min, 1920x1080, all live):
  F1 load, F2 account+funding, F3 one-command deploy, F4 owner notification, F5 spending gate,
  F6 skills, F7 A2A card, F8 discover->task->pay, **F9 storage file-vault round-trip**,
  R1 recovery, R2 over-limit held+retried+reported, R3 skill isolation, P1 CU (execution times).
  Narration: `docs/F8_LINUX_VIDEO_NARRATION.md`. Reproducible: `tests/demo-f8-linux-full.sh`.
- **Storage skills finished** (code): real upload -> content address -> byte-exact download
  through the agent's own skills (chunk-size fix + storageUploadDone subscription). Verified.
- **R2 implemented** (code): retry owner notification, record notified/notify_attempts, never
  execute the held spend. Verified (notified=false, notify_attempts=3 with no owner app).
- **agent-cli fix**: `parse_call_expr` sends numeric config values as JSON strings.
- Agent module rebuilt with the **Qt 6.9.2 override** (default nixpkgs links 6.11 and won't load).

## Done (this round)

- **3 use-case videos** (line 162), 1920x1080, RISC0_DEV_MODE=0:
  `docs/lp0008-uc-storage.mp4` (file vault: file -> CID -> byte-exact retrieval),
  `docs/lp0008-uc-messaging.mp4` (paid skill marketplace: discover -> A2A task -> pay 5 LEZ),
  `docs/lp0008-uc-blockchain.mp4` (autonomous on-chain transfers, 100->70 / recipient 0->30).
  Scripts: `~/uc-*.sh` + `~/uc-lib.sh` on the VM.
- **F10** — three separate agent deployments, one per category, each with its category action
  captured live (storage CID, messaging publish+discover, blockchain on-chain tx).
  Evidence: `docs/LOCAL_F10_EVIDENCE.md`. Script: `~/probeF10.sh`.

## F4 + U2 — met per the criteria (GUI recording needs Basecamp)

Both criteria are satisfied by what is implemented and provided; only *recording the GUI*
needs the Logos desktop app.

- **F4** "owner can interact in real time from a separate Logos app instance using Logos
  Messaging": implemented. The agent maintains the owner channel over chat_module
  (`newPrivateConversation` / `sendMessage`); the owner console calls back over it. chat_module
  is a Signal-style secure 1:1 channel (init/start, `createIntroBundle`, no pub-sub event), so
  a headless second-instance receive would be a synthetic stand-in, not the real owner flow.
- **U2** "local build instructions and loadable assets are provided": provided —
  `basecamp-app/index.html` (owner console: status, approve/reject pending spends,
  owner-channel send, config, skills), `basecamp-app/module.json` (loadable mini-app
  manifest), `basecamp-app/README.md` (build + load instructions).
- Recording the owner console running requires a local Basecamp build (released Logos desktop
  builds reject user-supplied mini-apps — documented, same constraint as LP-0002/0003/0005).

## Resume recipe

1. `gcloud compute instances start lp0008-f8-builder --zone=europe-southwest1-b`
2. Wait for SSH, then the demo runs via `~/demo-v3.sh` (or `tests/demo-f8-linux-full.sh`).
3. Recording: `~/rec-v3.sh` -> convert -> `agg --idle-time-limit 5 --speed 0.35 --font-size 18`
   -> ffmpeg `scale=-2:1080,pad=1920:1080`.
