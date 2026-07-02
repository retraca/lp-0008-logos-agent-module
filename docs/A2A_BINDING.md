# A2A Transport Binding over Logos Messaging

This document describes how the LP-0008 agent module implements the Agent2Agent (A2A) protocol,
using Logos Messaging as the transport layer and LEZ token transfers as the payment layer.

---

## Overview

The [Agent2Agent (A2A) protocol](https://a2a-protocol.org/latest/specification/) is an open
standard governed by the Linux Foundation, contributed originally by Google, and backed by over
150 organisations. It defines how agents discover each other (Agent Cards), negotiate tasks
(task lifecycle), and exchange messages (text, files, structured data).

A2A deliberately omits two things:

- **Payment** — no mechanism for agents to charge or pay each other per task.
- **Encrypted transport** — A2A's reference transport is plain HTTP/SSE; privacy is left to the
  implementer.

This submission fills both gaps natively:

- **LEZ token transfers** (shielded, zero-knowledge) provide per-task micropayment between
  agents, with privacy by default.
- **Logos Messaging** (end-to-end encrypted, serverless, Waku-backed) replaces HTTP/SSE as the
  transport. No central server handles agent messages.

The result is an A2A-compatible agent network that any standard A2A client can discover and
interact with, extended with payment and privacy primitives no vanilla A2A implementation
provides.

---

## Agent Card Schema

Each agent publishes an Agent Card: a signed JSON document declaring its identity, skills, and
pricing. Standard A2A fields are used without modification; LEZ-specific fields are additive
extensions (prefixed `x-lez-`) that standard A2A clients ignore.

### Standard A2A fields

```json
{
  "id": "logos-agent:<npk-hex>",
  "name": "LP-0008 Agent",
  "provider": {
    "organization": "retraca",
    "url": "https://github.com/retraca/lp-0008-ai-module"
  },
  "capabilities": {
    "streaming": true,
    "pushNotifications": false,
    "stateTransitionHistory": true
  },
  "securitySchemes": {
    "lez": {
      "type": "apiKey",
      "description": "Caller must transfer x-lez-price LEZ to the agent NPK before task acceptance."
    }
  },
  "agentInterfaces": [
    {
      "type": "a2a",
      "transport": "logos-messaging",
      "address": "<chat-module-intro-bundle-hex>"
    }
  ],
  "defaultInputModes": ["text/plain", "application/json"],
  "defaultOutputModes": ["application/json"],
  "skills": [
    {
      "id": "storage.upload",
      "name": "Storage Upload",
      "description": "Encrypts and uploads a file to Logos Storage; returns content address.",
      "inputModes": ["application/octet-stream"],
      "outputModes": ["application/json"]
    }
    // ... one entry per skill from meta.skills()
  ],
  "signature": "<base64-sig-over-card-bytes-with-lez-key>"
}
```

### LEZ extensions

| Field | Type | Meaning |
|---|---|---|
| `x-lez-identity.npk` | hex string | Agent's NullifierPublicKey — the shielded identity used to receive payments. |
| `x-lez-identity.account_id` | hex string | Derived AccountId for the agent's shielded account. |
| `x-lez-price` | string (decimal LEZ) | Default per-task price; `"0"` means free. |
| `skills[n].x-lez-price` | string (decimal LEZ) | Per-skill price override; takes precedence over the card-level default. |

The card is signed with the agent's LEZ key (NSK-derived signing key). Any party holding the
NPK can verify the signature.

### Discovery

Agent Cards are published to a named Logos delivery topic (pub/sub, Waku-backed). The topic
name is conventionally `logos-agent-discovery-v1` but is configurable via `meta.configure`.
Callers subscribe to this topic via `agent.discover(topic)` to collect available agents.

---

## Transport Binding: A2A over Logos Messaging

This is a custom Layer-3 transport binding, using the extensibility model A2A defines for
non-HTTP transports.

Logos Messaging provides two primitives relevant here:

- **chat-module** — end-to-end encrypted 1:1 conversations between two identities.
- **delivery-module** — end-to-end encrypted pub/sub topics (group broadcast).

Each abstract A2A operation maps to a Logos Messaging primitive as follows:

| A2A operation | Logos Messaging mapping |
|---|---|
| `SendMessage` (task request) | chat-module 1:1 E2E message to the peer agent's intro-bundle address. Body is a JSON-RPC-shaped envelope `{type:"task_request", task_id, skill, params, lez_price}`. |
| `GetTask` (status poll) | chat-module request/reply on the same 1:1 channel. Body: `{type:"task_get", task_id}`. Reply: `{task_id, state, result_or_error}`. |
| `CancelTask` | chat-module message `{type:"cancel", task_id}`. Provider acknowledges with `{type:"cancelled", task_id}` and initiates refund if payment was already made. |
| `SubscribeToTask` (streaming) | delivery-module topic named `agent-task-<task_id>`. Provider posts status updates as messages to this topic as the skill progresses. Requester subscribes at task request time. |
| Agent discovery | delivery-module named topic (default `logos-agent-discovery-v1`). Agents post their Agent Card as a message on joining and periodically refresh. |

All messages are JSON strings. The `task_id` is a UUID generated by the requester and included
in the initial `SendMessage`.

### Message envelope

```json
{
  "type": "task_request | task_get | cancel | task_status | task_result | cancelled",
  "task_id": "<uuid>",
  "skill": "storage.upload",
  "params": { ... },
  "lez_price": "5.0",
  "state": "working | input-required | completed | failed",
  "result": { ... },
  "error": "..."
}
```

---

## Task Lifecycle

The A2A task lifecycle states map directly to internal agent states:

```
[requester sends task_request]
         |
         v
      working          -- task accepted; skill execution started; payment transferred
         |
    +----+----+
    |         |
    v         v
input-required  (no branch: spending gate triggered)
    |
    v
  [owner approval or rejection via owner channel]
    |
    +-- approved --> working (resumes)
    |
    +-- rejected/timeout --> failed
         |
         v
   completed / failed
```

**`working`**: the provider agent has accepted the task and begun skill execution. The payment
(`x-lez-price` LEZ) is transferred from requester to provider NPK at this transition.

**`input-required`**: the skill requires an above-threshold spend (e.g., `program.call` with a
high-value instruction, or `wallet.send` above `per_tx_limit`). The agent pauses, sends an
approval request to the owner over the owner channel, and holds the task in this state. The
A2A requester is notified via the task-status topic. If the owner approves, the task returns to
`working`. If the owner rejects or the approval times out, the task transitions to `failed`.

**`completed`**: the skill returned a result. The result JSON is sent to the requester over the
1:1 channel.

**`failed`**: the skill raised an error, the owner rejected the spend, or the approval timed
out. The provider sends an error envelope. Refund logic is triggered (see Payment model below).

---

## Payment Model

A2A defines no payment mechanism. This binding adds one via LEZ shielded transfers.

### Payment flow

1. Requester calls `agent.task(peer_address, skill, params)`.
2. Requester reads `x-lez-price` (or skill-level override) from the peer's Agent Card.
3. On sending the `task_request` message, the requester transfers `x-lez-price` LEZ to the
   provider's NPK via `wallet.send`. This transfer is subject to the **requester's own spending
   threshold gate** — if it exceeds the per-tx limit, the requester's owner must approve it
   before the task request is sent.
4. Provider receives the task and verifies payment (checks its own balance delta via
   `wallet.balance()` / incoming note scan). On verification, transitions to `working`.
5. On `completed`, payment is retained by the provider.
6. On `cancelled` or `failed` after payment: the provider issues a best-effort refund via
   `wallet.send(requester_npk, amount)`. This is a new shielded transfer, not a reversal.
   **Limitation:** the refund is best-effort. There is no atomic escrow in this baseline.
   An upgrade path exists: deploy a LEZ escrow program that holds funds until the provider
   submits a proof of completion; the program releases to the provider on completion or back
   to the requester on cancel. This is noted as a future upgrade, not shipped in this submission.

### Zero-price tasks

If `x-lez-price` is `"0"`, no transfer is made. The task proceeds immediately to `working`.

---

## Known Limitations

**A2A identity binding gap.** The Agent Card publishes the NPK as `x-lez-identity.npk` and the
chat-module intro-bundle as the transport address (`agentInterfaces[0].address`). These are two
independent identities linked only by the Agent Card signature: the NPK is the shielded LEZ
identity; the chat intro-bundle is derived from a separate chat-module keypair.

The ideal design derives the chat intro-bundle deterministically from the NSK so a single root
secret produces both identities. This derivation is not implemented in the current submission
because the `liblogoschat` API does not expose a seed-based identity constructor in the version
researched. The Agent Card signature provides a weaker binding:
the agent proves it controls both keys by signing the card that contains both.

This limitation means a verifier cannot cryptographically prove the chat address and the LEZ
identity belong to the same agent without trusting the signature; they cannot derive one from
the other independently.
