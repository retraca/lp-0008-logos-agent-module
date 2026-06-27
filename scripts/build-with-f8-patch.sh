#!/usr/bin/env bash
# Build agent_module with the F8 cross-module-event fix applied to logos-cpp-sdk.
#
# The fix (patches/logos-cpp-sdk-onEvent-connect-after-init.patch) makes
# RemoteLogosObject::onEvent connect to the dynamic replica's `eventResponse`
# signal AFTER the replica is initialized, instead of before — which is the bug
# that prevents a subscribing module from ever receiving another module's events
# in qt_remote/IPC mode. With it, agent A reliably ingests agent B's Agent Card
# (full F8). See docs/F8_DISCOVERY_FIX.md for the full diagnosis.
#
# Runs in a clean environment (Linux or a fresh macOS nix store). It:
#   1. fetches the logos-cpp-sdk source rev your module-builder pins,
#   2. applies the patch,
#   3. builds .#lib with that patched cpp-sdk overridden in.
#
# Usage:  ./scripts/build-with-f8-patch.sh
# Env:    CPP_SDK_REF   override the cpp-sdk flake ref to patch (default: the rev
#                       resolved from scaffold/flake.lock).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$HERE/patches/logos-cpp-sdk-onEvent-connect-after-init.patch"
SCAFFOLD="$HERE/scaffold"
[ -f "$PATCH" ] || { echo "missing $PATCH"; exit 1; }

# 1. resolve the cpp-sdk rev the module-builder uses (override-able).
REF="${CPP_SDK_REF:-}"
if [ -z "$REF" ]; then
  REV="$(python3 - "$SCAFFOLD/flake.lock" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); n=d["nodes"]
mb=d["nodes"]["root"]["inputs"].get("logos-module-builder")
cs=n[mb]["inputs"].get("logos-cpp-sdk")
print(n[cs]["locked"]["rev"])
PY
)"
  REF="github:logos-co/logos-cpp-sdk/$REV"
fi
echo "==> patching logos-cpp-sdk: $REF"

# 2. fetch + patch into a writable git flake.
SRC="$(nix flake prefetch "$REF" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["storePath"])')"
WORK="$(mktemp -d)/cppsdk-patched"
cp -r "$SRC" "$WORK"; chmod -R u+w "$WORK"
( cd "$WORK" && patch -p1 < "$PATCH" )
( cd "$WORK" && git init -q && git add -A && git -c user.email=ci@local -c user.name=ci commit -qm "F8 onEvent connect-after-init patch" )
echo "==> patched source at $WORK"

# 3. build the agent against the patched cpp-sdk.
cd "$SCAFFOLD"
echo "==> building agent_module with the patched SDK…"
OUT="$(nix build .#lib --no-link --print-out-paths --fallback \
  --override-input "logos-module-builder/logos-cpp-sdk" "path:$WORK")"
echo "BUILT: $OUT"
echo "Deploy: cp $OUT/lib/agent_module_plugin.dylib  <modules>/agent_module/   (re-sign on macOS: codesign --force -s -)"
echo "Then run: MODULES_DIR=<modules> tests/demo-a2a-discovery.sh"
