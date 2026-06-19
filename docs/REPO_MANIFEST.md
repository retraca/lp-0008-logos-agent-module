# REPO_MANIFEST — LP-0008 Public Repository Packaging

This document describes exactly which files belong in the public repository, which are
local-only, and the exact git commands to create the clean standalone public repo.

---

## File manifest

### Include in the public repo

```
LICENSE
.gitignore
README.md
ARCHITECTURE.md
BUILD_PLAN.md
LEARNING.md
SUBMISSION.md
.github/
  sequencer_config.json
  workflows/
    ci.yml
docs/
  A2A_BINDING.md
  SECURITY_MODEL.md
  SKILL_INTERFACE.md
  VIDEO_NARRATION.md
  lp0008-full-a.cast        # asciinema recording — full A2A flow (plain text — committed)
  lp0008-settle-demo.cast   # asciinema recording — settle flow (plain text — committed)
  REPO_MANIFEST.md          # this file
scaffold/
  CMakeLists.txt
  flake.nix
  metadata.json
  interfaces/
    chat_module_api.cpp
    chat_module_api.h
    delivery_module_api.cpp
    delivery_module_api.h
    lez_wallet.h
    skill.h
    storage_module_api.cpp
    storage_module_api.h
  src/
    agent_module_impl.cpp
    agent_module_impl.h
  README.md
tests/
  e2e.sh
  README.md
```

### Exclude from the public repo (local-only or generated)

| Path | Reason |
|---|---|
| `scaffold/build/` | CMake build directory — compiled artefacts, auto-generated, never committed |
| `scaffold/libagent_module_plugin.so` | Compiled plugin at scaffold root — gitignored via `*.so` rule |
| `scaffold/build/libagent_module_plugin.so` | Same, inside build dir — doubly excluded |
| `docs/lp0008-full-demo.mp4` + `docs/lp0008-settle-demo.mp4` | Binary videos — force-added via `git add -f`; keep in repo for evaluator access |
| `scaffold/build/CMakeFiles/` | CMake internal directory |
| `scaffold/build/CMakeCache.txt` | CMake cache |
| `scaffold/build/build.ninja` | Ninja build file |
| `scaffold/build/.ninja_deps` | Ninja deps cache |
| `scaffold/build/.ninja_log` | Ninja log |
| `scaffold/build/.qt/` | Qt autogen artefacts |
| `scaffold/build/generated/` | Qt Remote Objects generated sources |
| `scaffold/build/sdk_generated/` | SDK generated output |
| Any `result` / `result-*` symlinks | Nix build outputs |
| `.env`, `*.key`, `*.pem` | Secrets — must never be committed |

---

## Why a standalone repo (not a subdir push)

The meditations monorepo contains large binary files from other projects (Areata map data,
video assets, compiled binaries) that are not tracked by git but live in the working tree.
A direct `git subtree push` or filter-branch from meditations risks including those artefacts
or hitting GitHub's 100 MB file-size limit. The cleanest approach is a fresh `git init` of
this subdirectory alone.

---

## Commands to create the public repo

Run these from inside the `lp-0008-ai-module/` directory. These are for the human to execute
when ready — do NOT run them now.

```bash
# Step 1 — make sure you are inside the module directory
cd /path/to/lp-0008-ai-module

# Step 2 — initialise a fresh standalone git repo
git init
git branch -M main

# Step 3 — stage only the files that belong in the public repo
#           (the .gitignore will block the excluded paths)
git add LICENSE .gitignore README.md ARCHITECTURE.md BUILD_PLAN.md LEARNING.md SUBMISSION.md
git add .github/
git add docs/A2A_BINDING.md docs/SECURITY_MODEL.md docs/SKILL_INTERFACE.md \
        docs/VIDEO_NARRATION.md docs/lp0008-full-a.cast docs/lp0008-settle-demo.cast docs/REPO_MANIFEST.md
git add scaffold/CMakeLists.txt scaffold/flake.nix scaffold/metadata.json scaffold/README.md
git add scaffold/interfaces/ scaffold/src/
git add tests/

# Step 4 — verify nothing unexpected is staged
git status
# Expected: only source files. No *.so, no build/, no *.mp4 should appear.

# Step 5 — first commit
git commit -m "feat: LP-0008 autonomous AI agent module — initial public release"

# Step 6 — create the public GitHub repo and push
#   Replace <your-github-username> with your actual handle (e.g. retraca)
gh repo create retraca/logos-lp0008-agent \
  --public \
  --description "LP-0008: Autonomous AI agent module for Logos Core (LEZ wallet + storage + messaging + A2A)" \
  --source . \
  --remote origin \
  --push
```

### Recommended public repo name

```
retraca/logos-lp0008-agent
```

Alternative if that reads better for the evaluators:

```
retraca/lp-0008-logos-agent-module
```

---

## Post-push checklist

- [ ] Confirm the repo is public: `gh repo view retraca/logos-lp0008-agent`
- [ ] Verify `.so` and `build/` are absent from the repo: `gh api repos/retraca/logos-lp0008-agent/git/trees/main?recursive=1 | jq '.tree[].path'`
- [ ] Add the repo URL to the Lambda Prize submission form
- [ ] Add voiceover narration to `docs/lp0008-full-demo.mp4` and `docs/lp0008-settle-demo.mp4` before final submission
