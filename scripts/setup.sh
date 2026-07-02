#!/usr/bin/env bash
# scripts/setup.sh — build the v0.2.0 LEZ stack + module bundles for the real-proof demo.
#
# This is the exact recipe used to produce the VERIFIED end-to-end run in
# docs/TESTNET_EVIDENCE_V020.md and tests/demo-testnet.sh (RISC0_DEV_MODE=0, funding tx
# getTransaction-confirmed on the live testnet). Target: Ubuntu 22.04 / x86_64 with nix
# (flakes), a Rust + risc0 toolchain, and `logoscore` on PATH.
#
# Two demo paths after this runs:
#   • tests/demo-testnet.sh — PRIMARY. Funded end-to-end against the LIVE hosted testnet
#     (the testnet has the proper genesis ownership; a lone local sequencer does not — see below).
#   • tests/demo-real.sh    — LOCAL structural demo (F1 modules load + F2 agent account) against
#     a single standalone sequencer. A standalone sequencer cannot fund from genesis: LEZ's
#     authenticated transfer needs the genesis account owned by the auth-transfer program, which
#     is set up only by the full multi-service stack (sequencer + indexer) or the hosted testnet.
set -euo pipefail

LEZ_TAG="${LEZ_TAG:-v0.2.0}"          # the commit the hosted testnet runs
LEZ_SRC="${LEZ_SRC:-$HOME/logos-execution-zone}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
QT_PIN="github:NixOS/nixpkgs/e9f00bd893984bc8ce46c895c3bf7cac95331127"   # Qt 6.9.2 (logoscore's Qt)

echo "==> 0/5  system build deps"
# unzip: rapidsnark unpack. libpython3.10-dev: v0.2.0's wallet crate links pyo3. patchelf: below.
sudo apt-get update -q && sudo apt-get install -y -q unzip libpython3.10-dev patchelf

echo "==> 1/5  LEZ sequencer + wallet ($LEZ_TAG)"
[ -d "$LEZ_SRC/.git" ] || git clone https://github.com/logos-blockchain/logos-execution-zone.git "$LEZ_SRC"
git -C "$LEZ_SRC" fetch --tags -q && git -C "$LEZ_SRC" checkout -q "$LEZ_TAG"
( cd "$LEZ_SRC" && cargo build --release --bin sequencer_service --bin wallet )

echo "==> 2/5  lez-wallet-core (linked into the wallet module) against $LEZ_TAG"
# The core's path deps are ../../lez-build/{lee/state_machine,lez/wallet,...}; point that at
# the v0.2.0 checkout, then build the staticlib the Qt module links.
rm -rf "$REPO/lez-build"; ln -sfn "$LEZ_SRC" "$REPO/lez-build"
( cd "$REPO/lez-wallet-module/lez-wallet-core" && RISC0_DEV_MODE=0 cargo build --release --features lez-bridge )
cp -f "$REPO/lez-wallet-module/lez-wallet-core/target/release/liblez_wallet_core.a" \
      "$REPO/lez-wallet-module/qt-module/corelib/liblez_wallet_core.a"

echo "==> 3/5  build the agent + wallet Qt modules (nix, Qt 6.9.2)"
AGENT_OUT=$(nix build "$REPO/scaffold#install"                 --override-input nixpkgs "$QT_PIN" --print-out-paths --no-link)
WALLET_OUT=$(nix build "$REPO/lez-wallet-module/qt-module#default" --override-input nixpkgs "$QT_PIN" --print-out-paths --no-link)

echo "==> 4/5  platform modules (storage / chat / delivery / capability) from the logos-co flakes"
STORAGE_OUT=$(nix build "github:logos-co/logos-storage-module/b1d82a32c1ba27e20d07b7ed8555fd45b02adb4e#install"  --print-out-paths --no-link)
CHAT_OUT=$(nix build    "github:logos-co/logos-chat-module/9b22b5223a3220645015592b3c17ebc541f2898d#install"     --print-out-paths --no-link)
DELIVERY_OUT=$(nix build "github:logos-co/logos-delivery-module/2577383f6e0de24793b523d6ea4991aa6339afd8#install" --print-out-paths --no-link)
CAP_OUT=$(nix build     "github:logos-co/logos-capability-module/0187d2f404a629c6f20626478986dc4249c11bec#install" --print-out-paths --no-link)

echo "==> 5/5  assemble ./runtime-modules"
MD="$REPO/runtime-modules"; rm -rf "$MD"; mkdir -p "$MD"
# platform modules come as complete dirs (module .so + shared libs + manifest.json + variant)
for out in "$STORAGE_OUT" "$CHAT_OUT" "$DELIVERY_OUT" "$CAP_OUT"; do cp -rL "$out"/modules/* "$MD/" 2>/dev/null || cp -rL "$out"/* "$MD/" 2>/dev/null || true; done
# agent module (nix output has the loadable bundle)
cp -rL "$AGENT_OUT"/modules/agent_module "$MD/" 2>/dev/null || { mkdir -p "$MD/agent_module"; cp -L "$AGENT_OUT"/lib/*agent*.so "$MD/agent_module/agent_module_plugin.so"; cp -L "$REPO/scaffold/metadata.json" "$MD/agent_module/" 2>/dev/null || true; }
# wallet module: the nix build gives the .so; package it with the committed manifest.json + variant
mkdir -p "$MD/lez_wallet_module"
cp -L "$WALLET_OUT"/lib/lez_wallet_module_plugin.so "$MD/lez_wallet_module/lez_wallet_module_plugin.so"
cp -L "$REPO/lez-wallet-module/qt-module/manifest.json" "$MD/lez_wallet_module/manifest.json"
cp -L "$REPO/lez-wallet-module/qt-module/variant"       "$MD/lez_wallet_module/variant"

echo "==> patch the wallet module for libpython (v0.2.0's wallet crate embeds pyo3)"
# Build a nix python3.10 (nix glibc, so no system-glibc/libexpat conflict with logoscore) and make
# the wallet module NEED it; without this the daemon's module scan cannot dlopen the plugin.
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
