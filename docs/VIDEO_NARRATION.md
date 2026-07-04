# LP-0008 demo video, narration script

The submission is one main video plus three short use-case cuts. Record your voice over each
screencast; the prize requires narration ("a silent screencast is not sufficient"). Speak in your
own words. Blocks are keyed 1:1 to the numbered headers on screen.

**Record the primary video FRESH against the current build** — do NOT reuse the older cuts whose
on-camera hashes predate LEZ v0.2.0 (that credibility gap is exactly what sinks the competing
submission). The primary video is the evaluator's own test, recorded live:

Primary recording — the clean-clone run (shot-list):
```
git clone <repo> /tmp/lp0008-demo && cd /tmp/lp0008-demo
asciinema rec demo.cast -c "RISC0_DEV_MODE=0 ./demo.sh < /dev/null" --overwrite
agg --idle-time-limit 4 --cols 100 --rows 30 --font-size 20 --theme monokai demo.cast demo.gif
ffmpeg -i demo.gif -pix_fmt yuv420p -vf "scale=1920:1080:force_original_aspect_ratio=decrease,\
pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=#0d1117,setsar=1" docs/lp0008-v020-demo.mp4
```
Run it on a machine with a stable shell + nix + risc0 + logoscore. `RISC0_DEV_MODE=0` must stay
visible; the real RISC0 prover output (segments, cycle counts) appears during the funding step.

- Primary flow: `docs/lp0008-v020-demo.mp4` — a fresh clone → `./demo.sh` → six modules load, the
  agent funds its own shielded account from genesis on the LIVE v0.2.0 testnet with a real proof,
  tx confirmed on-chain, all `RISC0_DEV_MODE=0`.
- Use-case cuts (storage / messaging / blockchain): `docs/lp0008-uc-*.mp4`.
- CU: point at `docs/CU_COSTS.md` — real measured per-op cycle counts (transfer 131,072 total /
  80,734 user; public program calls + deploys = 0 client proving cycles). Not "TBD".

---

# Video 1 — Primary: the clean-clone run (`lp0008-v020-demo.mp4`)

This is the evaluator's own test on camera: clone the repo, run the one demo script, nothing
edited. Narrate the on-screen steps.

**Title.**
"This is LP-0008. I'll do exactly what an evaluator does: clone the repository and run the demo
script from a clean machine, unmodified. Everything you'll see is a real RISC0 proof, dev mode off."

**1 · setup from a clean clone.**
"The script builds the LEZ stack at v0.2.0, the exact version the hosted testnet runs, plus the
agent module and the platform modules, and assembles the runtime bundle. This is a fresh clone —
no pre-built artifacts."

**2 · six modules load together (F1).**
"It boots Logos Core and loads all six modules in one daemon — the agent beside the wallet,
storage, chat, and delivery, unmodified. Six loaded, zero crashed."

**3 · the agent's own shielded identity (F2, F7).**
"The agent creates its own shielded LEZ account. Its A2A card carries the identity — the nullifier
public key and a post-quantum ML-KEM viewing key. A real account the agent controls."

**4 · funded on the LIVE testnet, real proof (F2, P1).**
"Now it funds the agent a hundred tokens from genesis, on the live testnet, dev mode zero. The real
zk prover runs — you can see the segments and cycle counts, that's the compute-unit cost. The
funding transaction confirms on-chain by getTransaction."

**5 · the agent reads its balance through its own skill.**
"And the agent reads its balance back through its own module skill: a hundred. The whole run exits
zero — clone, build, load, fund, confirm, all from a clean environment with real proofs."

**Close.**
"That's the reproducible demo the prize asks for, passing unmodified. Compute costs are measured,
not estimated — real cycle counts per operation, in the docs."

---

# Video 2 — The agent through its own skills (`lp0008-agent-demo.mp4`, ~62s)

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

# Video 3 — Storage use case (`lp0008-uc-storage.mp4`, ~90s)

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

# Video 4 — Messaging use case (`lp0008-uc-messaging.mp4`, ~100s)

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

# Video 5 — Blockchain use case (`lp0008-uc-blockchain.mp4`, ~70s)

**Intro.**
"This is the blockchain use case, autonomous on-chain payments. The agent holds a shielded LEZ
account and acts on it on its owner's behalf, with no custodian."

**[1]** "First it's funded on chain, public to private, and the zero-knowledge prover runs. A
real proof settles, and the agent holds a hundred tokens in its own encrypted note."

**[2]** "Then the agent pays out on its own, thirty tokens to a recipient, private to private,
another real proof. The agent goes to seventy, the recipient to thirty. A real on-chain
transfer, settled with a real proof, no custodian."
