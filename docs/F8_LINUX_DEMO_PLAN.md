# LP-0008 Linux demo — plan + command map (narration-ready)

Goal: a complete, explanatory, ~5–6 min screencast that **feels like a person typing real
commands and narrating**, not a fast summary. No unexplained placeholders (`<genesis>`,
`<A>`); every value is either shown real or named in plain language. Every command is
**actually run on the machine** with its real output streaming on screen.

## A. What the criteria require (LP-0008 spec)

Functionality: **F1** module loads with wallet/storage/messaging, unmodified · **F2** agent's
own shielded LEZ account, send+receive · **F3** single-CLI headless deploy · **F4** owner
interacts in real time from a separate app · **F5** spending threshold (above-limit held,
below-limit auto) · **F6** all default skills, documented · **F7** A2A-compatible (Agent
Cards + task lifecycle over Logos Messaging) · **F8** two agents discover + run A2A task +
transfer LEZ autonomously · **F9** ≥3 illustrative use cases e2e on testnet · **F10** 3
testnet agents (one per category) · **F11** docs + clean repo.
Usability **U1** skill SDK, **U2** Basecamp. Reliability **R1** recovery, **R2** fail-safe
above-threshold, **R3** skill isolation. Performance **P1** CU costs. Supportability
**S1–S6** (testnet, CI green, README, reproducible demo script, **recorded video showing
terminal output incl. proof generation with `RISC0_DEV_MODE=0`**).

## B. What Discord told us

- Full-lifecycle demo with `RISC0_DEV_MODE=0` **shown in the video** is the accepted bar
  (LP-0013 was accepted on exactly that). The recording must **show terminal output incl.
  proof generation**.
- The builder must **narrate** — a silent screencast is not sufficient.
- The A2A "does it need a payment, or is a signed task lifecycle enough?" question is
  **unanswered** → show **both** the task lifecycle **and** the payment.
- Evaluators **clone-and-run on their own (Linux) machine** — so this Linux flow is the
  operative environment; macOS qt_remote/Waku limits don't apply to them.
- The only relaxation (PR #66) is the *adoption* criterion (F10), not F8.

## C. Scope of THIS video (and what's deferred + why)

Shown live on the local Linux stack, end to end:
**F1, F2, F5 (gate), F6, F7, F8 (discover → A2A task → pay), F9 (messaging + blockchain),
S5/S6.**
Deferred (already evidenced by the macOS demo `docs/lp0008-demo.mp4`, `docs/TESTNET_EVIDENCE.md`,
and the repo — narrate as "covered in the submission docs"): **F3** `agent up` wrapper,
**F4/U2** Basecamp GUI, **F9-storage** live round-trip, **F10** hosted-testnet agents,
**R/P** reliability/CU.

## D. Command map — every step: header (plain language) → the real command typed → what
streams on screen → the ✓ takeaway. Each value is explained, not abbreviated.

| # | Header (what + why, plain) | Command typed (real) | What you SEE run | ✓ takeaway |
|---|---|---|---|---|
| 0 | "Dev mode is off — the proofs are real." | `echo $RISC0_DEV_MODE` | prints `0` | RISC0_DEV_MODE=0 |
| 1 | "Start the LEZ blockchain locally — a standalone sequencer that produces real zero-knowledge proofs." | `sequencer_service sequencer_config.json -p 3040` | sequencer boot logs, then a `getLastBlockId` call returns the current block | chain live, genesis (the built-in faucet account) holds 10000 test LEZ |
| 2 | "Load the agent into Logos Core, next to the platform modules, without changing them." | `logoscore -D -m ./modules` then `logoscore load-module …` | the daemon's real `Module loaded: …` lines stream for capability, delivery, storage, chat, agent | 5 modules, 0 crashed |
| 3 | "Every capability the agent has, behind a documented interface." | `logoscore call agent_module meta_skills` | the real skills JSON (21 skills) | 21 skills, 6 categories |
| 4 | "Give each agent its own shielded account — its private on-chain identity (NPK = nullifier public key)." | `wallet account new private --label agentA` | the wallet prints the new account + its npk | two independent shielded identities, no custodian |
| 5 | "Publish the agent's A2A Agent Card — the standard other agents read to discover it." | `logoscore call agent_module agent_card` | the real Agent Card JSON (name, npk, skills) | A2A-standard card |
| 6 | "Fund agent A from the faucet account — public→private, a REAL proof. Watch the zkVM run." | `wallet auth-transfer send --from-label genesis --to-npk <agentA-npk> --amount 100` | the RISC0 zkVM executor lines stream, then a tx hash; balance 0→100; block number jumps | real proof, chain advanced |
| 7 | "The two agents find each other over Logos Messaging by exchanging Agent Cards." | `logoscore call agent_module agent_discover <topic>` then `meta_status` | the agent_discover call, then meta_status JSON shows `peer_count: 1` + the peer's npk + 21 skills | discovered over Waku |
| 8 | "Agent A opens an A2A task against the peer it found — the standard task lifecycle." | `logoscore call agent_module agent_task <peer-card> compute.run …` | the real task JSON: task_id, status, price resolved from the card | A2A task lifecycle |
| 9 | "Agent A pays the peer on its own — no human. Another real proof." | `wallet auth-transfer send --from-label agentA --to-npk <agentB-npk> --amount 5` | the zkVM executor lines again, tx hash; A 100→95, B 0→5 | autonomous payment, settled |
| ✓ | criteria checklist on screen | — | the F1/F2/F6/F7/F8/F9/S5/S6 list | — |

### Production rules (from the lambda-prize video bar + this feedback)
- Each command is **typed character-by-character** (visible), then **run live** with its
  **real streaming output** (no `>/dev/null`, no fabricated output).
- Generous **pauses** after each header and before each command so the narrator can speak.
- **Plain-language labels**, not opaque placeholders: "genesis" → "the faucet account";
  long npks shown truncated with a one-line explanation of what an npk is.
- `RISC0_DEV_MODE=0` visible up front and the **zkVM executor output shown during proofs**.
- **1920×1080**, ~5–6 min, ends on the criteria checklist. Narration keyed 1:1.
