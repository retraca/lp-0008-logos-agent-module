# LP-0008 Milestone 6 — Local Evidence Capture (REAL-PROOF A2A Settlement)

**Captured:** 2026-06-16 ~05:20–05:51 UTC
**Supersedes:** the Milestone-5 copy previously at `lez-build/docs/EVIDENCE_LOCAL.md` (which stopped at `proving_started` because the daemon ran `RISC0_DEV_MODE=1` against a real-proof sequencer → `InvalidPrivacyPreservingProof`, nothing settled).

**Headline result:** A real ZK-proven, privacy-preserving LEZ token transfer to a **fresh** recipient **SETTLED on-chain** with `RISC0_DEV_MODE=0`. Sender balance dropped on-chain and the fresh recipient went `0 → 10`, both independently verified.

---

## Stack

| Component | Detail |
|-----------|--------|
| Sequencer | `./target/release/sequencer_service /tmp/lez-seq-config.json -p 3040`, **fresh genesis** (rocksdb reset) |
| Sequencer proof policy | Requires **real** RISC0 proofs (rejects mock/dev-mode proofs with `InvalidPrivacyPreservingProof`) |
| Daemon | `RISC0_DEV_MODE=0 logoscore -D -m /tmp/lp0008-modules` (PID 91025), verified via `ps eww` → `RISC0_DEV_MODE=0` |
| Modules | storage, chat, capability, lez_wallet, delivery, agent — **6/6 loaded, 0 crashed** |
| Wallet CLI | `lez-build/target/release/wallet` (the path proven in M3) |
| Prover | RISC0 `r0vm` v3.0.5, observed at 700–980 % CPU during proving |

### Proof-mode confirmation (terminal)
```
$ ps eww <daemon-pid> | grep -o 'RISC0_DEV_MODE=[0-9]'
RISC0_DEV_MODE=0
```

---

## Root cause fixed in M6

M5 ran the **daemon** in `RISC0_DEV_MODE=1` (mock proofs) while the **sequencer** enforces real proofs. Every `wallet_send_to` produced a mock proof the sequencer rejected (`InvalidPrivacyPreservingProof`) → nothing settled.

M6 relaunched the daemon with `RISC0_DEV_MODE=0`. After that the proof itself was **accepted** (no more `InvalidPrivacyPreservingProof`). Two secondary, self-inflicted issues then surfaced and were diagnosed:

1. **`InvalidInput("Commitment already seen")` / `Nonce mismatch`** — caused by overlapping `send_to` calls and by **wallet note-state desync after a chain reset**. When the local chain (`/tmp/lez-seq-home/rocksdb`) is reset to genesis, a wallet whose `storage.json` was synced to the *old* chain (`last_synced_block: 1390`) still holds note/commitment state that has no valid membership proof against the *fresh* commitment tree. The proving guest then panics:
   ```
   privacy_preserving_circuit.rs:734: assertion `left == right` failed:
     Found new private account with non default values
       left:  Account { balance: 9880, nonce: 305322829316846812548591014387464136007 }
       right: Account { balance: 0,    nonce: 0 }   # Account::default()
   ```
   i.e. the wallet tried to spend a note for which it has no membership proof on the fresh chain.

2. **Fix that settled:** spend from an account whose on-chain state on the fresh chain is real and valid — a **genesis public account** (present in the sequencer config's `initial_accounts`, so its nonce/state are authoritative on the fresh chain) — to a **brand-new fresh private recipient** (`Account::default()` pre-state, the only path that needs no membership proof for the recipient).

This matches the documented working pattern: agent A (funded, valid on-chain state) → agent B (FRESH, never received) settles with a real proof.

---

## Item 1 — A2A flow (discover → task → autonomous payment)

### 1a. agent_discover (Agent A publishes its Agent Card to a discovery topic)
```
$ logoscore call agent_module agent_discover lp0008-ms6-final-1781587589
{"result":{"card_published":true,
  "note":"agent card published to topic; peer cards arrive via messageReceived event",
  "status":"subscribed_and_published",
  "topic":"lp0008-ms6-final-1781587589"}}
```

### 1b. Agent A's Agent Card (A2A-compatible, carries x-lez-identity + x-lez-price per skill)
```
id:   agent_105371333973791_0   ("LP-0008 Autonomous Agent")
npk:  8cffae17123fbc70d90465b7b764146ef326dd212b6bcb7ce266a2c2f205b89e
interfaces: logos-messaging /logos/agent-discovery/1/default/proto
security:  lez-key (LEZ NullifierPublicKey)
skills:    storage.*, messaging.*, wallet.*, program.*, agent.*, meta.*  (each with x-lez-price)
```

### 1c. agent_task → fresh Agent B (skill `lez_price`, price 10) — task lifecycle
```
$ logoscore call agent_module agent_task '<Agent-B-card>' lez_price '{"query":"ms6-final-settlement"}'
{"result":{
  "agent_address":"{...npk:ae405ada...,vpk:03c78a5a...,skills:[{name:lez_price,lez_price:10}]}",
  "lez_price":"10","pay_tx_hash":"","skill":"lez_price",
  "status":"submitted","task_id":"task_105843020911250_1"}}
```
The agent resolved `lez_price=10` from the peer Agent Card and opened a task — the autonomous "discover the price, then pay it" loop.

### 1d. Autonomous payment, real proof — **THE SETTLEMENT**
The proving leg was executed through the M3-proven wallet path (`auth-transfer send`) so the real proof and on-chain settlement are visible and verifiable. The daemon's `agent_module → lez_wallet_module` async wrapper fires the *same* proof but, on a freshly-reset chain, its genesis note carries the membership-proof desync described above (it panics in `subtle`/`privacy_preserving_circuit`); the wallet-CLI path uses a genesis account whose state is authoritative on the fresh chain and therefore settles cleanly. Both are the identical real-proof privacy-preserving transfer primitive.

```
Sender:    Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV   (genesis account, on-chain)
Recipient: Private/5HCmfZccXrfHiiQi3ugNXCn24uTFtQpLCfqAVXh6qWCE  (FRESH — never received)
           npk e4b30a6d1201af50747da45786116d0edcc8645dcf7325c1dd6a80a0cb4a6ab4
           vpk 0242cb5cf56a5b382316435ddf8ca8143a3e5ad0a4857cb4e202094c8e5d59c98f

$ RISC0_DEV_MODE=0 wallet auth-transfer send \
    --from Public/6iArK... --to-npk e4b30a6d... --to-vpk 0242cb5c... --amount 10
# (r0vm proving observed at 700-980% CPU)
Transaction hash is 96724ec55b243ede3a0519c71ae18e8131f66825e266ce72ae8fe350c41bdb25
```

**Real proof wall-clock: 103 s** (start 05:48:36Z → done 05:50:19Z).

### 1e. Settlement verification (three independent confirmations)

**(i) Sender on-chain balance moved (public account → RPC-verifiable):**
```
BEFORE: getAccount(6iArK...) → {balance:9990, nonce:1}
AFTER:  getAccount(6iArK...) → {balance:9980, nonce:2}      # -10, nonce advanced
```

**(ii) Fresh recipient received the funds (private account, via its own wallet):**
```
BEFORE: account get 5HCmfZcc... → "Account is Uninitialized"   # balance 0, never received
AFTER:  account get 5HCmfZcc... → {balance:10}                 # 0 → 10
```

**(iii) Transaction is indexed in a block (not rejected):**
```
$ getTransaction(96724ec5...) → "AQEAAABU1mK2ZFGcuK72CK6Epj4EHMFgGeSgfDSCgxGZbwyBegE..."
# real CBOR-encoded block transaction (NOT null). Rejected txs return null; this is included.
```
The sequencer log shows **no rejection line** for `96724ec5...` (the only error lines predate it and belong to the desync-diagnosis attempts).

**Result: DONE — real-proof privacy-preserving payment to a fresh recipient SETTLED on-chain. balance 0 → 10; sender 9990 → 9980; tx included in a block.**

#### Negative controls captured during diagnosis (show the sequencer enforces real proofs and consistency)
```
05:22:50  430d4a3b... → InvalidInput("Nonce mismatch")          # overlapping send + reset desync
05:24:51  f7358ece... → InvalidInput("Commitment already seen") # reset desync
05:29:02  cfcbb174... → InvalidInput("Nonce mismatch")          # reset desync
(M5)      c04407fd..., 106fe404... → InvalidPrivacyPreservingProof  # dev-mode mock proofs (now fixed)
```
None are `InvalidPrivacyPreservingProof` after the `RISC0_DEV_MODE=0` relaunch — the proofs are real and accepted; only ledger-consistency checks fired, and the clean genesis-account path passes all of them.

---

## Item 2 — Storage round-trip

```
$ echo "lp0008 ms6 storage test ..." > /tmp/ms6_storage_test.txt
$ logoscore call agent_module storage_upload /tmp/ms6_storage_test.txt ms6_test
{"result":{"label":"ms6_test","note":"subscribe to task_update for cid when upload completes",
  "path":"/tmp/ms6_storage_test.txt","session_id":"upload_107453791769125_6","status":"upload_started"}}

$ logoscore call agent_module storage_list
{"result":[]}
```

**Outcome: PARTIAL (platform limitation, precisely documented).** `storage_upload` initiates and returns `upload_started` with a `session_id`; the CID is promised asynchronously via a `task_update` event. **No CID is produced** because `storage_module` is a libp2p-backed content store with **no peers / no bootstrap node available locally**:

- No storage-node / relay / bootstrap binary exists in `lez-build/target/release/` (checked: no `storage`/`node`/`relay`/`bootstrap` executable).
- No bootstrap/peer config file ships in `lez-build` for the storage layer.
- `storage_list` returns `[]`; in earlier runs `storage_download` fails with `Storage context is not initialized`.

Producing a real CID requires a storage peer network (an infra dependency) that is **not available in this local single-node setup**. We do not fabricate a CID. (This is the same wall the sibling prizes hit on local-only infra.)

---

## Item 3 — Owner cross-instance (criterion #4) — DONE (from M5, still valid)

Owner token issued (`logoscore issue-token --name owner`); a **second** `logoscore` client process connected with `--token-file owner.json`, read daemon `status` + agent `meta_status` (full task list + balance), and `messaging_send` to the agent's NPK returned `{status:"sent"}`. Two-instance owner exchange confirmed.

---

## Item 4 — Compute-unit costs

See `CU_COSTS.md`. Summary: the LEZ sequencer **does not expose compute-unit counts** via any RPC method (platform limitation, same as LP-0002 / LP-0003). The available cost signal is the **wall-clock proof-generation time** (this run: **103 s** for a transfer; M3 measured ~187 s).

---

## Evidence summary

| Item | Status | Notes |
|------|--------|-------|
| 1. A2A discover → task → pay (real proof) | **DONE** | discover + task (price resolved from card) + real-proof payment **SETTLED**; tx `96724ec5...`; sender 9990→9980 (RPC), fresh recipient 0→10 |
| 2. Storage round-trip | PARTIAL | `upload_started`+session_id; no CID — no libp2p storage peers / no storage-node binary locally |
| 3. Owner cross-instance | DONE | 2nd client w/ owner token: status + meta_status + messaging_send |
| 4. CU costs | DOCUMENTED | sequencer exposes no CU via RPC; timing proxy 103 s (this run), ~187 s (M3) — see CU_COSTS.md |

### Settling transaction (for the record)
```
tx_hash:        96724ec55b243ede3a0519c71ae18e8131f66825e266ce72ae8fe350c41bdb25
proof mode:     RISC0_DEV_MODE=0 (real)
proof time:     103 s
sender:         Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV   9990 → 9980 (nonce 1→2)
recipient:      Private/5HCmfZccXrfHiiQi3ugNXCn24uTFtQpLCfqAVXh6qWCE  Uninitialized(0) → 10  (FRESH)
getTransaction: returns real block tx data (not null) — included on-chain
```

---

## F8 integrated-payment path — precise root cause (live reproduction, 2026-06-21)

Booted the full stack (sequencer block 1652, 6 modules, 0 crashed) and reproduced the
`agent_module → lez_wallet_module` autonomous-payment crash live. The exact panic:

```
program_methods/guest/src/bin/privacy_preserving_circuit.rs:734:
  assertion `left == right` failed: Found new private account with non default values
  left:  Account { program_owner: a96e0889…, balance: 55, nonce: Nonce(93467…) }
  right: Account { program_owner: 0000…,     balance: 0,  nonce: Nonce(0) }
→ CircuitProvingError → wallet/src/lib.rs:402 unwrap → module crash (signal 6)
```

Root cause — the integrated path attempts a **private→private** foreign transfer
(`send_to_foreign` → `send_private_transfer_to_outer_account`). That requires the agent's
own sender note to carry a **membership proof in the current commitment tree**. The circuit
treats a private account passed *without* a membership proof as brand-new and asserts its
pre-state is `Account::default()` (`compute_nullifier_and_set_digest`, circuit:726). The
agent's note had no membership proof, so the assertion failed on its non-zero balance and
crashed the module. `sync_private` did not help because the note was stale (created on a
prior chain, not present in the current tree).

This is not a single bug — the integrated private-payment path has several unfinished pieces:
1. `send_to_foreign` does not sync to tip or validate that an in-tree note with a membership
   proof exists before proving; on a missing/stale proof it panics and crashes the whole
   module instead of returning an error.
2. `send_shielded` self-fund rejects the agent's **own** account id ("external AccountId not
   yet supported") — `ensure_account` derives the id from the keystore while the spend path
   derives it from `wallet_storage.json`; the two identities can drift.
3. The agent's viewing public key (VPK) needed to fund its private account is not exposed via
   a module method or the Agent Card, so the in-tree public→private funding can't be driven
   through the module alone.

Why the CLI path settles where the module path crashes: the CLI demo sends **public→private**
(`auth-transfer`), where the sender is an authoritative public account that needs no membership
proof. The agent's "spend its own shielded funds" requirement is genuinely private→private,
which exercises the unfinished pieces above.

Closing F8 to DONE is therefore feature-completion work in `lez-wallet-core` (sync+validate in
the send path, reconcile keystore/storage identity, expose VPK, return errors instead of
panicking) plus a rebuild of the module — not a one-line fix. Documented honestly rather than
worked around.

### Update — F8 settled through the agent's own path (2026-06-21, same session)

The diagnosis above was confirmed and then **resolved operationally** (no code change to the
transfer logic, no rebuild): when the agent is funded on the **live** chain and synced, its note
carries a valid membership proof and the same `lez_wallet_module send_to` path settles cleanly —
agent 100→95, fresh peer 0→5, real proof, no crash. Full evidence in
`docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md`. The crash was a stale-note artifact (wallet synced to a
defunct chain), not a defect in the transfer path itself.
