# Recording runbook — paste one block per video, narrate over the real run

You record your screen (QuickTime / OBS, 1920×1080, terminal full-screen, font ≥18pt,
dark background). Each video is ONE paste — the script prints its own step headers, so you
narrate over them as they appear. Pasting one command is also the strongest evidence for S5:
it IS the evaluator's own test, unmodified.

Prep once, before recording anything:

```bash
git clone https://github.com/retraca/lp-0008-logos-agent-module ~/lp0008 && cd ~/lp0008
bash scripts/setup.sh        # builds LEZ v0.2.0 + modules; do this OFF camera (long)
export PATH="$HOME/lp0008/bin:$PATH"   # wherever setup put logoscore; adjust if different
```

Between takes: `pkill -9 -f "logoscore -D"; rm -rf ~/.logoscore` for a clean state.

---

## Video 1 — Primary: the clean-clone run  (S5 · F1 · F2 · F7 · P1)

Paste (on camera — start with the clone so the clean-clone claim is visible):

```bash
cd ~/lp0008 && RISC0_DEV_MODE=0 ./demo.sh
```

Say, as each on-screen header appears:

- **before pasting** — "This is LP-0008. I'll do exactly what an evaluator does: run the demo
  script from a clean clone, unmodified. Everything you'll see is a real RISC0 proof, dev mode off."
- **`testnet reachable?`** — "First it checks the live hosted testnet — that's the chain
  everything settles on."
- **`F1 — boot the daemon and load the modules`** — "It boots Logos Core and loads all six
  modules in one daemon — the agent beside the wallet, storage, chat and delivery, unmodified.
  Six loaded, zero crashed."
- **`F2 — the agent's own shielded account`** — "The agent creates its own shielded LEZ account.
  Its A2A card carries the identity — the nullifier public key and a post-quantum ML-KEM viewing
  key. A real account the agent controls."
- **`Fund the agent 100 LEZ from genesis`** — (this is the long beat, ~90s of real proving)
  "Now it funds the agent a hundred tokens from genesis, on the live testnet, dev mode zero.
  The real zk prover is running right now — this wait is the proof being generated."
- **`confirm on-chain via getTransaction`** — "The funding transaction confirms on-chain,
  by getTransaction, on the public testnet."
- **`the agent reads its balance THROUGH its own module skill`** — "And the agent reads its
  balance back through its own module skill: a hundred."
- **`PASS`** — "Clone, build, load, fund, confirm — all from a clean environment with real
  proofs. That's the reproducible demo the prize asks for, passing unmodified."

## Video 2 — Proof generation on camera  (S6 · P1)

Paste:

```bash
RISC0_DEV_MODE=0 RISC0_INFO=1 $HOME/logos-execution-zone/target/release/wallet \
  auth-transfer send --from Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV \
  --to rcpt --amount 5
```

(Use the funded wallet home from Video 1: `export LEE_WALLET_HOME_DIR=<the fund home>` —
or simplest: run this segment immediately after demo.sh in the same take.)

Say while the cycle counts stream:

- "This is the RISC0 prover with dev mode off — a real STARK proof for a shielded transfer.
  The cycle counts on screen are the compute-unit cost: a hundred thirty-one thousand total
  cycles, about eighty-one thousand user cycles. These are the measured numbers in our CU
  docs — not estimates. Public program calls and deploys cost zero client proving cycles;
  only privacy operations pay the prover."

## Video 3 — F8: two agents discover, task, and pay  (F8 · F9)

Needs the multi-node shell (two daemons — works on this Mac, not on a small VM).

Paste:

```bash
cd ~/lp0008 && LEZ_BUILD=~/logos-execution-zone bash tests/demo-f8-testnet.sh
```

Say over the on-screen stages:

- "Two independent agents, two daemons. They discover each other over Waku — agent A reads
  agent B's card, with its price, from the network."
- (gate stage) "Agent A's owner set a spending limit. The task is over the limit, so the gate
  holds it — pending approval, never executed. Under the limit, it runs."
- (payment stage) "Approved — and agent A pays agent B autonomously, from its own shielded
  account, a real proof on the live testnet. Discovery, task, payment — no human in the loop."

## Video 4 — Use-case cuts  (SR3 · F9: vault + marketplace)

File vault (Codex peers up first):

```bash
cd ~/lp0008 && bash tests/demo-f8-linux-full.sh    # storage + messaging segments
```

- (storage segment) "Use case one: a private file vault. The agent stores a document through
  the storage module and gets a content ID back — retrievable, content-addressed."
- (messaging segment) "Use case two: the owner messages the agent over the private delivery
  channel and gets a live reply — no server in between."
- (payment leg, if shown) "Use case three you've already seen end-to-end: the paid marketplace —
  discovery, a priced skill, and autonomous shielded payment."

Optional bonus — Basecamp GUI against the FUNDED wallet (beats #99's errored clip):
build basecamp locally, load `basecamp-app/` assets, then on camera in the chat UI:
`meta.status` · `agent.card` · `wallet.balance` · `wallet.send` over the limit → `pending_approval`.

## After recording

1. Keep each file under ~6 min; name them `docs/lp0008-v020-demo.mp4`,
   `docs/lp0008-prover.mp4`, `docs/lp0008-f8-v020.mp4`, `docs/lp0008-uc-*.mp4`.
2. Host on YouTube/Loom, link them in `SOLUTION_LP-0008.md`, commit, push.
3. Reopen the PR to logos-co/lambda-prize (resubmission was explicitly invited in #88).
