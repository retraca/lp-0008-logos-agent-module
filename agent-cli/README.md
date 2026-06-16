# agent-cli

Single-command deploy and configure CLI for the LP-0008 autonomous AI agent module on Logos Core.

Orchestrates the `logoscore` binary as subprocesses. No daemon code — this is a thin shell over
the existing `logoscore` CLI.

---

## The one-command deploy

```bash
agent up \
  --modules-dir ./result-agent \
  --owner <YOUR-NPK-HEX> \
  --per-tx-limit 10.0 \
  --per-period-limit 100.0 \
  --period-seconds 86400 \
  --detach
```

This single invocation:
1. Starts `logoscore -D` headless with both module plugins loaded.
2. Polls until the daemon is ready (retries `meta.status()` for up to 60 s).
3. Calls `meta.configure` for each of the four config keys.
4. Leaves the daemon running in the background (`--detach`).

Add `--fund <amount> --passphrase <your-passphrase>` to also deposit LEZ into the
agent's shielded account in the same command (see TODO note below).

---

## Prerequisites

- `logoscore` on PATH, **or** set `LOGOSCORE_BIN=/path/to/logoscore`.
- `SEQUENCER` env var (or `--sequencer`) pointing at a running LEZ sequencer.
  Default: `http://127.0.0.1:3040` (the `lez-build` docker-compose chain).
- A `--modules-dir` containing:
  - `libagent_module_plugin.so` (or `.dylib`) — built from `lp-0008-ai-module/scaffold/`
  - `liblez_wallet_module_plugin.so` (or `.dylib`) — built from `lez-wallet-module/qt-module/`
  - `metadata.json` for each module

---

## Build

```bash
cd agent-cli
cargo build --release
# Binary: target/release/agent
```

Or with nix from the repository root:

```bash
cargo build --release --manifest-path lp-0008-ai-module/agent-cli/Cargo.toml
```

---

## Subcommands

### `agent deploy`

Start the daemon and load the module. Blocks unless `--detach`.

```bash
agent deploy --modules-dir ./result-agent [--detach]
```

### `agent configure`

Set spending limits and owner address on a running agent.

```bash
agent configure \
  --modules-dir ./result-agent \
  --owner <NPK-HEX> \
  --per-tx-limit 10.0 \
  --per-period-limit 100.0 \
  [--period-seconds 86400]
```

### `agent fund`

Deposit LEZ into the agent's shielded account.

```bash
agent fund --modules-dir ./result-agent --amount 50.0 --passphrase <passphrase>
```

> **TODO (runtime milestone):** The exact `lez_wallet_module` wire-method name for
> self-funding is pending API finalisation.  Current call expression:
> `wallet_fund("<passphrase>", "<amount>")`.
> Verify against `logoscore -l lez_wallet_module -c "help()"` and update
> `fund_call_expr()` in `src/main.rs` if the method name differs.
>
> Alternative path if no direct fund method exists:
> 1. `agent-cli` calls `lez_wallet_module.ensure_account("<passphrase>")` to initialise the account.
> 2. `agent-cli` calls `lez_wallet_module.npk("<passphrase>")` to retrieve the NPK.
> 3. Operator transfers LEZ from an external wallet to that NPK (out-of-band).

### `agent status`

Print the agent's current status JSON.

```bash
agent status --modules-dir ./result-agent
```

### `agent up`

Deploy + configure (+ optionally fund) in one shot.  This is the "single CLI
command" required by the LP-0008 spec (criterion 3).

```bash
agent up \
  --modules-dir ./result-agent \
  --owner <NPK-HEX> \
  --per-tx-limit 10.0 \
  --per-period-limit 100.0 \
  [--period-seconds 86400] \
  [--detach] \
  [--fund 50.0 --passphrase <passphrase>]
```

---

## Environment variables

| Variable        | Default                        | Purpose                              |
|-----------------|--------------------------------|--------------------------------------|
| `LOGOSCORE_BIN` | `logoscore`                    | Path to the logoscore binary         |
| `SEQUENCER`     | `http://127.0.0.1:3040`        | LEZ sequencer JSON-RPC URL           |

---

## How it maps to logoscore

| agent-cli action          | logoscore invocation                                                                          |
|---------------------------|-----------------------------------------------------------------------------------------------|
| spawn daemon              | `logoscore -D -m <modules-dir> -s <sequencer>`                                               |
| ready check (poll)        | `logoscore -m <dir> -s <seq> -l agent_module -c "meta.status()" --quit-on-finish --json-output` |
| configure key             | `logoscore -m <dir> -s <seq> -l agent_module -c 'meta.configure("<key>","<val>")' --quit-on-finish --json-output` |
| status                    | `logoscore -m <dir> -s <seq> -l agent_module -c "meta.status()" --quit-on-finish --json-output` |
| fund (TODO)               | `logoscore -m <dir> -s <seq> -l lez_wallet_module -c 'wallet_fund("<pass>","<amt>")' --quit-on-finish --json-output` |
