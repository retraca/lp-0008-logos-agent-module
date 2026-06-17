# CI status

- **lint**: ✅ green (clang-format advisory over scaffold/src + interfaces).
- **build** (`nix build ./scaffold#lib`): the agent module's own C++ compiles cleanly
  (all application-code issues resolved). It currently fails only at the platform
  **dependency header resolution** stage: the builder-generated `logos_sdk.h`
  `#include`s the `chat_/storage_/delivery_module_api.h` headers and constructs the
  generated dependency client wrappers, but the `logos-module-builder` code generator
  and the published platform-module header packages are not version-aligned for this
  combination (different generator revisions disagree on the dependency-client
  constructor signature and on which header-package layout is exposed). Pinning to one
  set surfaces a ctor mismatch; pinning to another drops the header entirely. A
  known-good version set across `logos-module-builder` + `logos-{chat,storage,delivery}-module`
  (or building those three modules in CI to emit matching headers — the chat module
  compiles OpenSSL from source) is required.
- **e2e**: manual `workflow_dispatch` only (real-proof run takes minutes per proof; the
  reproducible real-proof demo is `tests/demo-real.sh`, and the recorded run is in
  `docs/lp0008-demo.mp4`).

The module **builds and runs locally** with the platform modules present (see
`docs/EVIDENCE_LOCAL.md`, `docs/TESTNET_EVIDENCE.md`, `docs/EVIDENCE_PEERS.md`): all
six modules load, the agent funds/sends/receives on the hosted testnet, storage round-trips,
and cross-node messaging works.
