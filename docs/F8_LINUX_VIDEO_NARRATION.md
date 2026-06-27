# LP-0008 narration scripts (read-aloud ready)

Four videos. Read each block while that part of the screen plays. The videos are paced with
pauses, so you can slow down or pause any time. Speak naturally, first person. Numbers in
brackets line up with the on-screen step.

The prize wants you to explain what you built and why, the architecture, the key decisions, and
the full flow. The opening of the main video covers the what and why, so lead with it.

---

# Video 1 — Main flow (`lp0008-f8-linux-demo.mp4`, ~7 min)

**Intro (title card).**
"This is LP-0008, an autonomous AI agent that runs as a native module inside Logos Core. It
holds its own shielded LEZ wallet, it stores files on Logos Storage, it finds other agents over
Logos Messaging, and it pays them, all within limits its owner sets. The design is two modules:
the agent module is the runtime, with skill dispatch, the spending gate, the owner channel, and
agent-to-agent coordination. It sits on top of the platform modules, messaging, storage, and
chat, without changing any of them. I picked the A2A protocol for coordination because it's the
emerging standard, but A2A leaves two things open: payment and encrypted transport. Logos fills
both. LEZ gives me per-task payment, and Logos Messaging gives me encrypted transport with no
server in the middle. Everything you'll see runs on one Linux machine, and every proof is real,
dev mode off."

**[1] The chain.**
"First I start the LEZ blockchain locally, a standalone sequencer that does real proving.
Genesis holds ten thousand test tokens, and you can see the block height climbing, so the chain
is live."

**[2] Deploy.**
"This is the whole deploy, one command. agent up starts Logos Core headless, loads the agent
next to the platform modules, and sets the owner and the spending limit. Five modules come up,
zero crashes, and I didn't touch any platform module."

**[3] Identity and card.**
"The agent owns a shielded LEZ account. Its identity is an npk, a shielded public key. And its
A2A Agent Card carries that same npk, so when another agent discovers the card, it knows exactly
which account to pay. One identity across the wallet and the card."

**[4] Skills.**
"Twenty-one skills, across storage, messaging, wallet, programs, agent-to-agent, and meta, all
behind a documented interface so a third party can add more without touching the core."

**[5] Funding, real proof.**
"The owner funds the agent, a hundred tokens, public to private. Watch the zero-knowledge prover
actually run. Those execution-time lines only show up with real proving, dev mode off, and the
cycle count is the compute cost. A real transaction settles, the balance goes to a hundred, and
the chain moves forward."

**[6] Storage file vault.**
"Now the file vault. The agent runs an embedded Logos Storage node. The owner hands it a file,
the agent stores it and returns a content address. Then anyone with that address gets the exact
bytes back. This is a real upload and a real download, not a stub. That was one of the harder
pieces: the upload returns a session id and the content address arrives later on an event, so
the agent subscribes to that event and resolves the address."

**[7] A second agent.**
"A second agent comes online with its own shielded account, so now we have two."

**[8] Discovery.**
"Here's the key moment. Each agent publishes its Agent Card to a shared Logos Messaging topic
and reads the others. Agent A finds agent B, with its skills. This cross-module event delivery
is exactly what was hard to get working, and it runs here on Linux."

**[9] Spending gate.**
"The owner set a fifty-token limit. Agent A opens a task priced at eighty, over the limit. So it
does not pay. It tried to reach the owner three times, it reports that it couldn't, and it holds
the spend. Agent A still has all hundred tokens. Above the limit never executes on its own, and
if it can't reach the owner, it's held and reported, never dropped."

**[10] Autonomous payment.**
"Five tokens is under the limit, so the agent pays the peer on its own, no human, another real
proof. Agent A goes to ninety-five, agent B to five."

**[11] Recovery.**
"I restart the agent. The held task and the config come straight back. No task state lost."

**[12] Skill isolation.**
"And I call a skill with bad input. It returns an error, and the module keeps running. A failing
skill stays isolated."

**Close.**
"So that's the agent end to end: it loads with the platform modules unchanged, owns and funds
its own account, deploys in one command, stores and retrieves files, runs the full
agent-to-agent flow over real messaging and a real payment, enforces the spending gate, survives
a restart, and isolates failures. Every proof real, dev mode off."

---

# Video 2 — Storage use case (`lp0008-uc-storage.mp4`, ~90s)

**Intro.**
"This is the storage use case, a personal file vault. The owner sends a file to the agent, the
agent stores it on Logos Storage and returns a content address, and it can be retrieved from
anywhere by that address."

**[1]** "The agent runs an embedded Logos Storage node, and it comes up with its own peer id."

**[2]** "The owner hands it a private file. The agent stores it and returns a content address.
You can see it in the agent's file list."

**[3]** "And anyone with that address gets the exact bytes back. Original and retrieved match,
byte for byte. That's a real Codex upload and download through the agent's own skills."

---

# Video 3 — Messaging use case (`lp0008-uc-messaging.mp4`, ~100s)

**Intro.**
"This is the messaging use case, a paid skill marketplace. Agents advertise skills with a price
on a shared topic. A client agent discovers a provider, requests the task, and pays for it on
its own, no human in the loop."

**[1]** "I bring up a client agent and a provider agent, both on Logos Messaging, and the client
is funded."

**[2]** "The client discovers the provider's Agent Card on the shared topic, with its skills.
That's the A2A discovery step."

**[3]** "The client opens an A2A task for a skill priced at five tokens, then settles it on
chain with a real proof. The provider gets paid, zero to five, fully autonomous. Discover,
request, pay, with payment and privacy that vanilla A2A can't offer."

---

# Video 4 — Blockchain use case (`lp0008-uc-blockchain.mp4`, ~70s)

**Intro.**
"This is the blockchain use case, autonomous on-chain payments. The agent holds a shielded LEZ
account and acts on it on its owner's behalf, with no custodian."

**[1]** "First it's funded on chain, public to private, and the zero-knowledge prover runs. A
real proof settles, and the agent holds a hundred tokens in its own encrypted note."

**[2]** "Then the agent pays out on its own, thirty tokens to a recipient, private to private,
another real proof. The agent goes to seventy, the recipient to thirty. A real on-chain
transfer, settled with a real proof, no custodian."
