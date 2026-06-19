# CI status

- **lint**: ✅ green.
- **e2e**: manual `workflow_dispatch` (real-proof run, minutes/proof; reproducible via `tests/demo-real.sh`, recorded in `docs/lp0008-full-demo.mp4` and `docs/lp0008-settle-demo.mp4`).
- **build** (`nix build ./scaffold#lib`): the agent's own C++ **compiles cleanly** — every application-code issue is fixed (single-line decls, AUTOMOC, `dontWrapQtApps`, `nlohmann_json`, `logos_module()` builder macro, generated-event multiple-definition removed, `delivery_module.send`, pinned `flake.lock`). It is blocked at **dependency-client generation** by an upstream packaging gap:

  The builder generates `agent_module`'s dependency client wrappers (`logos_sdk.h`) in `lp` (Qt-free, string-ctor) style because the module's `interface` is `universal`. To bind those, it needs each dependency to publish either (a) a `lidl` flake output (→ generate matching `lp` clients) or (b) an `lp`/`std` header variant. The published `logos-co/logos-{chat,storage,delivery}-module` flakes expose **only a single qt-style header package** (`StorageModule(LogosAPI*)`) and **no `lidl` output**, so:
    - `interface: universal` → the qt header is copied but the generated `lp` client calls `StorageModule("storage_module")` → ctor mismatch.
    - `interface: qt` → no dependency header is copied at all → `storage_module_api.h: No such file`.

  Neither consumer-side setting reconciles, because the dependency modules don't publish the artifact an `lp` consumer needs. The fix is upstream: the platform modules must publish a `lidl` (or `headers-std`) output, **or** they must be built in this CI to emit matching headers (the chat module compiles OpenSSL from source — impractical on a stock runner).

The module **builds and runs locally** with the platform modules present (see `EVIDENCE_LOCAL.md`, `TESTNET_EVIDENCE.md`, `EVIDENCE_PEERS.md`).
