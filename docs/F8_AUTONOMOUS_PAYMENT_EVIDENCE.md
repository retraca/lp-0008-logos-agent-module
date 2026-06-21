# LP-0008 — F8 Autonomous Agent-to-Peer Payment (real proof, settled)

**Captured:** 2026-06-21 · local LEZ sequencer, `RISC0_DEV_MODE=0` (real RISC0 proofs)
**Stack:** logoscore daemon + `lez_wallet_module` + `agent_module` (6 modules loaded, 0 crashed)

Demonstrates the F8 payment leg end-to-end through the agent's **own module path** —
`logoscore call lez_wallet_module send_to <npk> <vpk> <amount>` →
`provider::send_to_foreign` → `send_private_transfer_to_outer_account` — with the agent
spending its **own shielded funds**, a real zk proof, and on-chain settlement. No human
moved the money; no CLI stand-in for the transfer itself.

## Flow

| Step | Action | Result |
|------|--------|--------|
| 1 | Fresh agent identity created in the module (`ensure_account`) | npk `8f27bf0b…`, account `DqjJK38K…` |
| 2 | Agent funded on the **current** chain (public→private, `auth-transfer` from genesis `6iArKUXx…`) | tx `f2480da5…`, +100 LEZ |
| 3 | Agent syncs to tip (`sync_private`) → in-tree note with valid membership proof | `Synced to block 1797`, balance 100 |
| 4 | **Agent pays a fresh peer** (`send_to` npk `921a17…` vpk `0386b7…`, 5 LEZ) | real proof, settled |

## Settlement — independently confirmed via balances

```
agent  (Private/Dqj…)  balance 100 → 95     # spent 5 of its own shielded funds
peer   (Private/9teRMRopW8mQ3WV9sQVDXruywrir2gxt8DcdbepjdHxD, label f8recip)
                       balance   0 →  5     # account get → {"balance":5, ...}
```

Both balances read back after `sync-private` to the live chain (tip ~1838). The agent's
note was consumed and re-committed as 95 change; the recipient's fresh commitment carries 5.

## Why earlier attempts crashed (and this one didn't)

The integrated path proves the **sender's** note, which requires a membership proof in the
**current** commitment tree. Earlier runs used a note synced to a **defunct** chain
(`last_synced_block: 4497` while the live chain was at 1652), so the note had no proof in the
current tree; the circuit (`privacy_preserving_circuit.rs:734`) asserts an unproven private
account must be `Account::default()` and aborts the module. Funding the agent **fresh on the
live chain** and syncing gives the note a valid membership proof — and the same code path then
settles cleanly. The fix is operational (fund-on-live-chain + sync before spend), not a code
change to the transfer logic.

## Scope / honesty

- This proves the **autonomous payment primitive**: the agent module spends its own shielded
  funds to pay a foreign recipient by NPK+VPK, real proof, settled.
- The A2A **discovery + task lifecycle** (agent_discover → agent_task → price resolved from the
  peer's Agent Card) is shown in `EVIDENCE_LOCAL.md` §1a–1c.
- Known polish items (do not affect the settled payment above): the module's `send_shielded`
  self-fund still mismatches the agent's own account id (funding here used the documented
  public→private `auth-transfer` deployment step), and `history` has a separate read bug.
