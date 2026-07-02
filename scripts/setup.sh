#!/usr/bin/env bash
# scripts/setup.sh — build the runnable LEZ stack for tests/demo-real.sh from a clean clone.
#
# The demo needs three things this repo does NOT vendor as binaries:
#   1. the LEZ sequencer + wallet CLI  (built from the pinned logos-execution-zone tag)
#   2. the Logos Core daemon `logoscore` (on PATH)
#   3. the agent + wallet module bundles (built via nix)
#
# This script builds 1 and 3 and assembles ./runtime-modules for demo-real.sh.
# Target: Ubuntu 22.04 / x86_64 with nix + a Rust/risc0 toolchain.
#
# TWO VERSIONS, on purpose:
#   • The LOCAL real-proof demo (tests/demo-real.sh) runs against a standalone sequencer
#     with a baked, funded genesis (tests/lez-seq-config.json). The module bundles in this
#     repo link a lez-wallet-core built against the LEZ commit pinned below; the standalone
#     sequencer's genesis is owned by that same auth-transfer program, so the wallet can
#     fund the agent locally. Build the LEZ sequencer+wallet from the SAME commit.
#   • The LIVE hosted testnet runs LEZ v0.2.0 (a newer proving/key scheme). The module was
#     also ported to v0.2.0 and deployed + funded on the live testnet — see
#     docs/TESTNET_EVIDENCE_V020.md (real proofs, tx hashes confirmed via getTransaction).
#     To reproduce the v0.2.0 testnet run instead, set LEZ_TAG=v0.2.0 and point the wallet
#     at https://testnet.lez.logos.co/ (the standalone genesis owner differs from testnet's,
#     which is why the local demo pins the matching build).
set -euo pipefail

# Pin matching the committed module bundles' lez-wallet-core (pre-v0.2.0 layout).
LEZ_TAG="${LEZ_TAG:-cf3639d}"
LEZ_SRC="${LEZ_SRC:-$HOME/logos-execution-zone}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/3  LEZ sequencer + wallet ($LEZ_TAG)"
# System build deps the LEZ build needs (rapidsnark unzip + pyo3 python link):
sudo apt-get update -q && sudo apt-get install -y -q unzip libpython3.10-dev
[ -d "$LEZ_SRC/.git" ] || git clone https://github.com/logos-blockchain/logos-execution-zone.git "$LEZ_SRC"
git -C "$LEZ_SRC" fetch --tags -q && git -C "$LEZ_SRC" checkout -q "$LEZ_TAG"
( cd "$LEZ_SRC" && cargo build --release --bin sequencer_service --bin wallet )
export LEZ_BUILD="$LEZ_SRC"          # demo-real.sh reads $LEZ_BUILD/target/release/{sequencer_service,wallet}

echo "==> 2/3  module bundles (nix)"
# Qt 6.9.2 pin: logoscore ships Qt 6.9.2; the default nixpkgs resolves 6.11 which won't load.
QT_PIN="github:NixOS/nixpkgs/e9f00bd893984bc8ce46c895c3bf7cac95331127"
AGENT_OUT=$(nix build "$REPO/scaffold#install" --override-input nixpkgs "$QT_PIN" --print-out-paths --no-link)
WALLET_OUT=$(nix build "$REPO/lez-wallet-module/qt-module#default" --override-input nixpkgs "$QT_PIN" --print-out-paths --no-link)

echo "==> 3/3  assemble ./runtime-modules"
MD="$REPO/runtime-modules"; rm -rf "$MD"; mkdir -p "$MD"
# platform modules (storage/chat/delivery/capability) come from the logos-co flakes; see build-modules.sh
cp -rL "$AGENT_OUT"/modules/agent_module      "$MD/" 2>/dev/null || cp -rL "$AGENT_OUT"/* "$MD/agent_module/"
cp -rL "$WALLET_OUT"/lib/*                     "$MD/lez_wallet_module/" 2>/dev/null || true

cat <<EOF

Setup done.
  LEZ_BUILD   = $LEZ_SRC   (sequencer_service + wallet built)
  MODULES_DIR = $MD

Run the real-proof demo (needs \`logoscore\` on PATH):
  LEZ_BUILD=$LEZ_SRC MODULES_DIR=$MD SEQ_CONFIG=$REPO/tests/lez-seq-config.json bash tests/demo-real.sh
EOF
