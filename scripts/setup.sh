#!/usr/bin/env bash
# scripts/setup.sh — assemble the v0.2.0 LEZ stack + module bundles for the real-proof demo.
#
# Produces the exact stack behind the VERIFIED run in docs/TESTNET_EVIDENCE_V020.md and
# tests/demo-testnet.sh (RISC0_DEV_MODE=0, funding tx getTransaction-confirmed on the live
# testnet). Target: Ubuntu 22.04 / x86_64 with nix (flakes), a Rust + risc0 toolchain, git-lfs,
# and `logoscore` on PATH.
#
# Two demo paths after this runs:
#   • tests/demo-testnet.sh — PRIMARY. Funded end-to-end against the LIVE hosted testnet.
#   • tests/demo-real.sh    — LOCAL structural demo (F1 modules load + F2 agent account). A lone
#     standalone sequencer cannot fund from genesis (needs the full multi-service stack or the
#     hosted testnet), so the funded run is demo-testnet.sh.
#
# On the wallet module: v0.2.0's wallet crate embeds pyo3, and the logos-cpp-generator output for
# the wallet's skills exercises a gcc-14.3.0 libstdc++ std::format code path that ICEs under the
# Qt-6.9.2 nixpkgs pin (the agent module, whose generated code avoids that path, builds fine). So
# the prebuilt, verified wallet plugin is committed (Git-LFS) and used directly; only libpython is
# patched in per-machine below. To rebuild it from source you need a gcc without that libstdc++
# format bug while keeping Qt 6.9.2 — see docs/TESTNET_EVIDENCE_V020.md "Building".
set -euo pipefail

LEZ_TAG="${LEZ_TAG:-v0.2.0}"          # the commit the hosted testnet runs
LEZ_SRC="${LEZ_SRC:-$HOME/logos-execution-zone}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
QT_PIN="github:NixOS/nixpkgs/e9f00bd893984bc8ce46c895c3bf7cac95331127"   # Qt 6.9.2 (logoscore's Qt)

echo "==> 0/4  system build deps + LFS blobs"
sudo apt-get update -q && sudo apt-get install -y -q unzip libpython3.10-dev patchelf git-lfs
git -C "$REPO" lfs pull      # materialize the prebuilt wallet plugin

echo "==> 1/4  LEZ sequencer + wallet ($LEZ_TAG)"
[ -d "$LEZ_SRC/.git" ] || git clone https://github.com/logos-blockchain/logos-execution-zone.git "$LEZ_SRC"
git -C "$LEZ_SRC" fetch --tags -q && git -C "$LEZ_SRC" checkout -q "$LEZ_TAG"
( cd "$LEZ_SRC" && cargo build --release --bin sequencer_service --bin wallet )

echo "==> 2/4  agent module (nix, Qt 6.9.2) + platform modules (logos-co flakes)"
AGENT_OUT=$(nix build "$REPO/scaffold#install" --override-input nixpkgs "$QT_PIN" --print-out-paths --no-link)
STORAGE_OUT=$(nix build "github:logos-co/logos-storage-module/b1d82a32c1ba27e20d07b7ed8555fd45b02adb4e#install"  --print-out-paths --no-link)
CHAT_OUT=$(nix build    "github:logos-co/logos-chat-module/9b22b5223a3220645015592b3c17ebc541f2898d#install"     --print-out-paths --no-link)
DELIVERY_OUT=$(nix build "github:logos-co/logos-delivery-module/2577383f6e0de24793b523d6ea4991aa6339afd8#install" --print-out-paths --no-link)
CAP_OUT=$(nix build     "github:logos-co/logos-capability-module/0187d2f404a629c6f20626478986dc4249c11bec#install" --print-out-paths --no-link)

echo "==> 3/4  assemble ./runtime-modules"
MD="$REPO/runtime-modules"; rm -rf "$MD"; mkdir -p "$MD"
for out in "$STORAGE_OUT" "$CHAT_OUT" "$DELIVERY_OUT" "$CAP_OUT"; do cp -rL "$out"/modules/* "$MD/" 2>/dev/null || cp -rL "$out"/* "$MD/" 2>/dev/null || true; done
cp -rL "$AGENT_OUT"/modules/agent_module "$MD/" 2>/dev/null || { mkdir -p "$MD/agent_module"; cp -L "$AGENT_OUT"/lib/*agent*.so "$MD/agent_module/agent_module_plugin.so"; cp -L "$REPO/scaffold/metadata.json" "$MD/agent_module/" 2>/dev/null || true; }
# wallet module: committed prebuilt plugin + manifest + variant
mkdir -p "$MD/lez_wallet_module"
cp -L "$REPO/lez-wallet-module/qt-module/prebuilt/lez_wallet_module_plugin.so" "$MD/lez_wallet_module/lez_wallet_module_plugin.so"
cp -L "$REPO/lez-wallet-module/qt-module/manifest.json" "$MD/lez_wallet_module/manifest.json"
cp -L "$REPO/lez-wallet-module/qt-module/variant"       "$MD/lez_wallet_module/variant"

echo "==> 4/4  patch the wallet module for libpython (v0.2.0's wallet crate embeds pyo3)"
# Build a nix python3.10 (nix glibc — no system-glibc/libexpat clash with logoscore) and make the
# wallet plugin NEED it; without this the daemon's module scan cannot dlopen it.
NIXPY=$(nix build "$QT_PIN#python310" --print-out-paths --no-link)/lib
SO="$MD/lez_wallet_module/lez_wallet_module_plugin.so"; chmod u+w "$SO"
patchelf --add-needed libpython3.10.so.1.0 --set-rpath "$NIXPY" "$SO"

cat <<EOF

Setup done.
  LEZ_BUILD   = $LEZ_SRC
  MODULES_DIR = $MD

Real-proof demo (needs \`logoscore\` on PATH):

  # PRIMARY — funded end-to-end on the LIVE testnet (RISC0_DEV_MODE=0):
  LEZ_BUILD=$LEZ_SRC MODULES_DIR=$MD bash tests/demo-testnet.sh

  # LOCAL structural demo (F1 modules load + F2 agent account, real proofs):
  LEZ_BUILD=$LEZ_SRC MODULES_DIR=$MD SEQ_CONFIG=$REPO/tests/lez-seq-config.json bash tests/demo-real.sh
EOF
