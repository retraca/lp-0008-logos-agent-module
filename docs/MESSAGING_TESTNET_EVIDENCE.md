# LP-0008 — Messaging Use Case over Logos Messaging (Waku, real relay)

**Stack:** Logos Messaging = Waku. nwaku `wakuorg/nwaku:v0.33.0`, RELAY protocol, cluster-id 0 shard `/waku/2/rs/0/0`.
**Captured:** 2026-06-20T12:55:45Z

Closes the F9 messaging category with a real **two-node Waku relay**: an owner-channel /
A2A message is published on node 1 and received on an independent node 2 over the gossip
relay — the exact transport the agent's owner channel and A2A binding ride on
(`docs/A2A_BINDING.md`). A single node cannot do this; the message crossed the wire.

## Two independent relay nodes

| Node | Peer ID | Role |
|------|---------|------|
| W1 | `16Uiu2HAmKtazmYqZo4kZth98TyGbx47L8Jt8iStddghG6mTMQAr6` | publisher |
| W2 | `16Uiu2HAmKBg4dMHJFG7ydQfoA5UaL6B8a86KqLRqWptERkptBS5N` | subscriber (statically peered to W1, `outRelayConns=1`) |

## Subscribe → publish → receive

```
POST /relay/v1/subscriptions  ["/waku/2/rs/0/0"]            → 200 (both nodes)
POST /relay/v1/messages/<shard>  {payload, contentTopic:/lp0008/1/owner-channel/proto}  (W1)  → 200
GET  /relay/v1/messages/<shard>  (W2)                       → 1 message
```

W2 received, decoded from base64:

> LP-0008 messaging use case: agent owner-channel message relayed over Waku <timestamp>

contentTopic `/lp0008/1/owner-channel/proto` — identical payload, end to end.

## Why this matters for F9

Storage (`STORAGE_TESTNET_EVIDENCE.md`) and Messaging (this doc) both demonstrated as real
distributed round-trips, removing the "single node, no peers" limitation for both
categories. Blockchain already settled on LEZ testnet (`TESTNET_EVIDENCE.md`). All three
default skill categories now have a real, networked end-to-end demonstration.

## Reproduce

```bash
docker run -d --name waku1 -p 8645:8645 -p 60000:60000 wakuorg/nwaku:v0.33.0 \
  --relay=true --pubsub-topic=/waku/2/rs/0/0 --cluster-id=0 \
  --rest=true --rest-address=0.0.0.0 --rest-port=8645 --tcp-port=60000
W1=/ip4/<waku1-ip>/tcp/60000/p2p/<waku1-peerid>
docker run -d --name waku2 -p 8646:8646 -p 60001:60001 wakuorg/nwaku:v0.33.0 \
  --relay=true --pubsub-topic=/waku/2/rs/0/0 --cluster-id=0 \
  --rest=true --rest-address=0.0.0.0 --rest-port=8646 --tcp-port=60001 --staticnode=$W1
# subscribe both to /waku/2/rs/0/0, POST a base64 payload to W1, GET it on W2
```
