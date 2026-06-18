# LP-0008 demo — narration script

Read this over `docs/lp0008-full-demo.mp4`. The screen shows the real commands and
output. Your voice carries the meaning. Each block below is keyed to the on-screen
header with the SAME number, so you stay in sync: when header "4 · A real on-chain
payment" appears, read block 4.

Speak in your own words. Short lines. You can pause between sections.

---

**Intro** (title card)
"This is LP-0008. An AI agent that lives on Logos and owns its own infrastructure:
a private wallet, file storage, and encrypted messaging. Everything you'll see is
real, with real zero-knowledge proofs. Dev mode is off."

**1 · Boot the stack**
"I'm starting the whole thing live. First the LEZ chain, you can see blocks
advancing. Then the agent daemon, and the modules loading: storage, wallet,
messaging, and my agent module on top. Six modules, zero crashes. My module didn't
need to change any of the others."

**2 · It owns a shielded wallet**
"The agent has its own shielded account. That balance is its money, not the
owner's. It can receive from anyone and spend on its own."

**3 · It speaks A2A, discoverable, with a price**
"Its capabilities are skills, twenty-one of them, behind an interface so anyone can
add more. The agent card is the A2A standard for how agents find each other. A2A
left out payment and private transport on purpose, so I add the agent's shielded
keys to the card and use Logos messaging and LEZ to fill that gap."

**4 · A real on-chain payment, watch the prover**
"Here's a real shielded transfer. A shielded transfer runs two zero-knowledge
proofs, and you're watching the prover run: the cycle counts only exist with real
proving. It ends with a transaction hash on the live chain, and the recipient goes
from zero to seven. Private payment, settled, real proof."

**5 · The owner sets the limit**
"The owner sets a per-transaction limit. Under it, the agent acts on its own. Over
it, the agent won't spend. It waits for the owner. That's the whole control model."

**6 · A private file vault, store and retrieve**
"Use case two, a file vault. The agent encrypts a file, stores it, and gets back a
content address. Then it checks the file is there and pulls it back. No cloud
provider in the loop."

**7 · Owner channel + live testnet**
"The agent reaches its owner over an encrypted channel, no server. And this all
runs on the hosted testnet, three agents, one per skill category, each funded with
real proofs."

**8 · A peer advertises a skill, with a price**
"Now the one I like most. A second agent publishes a card: it can run a job, for
five LEZ."

**9 · The agent hires it, and pays, by itself**
"My agent finds that peer, sends it the job, and because five is under the limit,
it just pays. Watch the daemon: the wallet fires, the proof runs. My agent's
balance drops by five, the peer's goes up by five. A real agent-to-agent payment,
settled, with no human and no payment processor."

**10 · Over the limit? It asks first**
"And the guardrail. If the price were eighty, over the limit, the agent would not
pay. It becomes a request the owner has to approve. Autonomy under the limit, the
owner above it."

**Close**
"That's LP-0008. Its own wallet, storage and messaging. Real on-chain actions.
And it hires and pays other agents, all under limits the owner sets. Thanks for
watching."

---

### The three use cases (the prize wants at least three) — name them as you go
1. On-chain payment (block 4)
2. File vault (block 6)
3. Paid agent marketplace (blocks 8–9)

### Recording
Open `lp0008-full-demo.mp4`, screen-record with mic on, read the blocks in order.
Pause the video between sections if you want more time on any one.
