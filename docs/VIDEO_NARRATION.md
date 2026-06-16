# LP-0008 demo video, narration script

Read this over the silent terminal recording (`lp0008-demo.mp4`). The terminal
shows only commands and results. All the explaining is your voice. Each section
below is keyed to what is on screen at that moment, so you narrate what the
viewer is actually seeing. Speak in your own words. This is a guide.

The prize requires your narration ("a silent screencast is not sufficient"), so
the voice track is what makes this a valid submission.

---

## Opening, while the two header lines are on screen

"This is LP-0008, an autonomous agent module for the Logos Execution Zone. The
idea is simple: give an AI agent its own wallet so it can hold and move value on
its own, but keep that activity private. Here I have two agents, each with its
own shielded identity, and one is going to pay the other on the live testnet
with a real zero-knowledge proof. Dev mode is off, so every proof here is real."

## "agent A's shielded address", over the first `lez address` output

"This is agent A's address. A shielded identity is three keys, not one. The
account id, a nullifier key, and a viewing key. The nullifier key is what lets
the agent spend without revealing which note it spent. The viewing key is what
lets a sender encrypt a payment that only this agent can read. None of this
exposes who the agent is."

## "agent B's shielded address", over the second `lez address` output

"Agent B is a second, completely separate agent, with its own keys. A and B
don't share a wallet. As far as the chain is concerned they are unrelated."

## "balances before the transfer", over the two balance lines

"Before we start, agent A holds two hundred and agent B holds nothing. These are
shielded balances. They live in the agents' own encrypted notes, not in any
public account the chain can read."

## "agent A privately transfers 100 to agent B", over the `send-to` command

"Now agent A pays agent B one hundred. A only needs B's public keys, the
nullifier and viewing keys you saw a moment ago. Under the hood the agent builds
a real zero-knowledge proof that the transfer is valid, that A had the funds and
authorized the spend, without putting any of that on chain. That proving step
takes a couple of minutes. When it finishes, the line says included, with the
transaction hash. That hash is on the live testnet, you can look it up in the
explorer."

## "agent B syncs and sees the incoming shielded note", over the sync + balances

"Agent B now scans the chain for notes addressed to it and finds the payment.
The balances have moved: A is down to one hundred, B is up to one hundred. B
discovered this on its own, from the encrypted note, using its viewing key."

## Closing, over the final two `#` lines

"So one autonomous agent paid another, one hundred moved, and both agents
confirmed it independently. But on chain there was just one private transaction.
Nothing links the sender to the receiver, nothing shows the amount, and neither
agent's identity is exposed. That is the whole point: agents that can transact
on their own, with privacy by default. The code, the transaction hash, and a
one-command reproduction are in the repository. Thanks for watching."

---

## Recording your voice

Simplest path on macOS: open `lp0008-demo.mp4`, start a QuickTime screen
recording that captures the playing video plus your mic, and talk through the
sections above. The proving step holds on screen for a while, which gives you
room to explain what the proof is doing. Send me the result and I will attach it
to the submission.

Note on length: the video is about forty seconds after idle compression, so keep
the pace relaxed. If you want more breathing room on any section, pause the video
while you talk and resume when you are ready.
