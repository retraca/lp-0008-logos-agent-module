# Logos Agent Module — LP-0008

Autonomous AI agent module for Logos Core. Lambda Prize LP-0008 submission.

## What this is

Two Logos Core universal modules (Qt, C++/Rust):

1. **`lez_wallet_module`** — new Logos Core module exposing the LEZ shielded wallet to any module via `LogosAPI`. Wraps lez-wallet-core (Rust FFI over `nssa`, `wallet`, `bedrock_client`).

2. **`agent_module`** — autonomous agent: skill dispatcher with spending-threshold gate, owner channel (E2E via `chat_module`), A2A task coordination, pluggable inference adapter.

See [SUBMISSION.md](SUBMISSION.md) for full details.

## Structure

```
lez-wallet-module/
  lez-wallet-core/           Rust crate: nssa/bedrock_client FFI bridge
  qt-module/                 Qt universal module (C++)
    liblez_wallet_module_plugin.so  Pre-built arm64 bundle

scaffold/                    Agent module (Qt universal module, pure C++)
  src/                       Full skill surface + spending gate + A2A
  interfaces/                Platform stubs + skill/wallet interfaces
  libagent_module_plugin.so  Pre-built arm64 bundle
```

## License

MIT OR Apache-2.0
