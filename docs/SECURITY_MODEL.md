# Security Model

This document describes exactly what the LP-0008 agent module can and cannot do without owner
approval, how keys are held, what on-chain observers and malicious peers can learn or influence,
and what guarantees hold when the owner is unreachable.

---

## What the agent can do autonomously

The following actions require no owner interaction:

- Read its own shielded token balance (`wallet.balance`)
- Read transaction history (`wallet.history`)
- Query LEZ program state (`program.query`)
- Upload, download, list, and share files via Logos Storage (`storage.*`)
- Send and receive Logos Messaging messages to any address (`messaging.send`)
- Join or create Logos Messaging group topics (`messaging.join`, `messaging.create_group`)
- Publish its A2A Agent Card to a discovery topic (`agent.card`)
- Discover other agents and read their Agent Cards (`agent.discover`)
- Receive A2A task requests from peer agents
- Execute token transfers and program calls **below the configured spending thresholds**
- Execute A2A task payments **below the configured spending thresholds**
- Report skill results and task status updates to requesters

Autonomous execution is gated on the spending threshold check (see below). Everything else —
reading state, messaging, storage — is unconditionally autonomous.

---

## What requires owner approval

Any action that moves tokens or invokes a program instruction is subject to the spending gate:

```
amount <= per_tx_limit  AND  (period_spent + amount) <= per_period_limit
    → execute autonomously
else
    → send approval request to owner channel, enter pending-approval state, WAIT
```

`per_tx_limit`, `per_period_limit`, and `period_seconds` are set via `meta.configure` at deploy
time and are persisted in the module's config store. A rolling `period_spent` counter is
maintained in memory and persisted with task state so it survives restarts.

When the threshold is exceeded, the agent sends a structured approval request over the E2E owner
channel:

```json
{
  "action":    "wallet.send | program.call | program.deploy",
  "recipient": "<address>",
  "amount":    "<decimal>",
  "reason":    "<task context>",
  "task_id":   "<a2a-task-uuid>"
}
```

The agent then pauses that task in `pending-approval` state. It does **not** time out silently:
see the failure-safe guarantee below. Execution resumes only on an explicit `approve_pending`
command from the owner; a `reject_pending` or timeout marks the task `failed`.

Skill categories subject to the gate:

- `wallet.send` — shielded token transfer
- `program.call` — invoke a LEZ program instruction
- `program.deploy` — deploy a compiled RISC-V program (incurs a deployment fee)
- A2A task payment — the LEZ price declared in a peer's Agent Card, paid on task acceptance

---

## Key custody

**NullifierSecretKey (NSK):** generated from a BIP39 mnemonic on first deploy via
`lez_wallet_module.ensure_account(passphrase)`. The NSK is encrypted at rest under the
owner-supplied passphrase and stored only on the remote node in the module's data directory. It
never transits to the owner's machine, to Logos Messaging, or to any external service.

**NullifierPublicKey (NPK):** derived from the NSK; this is the agent's public shielded
identity. It is published in the A2A Agent Card and is safe to share. Knowing the NPK lets a
sender address a shielded payment to the agent; it does not reveal the agent's balance or history.

**Owner's keys:** the owner holds their own chat-module identity keys on their laptop. These are
entirely separate from the agent's NSK/NPK. A compromise of the owner's device does not expose
the agent's wallet keys; a compromise of the remote node does not expose the owner's keys.

**Inference adapter:** the pluggable LLM/inference layer (`InferenceAdapter`) receives only
natural-language prompts and skill dispatch decisions. It never receives the passphrase, NSK,
or any signing material. It cannot initiate on-chain actions directly; it can only invoke named
skills with JSON params, which then go through the spending gate.

---

## Owner channel trust model

At deploy time the CLI passes the owner's `introBundle` to the agent. The agent calls
`newPrivateConversation(ownerIntroBundle, firstMessage)` and pins the resulting `convoId` as the
owner channel. This conversation is:

- End-to-end encrypted via the `logos-chat-module` (liblogoschat)
- Bound to the owner's chat-module identity (key-derived, device-independent)
- Stored as the sole trusted command channel in the agent's persisted config

Only messages arriving on this pinned `convoId` are treated as owner commands. Messages from any
other address — including peer agents, external users, or a different chat conversation — are
never elevated to owner authority. There is no privilege-escalation path through the A2A task
channel or the discovery topic.

The owner can reach the agent from any Logos app (Basecamp) instance that holds the owner's keys,
because the chat identity is key-derived and not device-bound.

---

## What an on-chain observer can learn

The agent uses a **shielded LEZ account** (NPK/NSK model, Groth16 ZK proofs). From the
perspective of the public chain state:

- **Cannot observe:** the agent's balance, who sent funds to the agent, who the agent sent funds
  to, the amount transferred, or any link between the agent's transactions.
- **Can observe:** that a shielded transaction was posted (a ZK proof exists on chain); the
  transaction hash; the block timestamp; the program ID if a public program call is made.

The NPK itself is published in the Agent Card (necessary for other agents to address payments),
but this does not reveal the balance or transaction graph. An observer who knows the NPK cannot
determine how many tokens the agent holds or has spent.

---

## What a malicious peer agent can do

A peer agent that has obtained the agent's NPK (from the Agent Card) and Logos Messaging address
can:

- Send A2A task requests (same as any legitimate peer)
- Send Logos Messaging messages to the agent's address
- Attempt to trigger skills via the A2A task channel

A malicious peer **cannot**:

- Force any spend above the configured threshold — all payment paths go through the spending gate
- Impersonate the owner — the owner channel is a separate, E2E-encrypted conversation bootstrapped
  at deploy with a specific `introBundle`; messages on the A2A task channel carry no owner
  authority regardless of content
- Access the agent's NSK or passphrase
- Read the agent's shielded balance or transaction history

The worst-case outcome from a malicious peer is a flood of A2A task requests. The agent can
reject tasks from unknown senders or rate-limit by address; this is a configuration option rather
than a protocol-level block, since A2A discovery is intentionally open.

---

## What the sequencer can do

The LEZ sequencer processes submitted transactions and produces blocks. It:

- Sees the ZK proof submitted with each shielded transaction (but the proof does not reveal the
  sender, recipient, or amount — it only proves validity)
- Can in principle withhold a specific transaction from a block (censorship); however, because the
  agent's on-chain identity is just a shielded key pair with no persistent pseudonym, selective
  censorship requires identifying the agent's transactions, which the proof structure makes
  difficult
- Cannot learn the agent's balance or spend history from chain state

The sequencer has no special access to the agent's module, keys, or configuration.

---

## Failure-safe guarantee

If the owner is unreachable when an above-threshold transaction is pending:

1. The agent retries the approval-request notification on the owner channel (configurable retry
   count and interval, defaults: 3 retries, 60-second interval).
2. If all retries are exhausted without a response, the proposed transaction is **not executed**.
3. The task is marked `failed` with reason `approval-timeout`, and the failure is recorded in the
   task state store (persisted to disk).
4. On next owner contact (the owner messages the channel), the agent reports the failed task and
   the reason.

There is no path by which a timed-out approval request results in silent execution.

---

## Known limitation: software-only enforcement

The spending threshold is enforced as a software policy inside the `agent_module`, not as an
on-chain constraint. This means:

- A full compromise of the remote node (root access + passphrase) would allow an attacker to
  invoke the wallet module directly, bypassing the agent's gate, and spend the agent's entire
  balance.
- The agent's balance is therefore the maximum at-risk amount in a node-compromise scenario.
  Operators should configure the agent's balance to match their risk tolerance rather than
  pre-loading large sums.

Mitigation (upgrade path): route above-threshold spends through an on-chain M-of-N multisig
contract (see LP-0002 — Private M-of-N Multisig). In this model the agent holds keys for one signer
slot; the owner holds a second. Above-threshold transactions require a co-signature from the
owner's key, enforced by the contract rather than by the agent's software. The baseline
submission ships the software gate; the multisig upgrade is noted as a natural follow-on.
