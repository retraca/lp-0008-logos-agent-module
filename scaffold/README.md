# scaffold/ — LP-0008 agent module

The **agent module** (`agent_module`): a Logos Core "universal" (pure-C++) module implementing
the autonomous agent runtime, owner channel, spending threshold, skill dispatch, and the
A2A-compatible coordination layer. It is built and loadable — the prebuilt bundle is
`libagent_module_plugin.so` here, and it loads alongside the wallet/storage/messaging modules
(see `../docs/EVIDENCE_LOCAL.md` and `../docs/TESTNET_EVIDENCE_V020.md`).

## What's here

| File | What it is |
| --- | --- |
| `src/agent_module_impl.{h,cpp}` | The agent implementation: the 21 prize skills, owner-approval gate, A2A card + task lifecycle, and events. Every public method becomes a wire method via `logos-cpp-generator`. |
| `metadata.json` / `module.json` | Module manifest: `core` + `interface:"universal"`, hard deps on chat/delivery/storage, interface deps on `lez_wallet` and `skill` (bound at runtime). |
| `interfaces/skill.h` | The third-party **skill contract** (`ISkill`). New skills are separate modules bound via `modules().bind_skill(...)`; see `../docs/SKILL_INTERFACE.md`. |
| `interfaces/lez_wallet.h` | The contract for `lez_wallet_module` (built separately under `../lez-wallet-module/`); the agent binds it via `modules().bind_lez_wallet(...)`. |
| `flake.nix` / `CMakeLists.txt` | The nix + CMake build (Qt 6.9.2, `logos-module-builder`). |
| `libagent_module_plugin.so` | Prebuilt module bundle (rebuild via the repo-root `../scripts/setup.sh`). |

## Build

```bash
# from the repo root — builds the sequencer/wallet and the module bundles
bash ../scripts/setup.sh

# or just this module:
nix build .#lib            # -> ./result/lib/agent_module_plugin.so + metadata.json
```

The wallet counterpart is `../lez-wallet-module/` (its Qt module wraps the Rust
`lez-wallet-core` that talks to LEZ). Both load into one `logoscore -D` daemon; the real-proof
end-to-end flow is `../tests/demo-real.sh`.
