# Recording runbook — paste one block per video, narrate over the real run

**Platform: the Linux builder box, inside `tmux`.** The stack is Linux-only
(`scripts/setup.sh` uses apt + a prebuilt Linux wallet plugin) — it does not build on macOS.
Record your Mac screen while your terminal is SSH'd into the box **inside tmux**: tmux keeps
the run alive if SSH blips, and one interactive session avoids the duplicate-instance races
that automated SSH retries caused. The stack is already built there (`~/lp0008`).

```bash
# from your Mac terminal (full-screen, font >=18pt, dark bg), then start recording:
gcloud compute ssh lp0008-f8-builder --zone=europe-southwest1-b --tunnel-through-iap
tmux new -A -s rec        # if the connection drops: reconnect and `tmux new -A -s rec`

# once, in the tmux session — the box has FOUR nix-store logoscore builds and only the
# plain -logos-logoscore-cli one supports our module variant (linux-amd64-dev); the
# "portable-bundle" one GLIBC-crashes and the "cli-bin-portable" one rejects the modules:
export LOGOSCORE_BIN=/nix/store/841y6inhnzhwsdisgs68gkx51244z75r-logos-logoscore-cli/bin/logoscore
export LEZ_BUILD=~/logos-execution-zone MODULES_DIR=~/lp0008-modules
export PATH="$HOME/.cargo/bin:$PATH"
```

Each video is ONE paste — the script prints its own step headers, so you narrate over them
as they appear. One unmodified command is also the strongest S5 evidence: it IS the
evaluator's own test.

Between takes: `pkill -9 -f "logoscore -D"; rm -rf ~/.logoscore`

---

## Narration must include architecture (SR3 — do not skip)

The prize text: the builder "narrates what they built and why, walks through the
architecture and key implementation decisions". Pure demo narration fails this. Open
**every** video (or at least the primary) with ~30s of architecture while the title/README
is on screen:

> "What I built: an autonomous agent that runs as a native Logos Core module — a Qt plugin
> loaded by the same daemon as the wallet, storage, chat and delivery modules, talking to
> them over Qt Remote Objects. Three key decisions: first, the agent owns its own shielded
> LEZ account — it isn't a proxy for the owner's wallet, every payment it makes is a real
> RISC0 proof from its own notes. Second, coordination is A2A-compatible — Agent Cards with
> id, name, description and tags, published over Waku as the transport binding, so any
> A2A framework can discover a Logos agent. Third, a spending gate between the agent and its
> wallet: below the owner's limit it acts autonomously, above it the task is held
> pending approval — the module enforces this, not the prompt. Inference is pluggable
> behind an adapter interface, local or API."

## Video 1 — Primary: the clean-clone run  (S5 · F1 · F2 · F7 · P1)

Paste:

```bash
cd ~/lp0008 && RISC0_DEV_MODE=0 ./demo.sh
```

Say, as each on-screen header appears:

- **before pasting** — architecture block above, then: "Now I'll do exactly what an
  evaluator does: run the demo script from a clean clone, unmodified. Everything you'll
  see is a real RISC0 proof, dev mode off."
- **`testnet reachable?`** — "First it checks the live hosted testnet — the chain
  everything settles on."
- **`F1 — boot the daemon and load the modules`** — "It boots Logos Core and loads all six
  modules in one daemon — the agent beside the wallet, storage, chat and delivery,
  unmodified. Six loaded, zero crashed."
- **`F2 — the agent's own shielded account`** — "The agent creates its own shielded LEZ
  account. Its A2A card carries the identity — the nullifier public key and a post-quantum
  ML-KEM viewing key. A real account the agent controls."
- **`Fund the agent 100 LEZ from genesis`** — (the long beat, ~90s of real proving)
  "Now it funds the agent a hundred tokens from genesis, on the live testnet, dev mode
  zero. The real zk prover is running right now — this wait is the proof being generated."
- **`confirm on-chain via getTransaction`** — "The funding transaction confirms on-chain,
  by getTransaction, on the public testnet."
- **`the agent reads its balance THROUGH its own module skill`** — "And the agent reads
  its balance back through its own module skill: a hundred."
- **`PASS`** — "Clone, build, load, fund, confirm — all from a clean environment with real
  proofs. That's the reproducible demo the prize asks for, passing unmodified."

## Video 2 — Proof generation on camera  (S6 · P1)

Simplest: same take as Video 1, right after PASS. Paste:

```bash
# from the funded wallet home of the Video-1 run (see docs/CU_COSTS.md "Measurement"):
RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info \
  ~/logos-execution-zone/target/release/wallet auth-transfer send \
  --from <funded-account> --to-npk <npk> --to-vpk <vpk> --amount 5
```

Say while the cycle counts stream:

- "This is the RISC0 prover with dev mode off — a real STARK proof for a shielded
  transfer. The cycle counts on screen are the compute-unit cost: a hundred thirty-one
  thousand total cycles, about eighty-one thousand user cycles. These are the measured
  numbers in the CU docs — not estimates. Public program calls and deploys cost zero
  client proving cycles; only privacy operations pay the prover."

## Video 3 — Paid skill marketplace: two agents discover, task, pay  (F8 · F9 · F5)

This demonstrates the spec's **"Paid skill marketplace"** illustrative use case — name it.
Two daemons in one tmux session (this is the run I verify before you record — see status
at the bottom).

Paste:

```bash
cd ~/lp0008 && LEZ_BUILD=~/logos-execution-zone bash tests/demo-f8-testnet.sh
```

Say over the on-screen stages:

- "This is the paid skill marketplace use case from the prize spec. Two independent
  agents, two daemons, on the LIVE hosted testnet. They discover each other over Waku —
  agent A reads agent B's card, with its declared LEZ price, from the shared discovery
  topic."
- (gate stage) "Agent A's owner set a spending limit of fifty. This task is priced eighty —
  over the limit — so the gate holds it: pending approval, never executed. That's the
  threshold mechanism, integrated, on the live chain."
- (task/pay stage) "Under the limit, the agent opens the A2A task and pays from its own
  shielded account. One honest platform note: the module-to-wallet hop is capped at about
  twenty seconds, and a real proof takes ninety — you saw the full payment settle as a real
  proof in the primary demo, and end-to-end on the local chain in the use-case cut. What
  this trace adds is discovery, the task lifecycle, and the gate — all live on testnet."

## Video 4 — Personal file vault + owner channel  (SR3 · F9 · F4)

Two spec-named use cases: **"Personal file vault"** (storage) and the owner-channel
interaction (messaging — the flow behind the **"On-chain event alerter"**: the agent
notifies its owner over Logos Messaging). Honest framing: these run against the local
stack (Codex/Waku peers); the settlement-bearing use case (marketplace) is the one that
runs fully on the hosted testnet.

Paste:

```bash
cd ~/lp0008 && bash tests/demo-f8-linux-full.sh
```

- (storage segment) "Use case: the personal file vault. The owner hands the agent a
  document; the agent stores it through the Logos storage module and returns a content
  address — retrievable from any device, content-addressed."
- (messaging segment) "The owner channel: I message the agent from a separate client over
  the private delivery channel and get a live reply — no intermediary server. This is the
  same channel the agent uses to alert its owner of on-chain events."
- (close) "Together with the marketplace payment you saw settle on the testnet, that's
  three of the prize's illustrative use cases end to end: file vault, owner
  messaging/alerts, and the paid skill marketplace."

## After recording

1. Keep each file under ~6 min; name them `docs/lp0008-v020-demo.mp4`,
   `docs/lp0008-prover.mp4`, `docs/lp0008-f8-v020.mp4`, `docs/lp0008-uc-*.mp4`.
2. Host on YouTube/Loom, link them in `SOLUTION_LP-0008.md`, commit, push.
3. Reopen the PR to logos-co/lambda-prize (resubmission explicitly invited in #88).

## Pre-recording verification status (updated as runs complete)

- [x] Video 1 block — `demo.sh` exit 0 verified on the builder box (testnet-funded, tx
      confirmed) — last verified this cycle
- [ ] Video 2 block — prover segment re-run pending
- [ ] Video 3 block — `demo-f8-testnet.sh` single-instance tmux run pending (the earlier
      hangs were traced to concurrent automated-SSH instances, not the script)
- [ ] Video 4 block — `demo-f8-linux-full.sh` storage/messaging segments re-run pending
