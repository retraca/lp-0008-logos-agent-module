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
export LEZ_BUILD=~/logos-execution-zone
export PATH="$HOME/.cargo/bin:$PATH"

# fresh clone for the take (NOTE: ~/lp0008 is an OLD monorepo dir — do not use it).
# ~/lp0008-clean already exists verified; re-clone on camera if you want the clone visible:
git clone https://github.com/retraca/lp-0008-logos-agent-module ~/lp0008-demo
cd ~/lp0008-demo
```

Each video is ONE paste — the script prints its own step headers, so you narrate over them
as they appear. One unmodified command is also the strongest S5 evidence: it IS the
evaluator's own test.

Between takes: `pkill -9 -f "logoscore -D"; rm -rf ~/.logoscore`

---

## Narration must include architecture (SR3 — do not skip)

The prize text: the builder "narrates what they built and why, walks through the
architecture and key implementation decisions". Pure demo narration fails this. Open the
primary with the full ~30s block below, and EVERY other video with a one-line recap
("This is LP-0008 — an autonomous agent running as a native Logos Core module with its own
shielded account, an A2A coordination layer over Waku, and an owner-set spending gate."):

> "What I built, and why: agents that hold their own keys and pay for their own services,
> with no custodian and no payment processor — an autonomous agent that runs as a native
> Logos Core module — a Qt plugin
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
cd ~/lp0008-demo && RISC0_DEV_MODE=0 ./demo.sh
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
# self-contained: fresh recipient, then a shielded transfer from genesis with the prover
# streaming its segments + cycle counts (see docs/CU_COSTS.md "Measurement")
export LEE_WALLET_HOME_DIR=$(mktemp -d) W=~/logos-execution-zone/target/release/wallet
echo '{"sequencer_addr":"https://testnet.lez.logos.co/","seq_poll_timeout":"60s","seq_tx_poll_max_blocks":80,"seq_poll_max_retries":40,"seq_block_poll_max_amount":200}' > $LEE_WALLET_HOME_DIR/wallet_config.json
printf "demo-pass\n" | $W account import public --private-key 10a26a9aec7d34b82364eeae45c5294dbb0a764b000b94eeb9b58511dc487c4d
RCPT=$(printf "demo-pass\ndemo-pass\n" | $W account new private -l rcpt 2>&1)
NPK=$(echo "$RCPT" | grep -oE 'npk [0-9a-f]{64}' | awk '{print $2}'); VPK=$(echo "$RCPT" | grep -oE 'vpk [0-9a-f]+' | awk '{print $2}')
printf "demo-pass\n" | RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info \
  $W auth-transfer send --from Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV \
  --to-npk $NPK --to-vpk $VPK --amount 5
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
cd ~/lp0008-demo && bash tests/demo-f8-testnet.sh
```

Say over the on-screen stages:

- "This is the paid skill marketplace use case from the prize spec. Two independent
  agents, two daemons, on the LIVE hosted testnet. They discover each other over Waku —
  agent A reads agent B's card, with its declared LEZ price, from the shared discovery
  topic."
- (gate stage) "Agent A's owner set a spending limit of fifty. This task is priced eighty —
  over the limit — so the gate holds it: pending approval, never executed. That's the
  threshold mechanism, integrated, on the live chain."
- (before the pay stage) "One honest platform note before the payment: the module-to-wallet
  hop is capped at about twenty seconds, and a real proof takes ninety — so on the shared
  testnet the in-module pay can get cut mid-proof. You saw the full payment settle as a real
  proof in the primary demo, and end-to-end on the local chain in the use-case video."
- (task/pay stage) "Under the limit, the agent opens the A2A task against the discovered
  card and initiates the pay from its own shielded account."
- (RESULT line) read it as printed — e.g. "discovery, the A2A task, and the gate — integrated,
  on the live testnet. That's what this trace adds on top of the local end-to-end run."

## Video 4 — Use cases ON the live testnet  (F9 · SR3: vault + alerter)

Two spec-named use cases with the agent DEPLOYED ON THE HOSTED TESTNET — no framing
needed: the alerter watches a real on-chain state change (the genesis funding tx), the
vault runs under the same testnet-funded agent. Verified exit 0 (UC1 owner notified,
UC2 byte-exact, funding tx getTransaction-confirmable).

Paste:

```bash
cd ~/lp0008-demo && bash tests/demo-usecases-testnet.sh
```

Say over the on-screen stages:

- (deploy) "Same boot as the primary — the agent wired to the live hosted testnet."
- (UC1 armed) "Use case: the on-chain event alerter. The agent's watch loop reads its LEZ
  account on the testnet — balance zero."
- (funding, prover lines streaming) "Now a real on-chain event: genesis funds the agent —
  that's the prover again, dev mode zero."
- (state change) "The watch loop sees the state change on the live chain — zero to a
  hundred — and the agent alerts its owner over Logos Messaging. No server, no webhook —
  an encrypted message to the owner's key."
- (UC2 vault) "Use case: the personal file vault, by this same testnet-funded agent. The
  owner hands it a file, it returns a content address, and the retrieval is byte-exact."
- (close/PASS) "With the paid-marketplace trace you saw in the previous video, that's
  three of the prize's use cases, end to end, with the agent live on the testnet."

## Video 5 — Reliability + the full local payment flow  (R1 · R2 · R3 · F5 · F9)

The full 12-step local run: single-command deploy, vault, discovery, the gate holding
with owner notification, the under-limit payment with BOTH balances moving, the 10b
alerter, restart-recovery, and skill isolation.

Paste:

```bash
cd ~/lp0008-demo && bash tests/demo-f8-linux-full.sh
```

- (step 6, storage) "Use case one: the personal file vault. The owner hands the agent a
  document; the agent stores it through the Logos storage module and returns a content
  address — retrieved back byte-exact."
- (step 9, gate) "The spending gate: an over-limit task is held, the owner is notified over
  Logos Messaging — three retry attempts, recorded — and the spend never executes."
- (step 10, pay) "The under-limit payment: the same transfer the agent's pay skill issues,
  run here through the wallet CLI from the agent's own account — a real proof, and both
  balances move: A drops to ninety-five, B receives five."
- (step 10b, alerter) "Use case two: the on-chain event alerter. The agent watches its LEZ
  account, sees the balance change from the payment, and notifies the owner over Logos
  Messaging — no server in between."
- (steps 11-12) "Reliability on camera: kill the daemon, restart — the held approval
  survives. And a failing skill errors in isolation while the module stays up."
- (close) "That's three of the prize's illustrative use cases end to end: the personal
  file vault, the on-chain event alerter, and the paid skill marketplace."

## After recording

1. Keep each file under ~6 min; name them `docs/lp0008-v020-demo.mp4`,
   `docs/lp0008-prover.mp4`, `docs/lp0008-f8-v020.mp4`, `docs/lp0008-uc-*.mp4`.
2. Host on YouTube/Loom, link them in `SOLUTION_LP-0008.md`, commit, push.
3. Reopen the PR to logos-co/lambda-prize (resubmission explicitly invited in #88).

## Pre-recording verification status — ALL VERIFIED 2026-07-09

Every paste block below was executed end-to-end on the recording box at HEAD 4b113f8
before hand-off. Do not edit the scripts before recording.

- [x] Video 1 — `demo.sh` exit 0 from a fresh clone: setup builds, 6/0 modules, agent
      funded from genesis on the LIVE testnet (real proof, prover output visible on
      screen), tx getTransaction-confirmed, balance read through the module
- [x] Video 2 — prover block: real segments + cycle counts (4 consecutive passes)
- [x] Video 3 — `demo-f8-testnet.sh` exit 0: **F8_INTEGRATED_PASS** — Waku discovery
      (peer_count=1), A2A task, gate HELD (pending=1), autonomous spend — live testnet,
      output streaming to stdout
- [x] Video 4 — `demo-f8-linux-full.sh` exit 0: all steps incl. 10b on-chain event
      alerter (`delivered_to_owner_channel: true`), restart-recovery, skill isolation
