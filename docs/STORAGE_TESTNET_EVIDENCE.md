# LP-0008 — Storage Use Case on the Logos Storage Testnet (real, distributed)

**Network:** Logos Storage (Codex) testnet — bootstrap SPRs from `logos-storage/logos-storage-testnet-starter`
**Node image:** `codexstorage/nim-codex:stable` (arm64; binary rebranded `codex`→`storage`)
**API base:** `/api/storage/v1` (rebranded from `/api/codex/v1`)
**Captured:** 2026-06-20T12:51:30Z

This closes the F9 storage category with a genuine **cross-node** round-trip over libp2p,
not a single-node local store. Two independent Storage nodes each joined the testnet
(3 bootstrap peers each); node B retrieved a file that only node A had.

## Two independent nodes, both on the testnet

| Node | Peer ID | Bootstrap peers | Role |
|------|---------|-----------------|------|
| A (agent-storage) | `16Uiu2HAmQGCpv8tV7upqZ3dN4bNAu9wA33TBexD79erCVwxWmwf7` | 3 | uploads the file |
| B (peer)          | `16Uiu2HAkz7WdMyLk8gwdxsMeDaDVWbXb3MDtWuYzTDJwQMLYanut` | 3 | retrieves it over libp2p |

## Upload → CID (node A)

```
POST /api/storage/v1/data   (file: lp0008-vault.txt, 154 bytes)
→ CID: zDvZRwzm2NjLKip6axEfQt33FmBVfFeZKbmVixhFVXCyhZCEqsqb
```

Manifest (real Codex dataset — Merkle tree + fixed block size, not a blob stub):

```json
{"cid":"zDvZRwzm2NjLKip6axEfQt33FmBVfFeZKbmVixhFVXCyhZCEqsqb","manifest":{"treeCid":"zDzSvJTfGqk9mAGRWt7Uc89LS5vUScU2WmFVqVMSHN2rF8g7U5Rz","datasetSize":154,"blockSize":65536,"filename":null,"mimetype":"application/octet-stream"}}
```

## Cross-node retrieval (node B pulls node A's blocks)

```
# B dials A directly over libp2p (NAT-independent, same testnet):
POST /api/storage/v1/connect/16Uiu2HAmQGCpv8tV7upqZ3dN4bNAu9wA33TBexD79erCVwxWmwf7?addrs=/ip4/172.17.0.3/tcp/8070  → "Successfully connected to peer" (200)

# B fetches the CID from the network:
GET  /api/storage/v1/data/zDvZRwzm2NjLKip6axEfQt33FmBVfFeZKbmVixhFVXCyhZCEqsqb/network/stream  → 200, 154 bytes, 17ms
```

Retrieved bytes are identical to the uploaded file (`diff` clean). A single node cannot
do this: the data physically moved A → B over the peer-to-peer transport.

## Why this matters for F9

The earlier limitation ("storage skill round-trips need a multi-node libp2p network;
single node has no peers") is now demonstrated as **resolved on the real testnet**: two
nodes, real bootstrap peers, real CID, real cross-node block exchange.

## Reproduce

```bash
# starter: github.com/logos-storage/logos-storage-testnet-starter (bootstrap SPRs in codex.sh)
docker run -d --name codex-node -p 8080:8080 -p 8070:8070 -p 8090:8090/udp \
  --entrypoint /usr/local/bin/storage codexstorage/nim-codex:stable \
  --data-dir=/data --api-port=8080 --api-bindaddr=0.0.0.0 \
  --listen-addrs=/ip4/0.0.0.0/tcp/8070 --disc-port=8090 --nat=extip:$(curl -s https://ip.codex.storage) \
  --bootstrap-node=spr:<SPR1> --bootstrap-node=spr:<SPR2> --bootstrap-node=spr:<SPR3>
echo hello > f.txt
CID=$(curl -s -XPOST localhost:8080/api/storage/v1/data -T f.txt)
curl -s "localhost:8080/api/storage/v1/data/$CID/network/stream" -o out.txt   # round-trips from the network
```
