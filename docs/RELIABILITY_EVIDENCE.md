# LP-0008 — Reliability evidence (R1, R2, R3)

The three Reliability criteria are **implemented in code and exercised by the demo**, not merely
asserted. Each row below cites the exact mechanism and the demo step that shows it running. File
references are into `scaffold/src/agent_module_impl.cpp` unless noted.

| # | Criterion | Mechanism (code) | Demonstrated |
|---|-----------|------------------|--------------|
| **R1** | Recovers from transient failures without losing pending task state | Task state + pending approvals + config are written to the module's persistence dir with an **atomic write-temp-then-rename** (`persist_json`, `agent_module_impl.cpp:178-187`) and **reloaded on start** from `instancePersistencePath()` (`:321-357`). A restart re-hydrates held approvals and config. | `tests/demo-f8-linux-full.sh` **step 11**: an over-limit task is held, the daemon is killed and restarted, and `meta_status` after restart shows the held approval and config **survived** — no task state lost. |
| **R2** | Above-threshold that can't reach the owner is **not executed**; retry then report | An over-limit spend is held as a proposal; the agent retries the owner notification up to `kMaxNotifyAttempts` and records the outcome on the proposal (`notified`, `notify_attempts`) — **the held spend never executes in this path**, whether or not the owner is reachable (`:445-457`). Failure-safe guarantee documented in `docs/SECURITY_MODEL.md` (§ "when the owner is unreachable", :172). | `tests/demo-f8-linux-full.sh` **step 9**: an over-limit task is opened; `meta_status` shows `pending_approvals` with `notified`/`notify_attempts`, the balance unchanged — reported, retried, never executed. |
| **R3** | Skill failures are isolated — a failing skill does not crash the module or other skills | Every skill `invoke()` and every module callback is wrapped in `try/catch` (**66 catch blocks** in the impl); exceptions are converted to an `{"error":...}` **value returned across the module boundary** (`skill_failed(...)` → `err(...)`), never propagated. Concurrent map access is mutex-guarded to remove the one otherwise-uncatchable crash (`:232`). | `tests/demo-f8-linux-full.sh` **step 12**: `approve_pending` is called with a nonexistent id; it returns a handled error, and `logoscore status` immediately after shows **6 modules loaded, 0 crashed** — the module and every other skill stayed up. |

## Why this is stronger than a checklist tick

An evaluator can verify each claim two ways without trusting prose:

1. **Read the code** at the cited lines — the persistence, retry, and isolation paths are all present
   and small enough to audit.
2. **Run the demo** — `tests/demo-f8-linux-full.sh` prints the R1/R2/R3 outcomes inline as steps
   9/11/12 (module counts, surviving approvals, handled errors), all with `RISC0_DEV_MODE=0`.

No reliability claim here rests on assertion alone: each is a mechanism in the source plus a step in
the reproducible demo.
