# LP-0008 demo video, narration script

The submission is one main video plus three short use-case cuts. Record your voice over each
silent screencast; the prize requires narration ("a silent screencast is not sufficient").
Speak in your own words. Blocks are keyed 1:1 to the numbered headers on screen.

- Main flow: `docs/lp0008-agent-demo.mp4` (~62s) — the agent through its own skills.
- Use-case cuts: `docs/lp0008-uc-storage.mp4`, `docs/lp0008-uc-messaging.mp4`, `docs/lp0008-uc-blockchain.mp4`.

Honest note to keep in mind while narrating: the standalone sequencer runs in dev mode so the
block loop stays fast on camera, but the funding transfer in step 5 runs with `RISC0_DEV_MODE=0`
and you see the real zk prover execute. That split is intentional and documented.

---

# Video 1 — Main flow (`lp0008-agent-demo.mp4`, ~62s)

**Title.**
"This is LP-0008, an autonomous AI agent that runs as a Logos Core module. It owns a shielded
LEZ wallet and pays other agents through its own skills. Every settlement is a real RISC0 proof."

**1 · the local LEZ chain.**
"First a standalone LEZ sequencer, doing real proving. It answers getLastBlockId, so the chain
is live and advancing."

**2 · deploy the agent in one command (F1, F3).**
"One command, agent up, loads the agent right next to the wallet and the platform modules. Six
modules come up together and report loaded and responding. Single-command deploy."

**3 · the agent's identity (F7).**
"The agent has its own A2A card, and the card carries its shielded identity, both the nullifier
public key and the viewing public key. That's a real on-chain account the agent controls, not a
placeholder."

**4 · the agent's skills (F6).**
"It ships with twenty-one skills out of the box, across storage, messaging, wallet, program, and
agent-to-agent. Every one of these reaches the real wallet module, no stubs."

**5 · fund the agent, a real proof (F2).**
"Now the owner funds the agent a hundred tokens. Watch RISC0_DEV_MODE, it's zero, so this is the
real zero-knowledge prover running, real segments, real execution time. The agent reads its own
balance back through its skill: a hundred."

**6 · autonomous A2A payment (F8).**
"Agent B advertises a compute skill at five tokens. Agent A discovers B's card, opens a task, and
pays it from its own shielded funds, another real proof. Agent A goes to ninety-five, agent B to
five. No human in the loop, the agent decided and paid on its own."

**Close.**
"All of that ran through the agent's own skills: load, fund, list skills, expose its card, and pay
a peer autonomously. The agent genuinely owns and operates a funded shielded account on Logos."

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
