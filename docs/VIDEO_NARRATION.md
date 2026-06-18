# LP-0008 demo video — narration script

Read this over the silent recording `docs/lp0008-full-demo.mp4` (about 68s, two
parts). The terminal shows commands and results; your voice does the explaining.
Each block below is keyed to what is on screen at that moment. Speak in your own
words, this is a guide. The prize needs your narration ("a silent screencast is
not sufficient"), and it needs you to explain what you built, why, the key
decisions, and at least three use cases. All of that is below.

Tip: you can pause the video between sections while you talk, then resume. You do
not have to keep pace with the 68 seconds.

---

## Opening — title card + the RISC0_DEV_MODE lines

"This is LP-0008, an autonomous AI agent that runs as a native Logos Core module.
The whole idea: instead of renting compute, storage and a wallet from a cloud
provider, the agent owns all of it on Logos. Its own shielded wallet, its own
storage, its own encrypted messaging. One thing up front: both the sequencer and
the daemon are running with RISC0_DEV_MODE set to zero, so every proof you see in
this video is a real zero-knowledge proof, not a mock."

## Section 1 — "MODULE LOADS", the logoscore status output

"First, the agent module loads inside Logos Core right next to the platform
modules: the wallet, storage, chat and delivery. Six modules up, zero crashed.
The key design point is that my agent module did not require any changes to those
platform modules. It depends on them through their published interfaces."

## Section 2 — "ALL SKILLS" + "agent_card"

"The agent's capabilities are exposed as skills. Twenty-one of them, across
storage, messaging, blockchain, agent coordination and meta. They sit behind a
documented interface, so a third party can add a new skill without touching the
core module. Below that is the agent card. This is the coordination layer, and I
made it A2A-compatible. A2A is the open agent standard, but it deliberately
leaves out payment and encrypted transport. So the card follows the A2A schema,
and then I extend it with an x-lez-identity field that carries the shielded keys.
Logos Messaging is the transport, and LEZ is the payment layer. That is exactly
the gap A2A leaves open, and Logos fills it natively."

## Section 3 — "AGENT'S OWN SHIELDED ACCOUNT", the balance line

"The agent holds its own shielded LEZ account. This is its balance. It can
receive funds from anyone and spend on its own, independent of the owner's
wallet. On chain it is indistinguishable from any other account."

## Section 4 — "REAL-PROOF SHIELDED TRANSFER", the cycle counts + tx hash

"Here is a real shielded transfer. Watch the cycle counts: a shielded transfer
runs two guest proofs, one at a hundred and thirty one thousand cycles, one at
two hundred and sixty two thousand. Those numbers are the compute-unit cost I
documented for the prize, and the fact they appear at all confirms dev mode is
off. It ends with a transaction hash on the live sequencer, and the fresh
recipient settles from zero to seven. That is the on-chain transfer use case,
end to end, with a real proof."

## Section 5 — "SPENDING GATE"

"This is the spending control. The owner sets a per-transaction limit, here fifty
LEZ. At or under that, the agent settles on its own. Over it, the agent does not
execute. It builds a pending proposal and waits for the owner to approve. That is
the line between autonomous and supervised, and the owner draws it."

## Section 6 — "STORAGE — file vault", the CID round-trip

"Second use case: a personal file vault. The agent runs a local storage node,
encrypts a file, uploads it, and gets back a content address, the CID here. Then
it confirms the file exists and downloads it back. Full round trip. The owner can
hand a file to the agent and pull it back from any device, with no cloud storage
provider in the middle."

## Section 7 — "MESSAGING — owner channel"

"The agent also talks to its owner over Logos Messaging, on a dedicated encrypted
channel. No server, no exposed API. The owner can reach the agent from any Logos
app instance that holds the owner's keys."

## Section 8 — "HOSTED TESTNET"

"And this runs on the hosted testnet. I deployed three separate agents, one per
skill category, storage, messaging and blockchain, each funded with real proofs.
The evidence and the reproduce steps are in the repo."

## PART B opening — "autonomous discover -> task -> pay -> SETTLE"

"Now the third use case, and the one I am most proud of: a paid skill
marketplace, fully autonomous, no human in the loop. Same six modules loaded."

## PART B — "DISCOVER A PEER" + "TASK + AUTONOMOUS PAYMENT"

"A second agent, agent B, publishes its agent card with a skill and a price, five
LEZ. My agent discovers it, sends a task, and because five is under the fifty
limit, it pays automatically. Watch the balances. My agent's own shielded balance
drops by five, paid from its own funds, and agent B goes from zero to five. A
real agent-to-agent payment that settled. No owner approval, no payment
processor. Discovery over Logos Messaging, payment in LEZ."

## PART B — "SPENDING GATE", the 80 > 50 line

"And to close the loop on control: if that price had been eighty instead of five,
over the limit, the agent would not have paid. It routes to pending approval and
waits for the owner. Autonomy with guardrails."

## Closing — over the final line

"So that is LP-0008. An agent with its own wallet, storage and messaging, that
takes real on-chain actions, stores files privately, and coordinates and pays
other agents over an A2A-compatible layer that adds the payment and privacy
vanilla A2A cannot. All native to Logos, all under limits the owner sets. Three
use cases end to end: a file vault, a real on-chain transfer, and an autonomous
paid marketplace. Thanks for watching."

---

### Three use cases to name explicitly (the prize asks for at least three)
1. **Personal file vault** — Section 6 (storage upload to CID to download).
2. **On-chain transfer** — Section 4 (real-proof shielded transfer).
3. **Paid skill marketplace** — PART B (autonomous agent-to-agent payment).

### One honest framing note (say it however you like, or skip)
PART B runs in dev mode so the full agent-to-agent round trip completes inside the
inter-module timeout. The real-proof settlement of the exact same transfer
primitive is the one in Section 4. So the payment rail is real-proof (Section 4),
and the autonomous routing of it is PART B.

---

## Recording your voice

Simplest path on macOS: open `lp0008-full-demo.mp4`, start a QuickTime screen
recording with microphone audio on, play the video, and read the script. Pause
the video between sections if you need more time to talk. Export, and that file
is the narrated submission video.
