# LP-0008 — Hosted LEZ Testnet Evidence

**Network:** `https://testnet.lez.logos.co/` (live; block height ~56,040 at capture)

> **Important — the hosted LEZ testnet has been reset since this capture.** At capture the chain
> was at block ~56,040; today `getLastBlockId` on `https://testnet.lez.logos.co/` returns ~5567,
> a fresh chain. The accounts, nonces, and tx hashes below were real and RPC-confirmed on the
> chain **at capture time** (`RISC0_DEV_MODE=0`), but they will not resolve on the current reset
> chain. The **reproducible** real-proof evidence an evaluator can run today is the local LEZ
> demos: the comprehensive video + `tests/demo-f8-linux-full.sh`, `docs/LOCAL_F10_EVIDENCE.md`,
> and `docs/F8_LINUX_FULL_EVIDENCE.txt` — same capabilities (create, fund, send, receive,
> three category agents), all with real proofs on a standalone sequencer.
**Proof mode:** `RISC0_DEV_MODE=0` (real RISC0 proofs)
**Wallet:** `lez-build/target/release/wallet`, `check-health` against the hosted testnet → **✅ All looks good** (client/sequencer versions compatible)

## Funding model

The hosted testnet has no public faucet, and the preconfigured genesis **public** accounts baked into the wallet are funded on it:

| Account | Balance (before) |
|---------|------------------|
| `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV` | 4048 |
| `Public/7wHg9sbJwc6h3NP1S9bekfAzB8CHifEcxKswCKUt3YQo` | 4000 |

We fund each agent's shielded account with native LEZ from `6iArKUXx…` via authenticated public→private transfers (real proofs).

## Three agents deployed — one per default skill category

Three separate shielded agent accounts were created and funded on the hosted testnet (`RISC0_DEV_MODE=0`):

| Agent (category) | Account ID | Funded | Funding nonce / evidence |
|------------------|-----------|--------|--------------------------|
| **Blockchain** | `Private/a48YnmT2vxNE1hVMvcu8VAUTRaoveKdDHXj9q57GoqD` | 200 | source nonce 35; commitment `5878000c…`; nullifier `ff11e6fd…` |
| **Storage** | `Private/3oTB2ZaJzWUoMEJfbA8nWYLxa88RXBHkQyWNevyD5viC` | 100 | source nonce 36; tx `dbc4006995a4099a0f3c2fb1e2a0b194b3afdd78ba2f953f064630fa6faed43b` |
| **Messaging** | `Private/G5UwwQLM6eRmXkYKUXTtJzpWtQMEsYPeLCvqEcZCaVNj` | 100 | source nonce 37; commitment `2b4bc056…`; nullifier `cfc2179a…` |

### Independent on-chain confirmation (RPC-verifiable)

The funding source account, read back from the sequencer **after** the three transfers:

```
$ wallet account get --account-id Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV
{"balance":3648,"program_owner":"CQPDUA5vFLQRZju4BmCBwBqiaWoCvjWz7Nd7D3f3JSkr","data":"","nonce":38}
```

`4048 − 200 − 100 − 100 = 3648`, nonces 35 → 38 consumed. All three fundings settled on-chain with real proofs.

## Reproduce

```bash
export NSSA_WALLET_HOME_DIR=<home>      # wallet_config.json sequencer_addr = https://testnet.lez.logos.co/
W=lez-build/target/release/wallet
RISC0_DEV_MODE=0 $W check-health
$W account new private -l agent-blockchain
$W account new private -l agent-storage
$W account new private -l agent-messaging
FROM=Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV
RISC0_DEV_MODE=0 $W auth-transfer send --from $FROM --to-label agent-blockchain --amount 200
RISC0_DEV_MODE=0 $W auth-transfer send --from $FROM --to-label agent-storage   --amount 100
RISC0_DEV_MODE=0 $W auth-transfer send --from $FROM --to-label agent-messaging --amount 100
$W account get --account-id $FROM     # → balance 3648, nonce 38
```

## Per-category demonstration

### Blockchain agent — outbound shielded transfer (SETTLED, real proof)

After `account sync-private` reached tip (`Synced to block 56131 in 164s`), the Blockchain agent sent a shielded transfer of 50 to a fresh recipient (`Private/…demo-recipient`), `RISC0_DEV_MODE=0`:

```
$ RISC0_DEV_MODE=0 wallet auth-transfer send \
    --from-label agent-blockchain --to-label demo-recipient --amount 50
# real proof generated; private→private transfer submitted
new_nullifiers:  43d571cf871b4283db73cea13143ae623995fb609f19e7aefb76a94a30e75b4c  (spends the agent's funding note)
                 cf3c5e23c28dc10e4dd10dc81c9a054fa7effbe5646981094b7817178cd4de48
new_commitments: 7beed5cea403607484da69a1ea3c742d00a7c1b31a91d3d42bb13a24a40afb44  (recipient: 50)
                 b5cd5ec41bd82a1b747939c40bcef35325f6b004ac3c598b235927a4731bd5c8  (agent change)
```

The agent both **received** (funding, above) and **sent** (here) tokens independently on the hosted testnet — the core Blockchain-category requirement. The first send attempt before sync returned "Can not pay for operation" (wallet had not yet discovered the received note); after `sync-private` to tip it proved and settled.

### Storage / Messaging agents

Funded and addressable on testnet (accounts above). Their full distributed round-trips are demonstrated on the live peer networks: a cross-node CID round-trip on the Logos Storage (Codex) testnet (`STORAGE_TESTNET_EVIDENCE.md`) and a two-node Waku relay for Logos Messaging (`MESSAGING_TESTNET_EVIDENCE.md`).

### Note on testnet operational fragility (observed)

- `account sync-private` scans from genesis to tip (~56k blocks) and the sequencer can time out on long ranges; sync persists per block, so it is re-run/looped until it reaches tip.
- The wallet's transaction poll window (`seq_tx_poll_max_blocks=5`) can report "Transaction not found in preconfigured amount of blocks" even when the tx later settles — confirmed here for the storage funding (`dbc40069…`), whose settlement is proven by the source account's subsequent nonce (37) and balance (3648).
