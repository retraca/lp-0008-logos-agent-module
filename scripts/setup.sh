#!/usr/bin/env bash
# scripts/setup.sh — build the runnable LEZ stack for tests/demo-real.sh from a clean clone.
#
# The demo needs three things this repo does NOT vendor as binaries:
#   1. the LEZ sequencer + wallet CLI  (built from the pinned logos-execution-zone tag)
#   2. the Logos Core daemon `logoscore` (on PATH)
#   3. the agent + wallet module bundles (built via nix)
#
# This script builds 1 and 3. Target: Ubuntu 22.04 / x86_64 with nix + a Rust/risc0 toolchain.
#
# Two demo paths (pick one):
#   • tests/demo-testnet.sh — the REAL-PROOF reproduction against the LIVE hosted testnet
#     (LEZ v0.2.0). Verified end-to-end: the agent module creates its shielded account, the
#     owner funds it from genesis, and the agent reads its balance back through its own skill,
#     all with RISC0_DEV_MODE=0. Tx hashes are getTransaction-confirmed in
#     docs/TESTNET_EVIDENCE_V020.md. This is the primary real-proof demo — it needs only
#     network access to https://testnet.lez.logos.co/ (no local chain to stand up).
#   • tests/demo-real.sh — the LOCAL structural demo against a single standalone sequencer:
#     it proves F1 (all modules load) and F2 (the agent creates its own shielded account)
#     with RISC0_DEV_MODE=0. NOTE: a single standalone sequencer binary cannot fund from
#     genesis — LEZ's authenticated-transfer needs the genesis account owned by the
#     auth-transfer program, which is set up by the full multi-service stack
#     (sequencer + indexer, via the upstream docker-compose) or by the hosted testnet.
#     So the funded end-to-end payment is reproduced by demo-testnet.sh (or the docker stack),
#     and demo-real.sh exits honestly if the standalone funding step cannot settle.
set -euo pipefail

# Build the LEZ version the hosted testnet runs, so the wallet is testnet-compatible.
LEZ_TAG="${LEZ_TAG:-v0.2.0}"
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

Real-proof demo (needs \`logoscore\` on PATH):

  # PRIMARY — funded end-to-end on the LIVE testnet (RISC0_DEV_MODE=0):
  LEZ_BUILD=$LEZ_SRC MODULES_DIR=$MD bash tests/demo-testnet.sh

  # LOCAL structural demo (F1 modules load + F2 agent account, real proofs):
  LEZ_BUILD=$LEZ_SRC MODULES_DIR=$MD SEQ_CONFIG=$REPO/tests/lez-seq-config.json bash tests/demo-real.sh
EOF
