# LP-0008 demo — narration script

> Status: recorded. Final narrated cut is `docs/lp0008-demo-narrated.mp4` (5:24, 1920×1080).

Read over `docs/lp0008-full-demo.mp4`. The screen shows real commands + output,
each header naming the success criterion it proves. Your voice carries the meaning.
Blocks are numbered to match the on-screen headers 1:1. Short lines. Pause between
sections if you want.

---

**Intro** (title card)
"This is LP-0008, an autonomous AI agent that runs as a native Logos Core module.
It owns its own wallet, storage and messaging. I'll walk through every success
criterion, step by step. Everything is real, with real zero-knowledge proofs.
Dev mode is off."

**1 · Loads into Logos Core (F1)**
"I start the LEZ chain, you see blocks advancing, then the agent daemon, and the
modules load: storage, wallet, messaging, and my agent on top. Six modules, zero
crashes. My module needed no changes to the others."

**2 · Single-command deploy (F3)**
"Deployment is one command. `agent up` spawns the daemon, loads the modules, and
sets the owner and limits. That's the boot you just saw, wrapped up, so an owner
can deploy on any headless node in one line."

**3 · Its own shielded account (F2)**
"The agent has its own shielded balance. Its money, not the owner's. It receives
from anyone and spends on its own."

**4 · All skills, extensible (F6, U1)**
"Twenty-one skills across storage, messaging, blockchain, agent coordination and
meta. They sit behind a documented interface, so third parties add skills without
forking the module."

**5 · A2A card (F7)**
"The agent card is the A2A standard. A2A leaves out payment and private transport,
so I extend the card with the agent's shielded keys and use Logos for both."

**6 · Owner channel (F4)**
"The owner reaches the agent on a dedicated encrypted channel. No server, no
exposed API, reachable from any app holding the owner's keys."

**7 · Use case 1, on-chain payment (CU / P1)**
"A real shielded transfer. Two zero-knowledge proofs, you're watching the prover
run, and the cycle counts only exist with real proving. It settles on-chain with
a transaction hash. The full compute-unit cost is documented."

**8 · Spending limit (F5, R2)**
"The owner sets a per-transaction limit. Under it, the agent acts on its own. Over
it, it holds the spend for approval. And if the owner can't be reached, it never
auto-executes, it retries and reports."

**9 · Use case 2, file vault (F9)**
"The agent encrypts a file, stores it, gets a content address, then confirms it's
there and pulls it back. A private vault with no cloud provider."

**10 · Recovers from a restart (R1)**
"Reliability. There are pending task records on disk. I kill the daemon, restart
it, and the records are still there. Task state survives a node restart."

**11 · Skill failures isolated (R3)**
"I call a skill with a bad input on purpose. It fails, but the module keeps
running. One skill failing never takes down the others."

**12 · Deployed on testnet (F10, S1)**
"On the hosted testnet I deployed three agents, one per skill category, each
funded with real proofs."

**13 · Everything else, in the repo (F11, U2, S2, S3, S4)**
"And the rest is in the repo: full docs, the Basecamp owner mini-app, end-to-end
tests in CI, a green build, and a README that walks the whole flow."

**14 · A peer advertises a skill (F7, F8)**
"Now use case three. A second agent publishes a card: it can run a job, for five
LEZ."

**15 · The agent discovers, prices, and opens the task; the payment settles with a real proof (F8 — partial)**
"My agent finds the peer, reads the price from its card, and because five is under
the limit, opens the task on its own. No human in that loop. The payment of the
resolved price then settles with a real zero-knowledge proof. Honest note: that
final settling transfer runs through the wallet's transfer primitive, not yet
through the agent module's own integrated wallet path, which still panics on a
freshly reset chain. So the autonomous discover-price-task loop is real, and the
payment is real, but the last integrated hop is the one piece still open."

**16 · Over the limit, it asks first (F5)**
"And the guardrail again: at eighty, over the limit, it would not pay. It holds
the request for the owner."

**Criteria checklist**
"Where it stands: it loads beside the platform modules, owns its account, deploys
in one command, controls spending, ships every skill, speaks A2A, runs three use
cases end to end on the live Logos testnets, deploys three agents on testnet,
recovers from restarts, isolates failures, documents its costs, and ships the
docs, app, CI and README. The one piece still open is the agent module's own
integrated wallet hop for autonomous payment, which I've been straight about.
That's LP-0008. Thanks for watching."

---

### Recording
Open `lp0008-full-demo.mp4`, screen-record with mic on, read the blocks in order.
Pause the video between sections if you want more time on any one.
