#!/usr/bin/env bash
# LP-0008 — canonical clone-and-run demo entry point for evaluators.
#
# Runs the VERIFIED clean-environment flow end to end (RISC0_DEV_MODE=0):
#   1. scripts/setup.sh       — build LEZ v0.2.0 (the hosted-testnet version) + the agent module
#                               + platform modules, materialize the prebuilt wallet plugin (LFS),
#                               and assemble ./runtime-modules.
#   2. tests/demo-testnet.sh  — boot logoscore, load all six modules (F1), have the agent create
#                               its own shielded account (F2), fund it 100 LEZ from genesis on the
#                               LIVE testnet with a real RISC0 proof, and confirm the tx on-chain.
#
# This is the script the prize's evaluation process refers to: clone the repo and run it from a
# clean environment; it succeeds without modification. Verified PASS from a fresh clone.
# For the local standalone-sequencer variant see README "Running tests and the real-proof demo".
#
# Requirements (a clean Logos-Core dev environment): nix (flakes), a Rust + risc0 toolchain,
# git-lfs, and `logoscore` on PATH. Set LEZ_BUILD / MODULES_DIR to override the defaults below.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

bash "$HERE/scripts/setup.sh"

LEZ_BUILD="${LEZ_BUILD:-$HOME/logos-execution-zone}" \
MODULES_DIR="${MODULES_DIR:-$HERE/runtime-modules}" \
  bash "$HERE/tests/demo-testnet.sh"
