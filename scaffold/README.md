# scaffold/ — LP-0008 agent module skeleton (UNBUILT)

## Honest status

This is a **design skeleton, not a buildable module**. It was authored from reading the
real Logos repos (see `../LEARNING.md` for citations), but it has **not been compiled or
loaded**, because the research environment lacks the toolchain:

- Missing on this machine (2026-06-06): `nix`, `cmake`, `qmake`/Qt6, `go`.
- The entire Logos Core module build chain requires Nix (which pulls Qt6 + CMake + the SDK).
  See `../BUILD_PLAN.md` "Dev-environment setup".

So this directory shows the **correct module shape and full skill surface** in the real
"universal" (pure-C++) pattern, with no fabricated build artifacts. To turn it into a real,
loadable module you must do `BUILD_PLAN.md` Phase 0 (toolchain) first.

## What's here

| File | What it is |
| --- | --- |
| `metadata.json` | Real module manifest. `core` + `interface:"universal"`. Hard deps on chat/delivery/storage; **interface deps** on `lez_wallet` and `skill` (bound at runtime). |
| `src/agent_module_impl.h` | The agent's full public skill surface (the 20 prize skills + owner-approval + events) in the universal pattern. Every public method becomes a wire method via `logos-cpp-generator`. |
| `interfaces/skill.h` | The third-party **skill contract** (`ISkill`). New skills are separate modules bound via `modules().bind_skill(...)` — no core change. |
| `interfaces/lez_wallet.h` | Proposed contract for the **`lez_wallet_module` that does not exist yet** (LEARNING.md S6). The agent binds it via `modules().bind_lez_wallet(...)`. |

## What is deliberately NOT here (and why)

- **No `agent_module_impl.cpp`** — the implementation is real work (Phases 2–4 of the plan)
  and would be fabricated guesswork without a working build/test loop. Writing it blind would
  violate the "no fabricated build steps" rule.
- **No `lez_wallet_module`** — it must be built (the central gap, LEARNING.md S6d / BUILD_PLAN
  Phase 1). Only its proposed contract is sketched.
- **No `flake.nix` / `CMakeLists.txt`** — these come from `logos-module-builder` scaffolding
  (`nix flake init -t github:logos-co/logos-module-builder`) once Nix is installed; emitting them
  by hand without building risks drift from the current builder. Generate them in Phase 0.

## How to make it real (first steps)

```bash
# 1. install Nix + flakes (BUILD_PLAN dev-env setup), then in a fresh module dir:
nix flake init -t github:logos-co/logos-module-builder
# 2. replace the template src/ with src/agent_module_impl.{h,cpp}, drop in interfaces/,
#    set metadata.json to this one, add the dependency flake inputs.
git init && git add -A
nix build .#lib
nix build 'github:logos-co/logos-module#lm' --out-link ./lm
./lm/bin/lm methods ./result/lib/agent_module_plugin.* --json   # should list the 20 skills
```
