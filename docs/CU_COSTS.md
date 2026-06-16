# LP-0008 — Compute-Unit (CU) Costs

Spec criterion (Performance): *"Document the compute unit (CU) cost of each on-chain operation the agent performs (token transfers, program calls, deployments) on LEZ devnet/testnet. Note: LEZ's per-transaction compute budget may change during testnet."*

## Finding: the LEZ sequencer does not expose CU counts

We attempted to retrieve a compute-unit cost for a settled on-chain operation through every RPC surface the standalone LEZ sequencer (`sequencer_service`, the one the demo runs against) provides:

| Method | Result | CU available? |
|--------|--------|---------------|
| `getTransaction(hash)` | returns the raw CBOR-encoded block transaction (real bytes for an included tx; `null` for a rejected one) | No CU/cycle field |
| `getBlock(n)` | binary block payload | No CU field |
| `getAccount(id)` | `{ program_owner, balance, data, nonce }` only | No |
| `getLastBlockId` / `checkHealth` | block id / health | No |
| EVM-style methods (`eth_getTransactionReceipt`, `eth_estimateGas`, …) | `-32601 Method not found` | N/A |

The sequencer indexes inclusion (a settled tx is retrievable, a rejected one is `null`) but **does not report a per-transaction compute-unit count** through any RPC method. This is a platform limitation of the current LEZ testnet sequencer, not a gap in the agent module — the sibling Lambda-Prize submissions (LP-0002, LP-0003) hit the same wall and likewise fall back to a timing proxy.

## Available cost signal: real-proof wall-clock time

The dominant cost of every on-chain operation here is **client-side RISC0 proof generation** (`RISC0_DEV_MODE=0`), measured directly:

| Operation | Real-proof wall-clock | Source |
|-----------|-----------------------|--------|
| Shielded token transfer (`wallet.send` / agent `wallet_send_to`) | **~103 s** | M6 settled tx `96724ec5…` (this run) |
| Shielded token transfer | ~187 s | M3 settled tx `f2bc62ca…` |

Measured on an Apple-silicon laptop; `r0vm` v3.0.5 observed at 700–980 % CPU during proving. `program.call` and `program.deploy` use the same privacy-preserving-transaction proving primitive, so their proving cost is of the same order (dominated by the guest cycle count of the program being proven); they were not separately settled in this local run.

## How to obtain real CU when the platform exposes it

When the LEZ testnet sequencer adds a compute-unit field to its transaction receipt (the spec anticipates the per-transaction compute budget changing during testnet), the numbers can be captured by reading that field from `getTransaction` for each settled operation — the demo script (`tests/demo-real.sh`) and `agent.wallet_send_to` already drive the operations end-to-end; only the receipt read needs the new field.

We do not fabricate CU numbers that the sequencer does not return.
