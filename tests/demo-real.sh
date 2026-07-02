#!/usr/bin/env bash
# tests/demo-real.sh — LP-0008 reproducible real-proof end-to-end demo.
#
# Self-bootstrapping: starts its own LEZ sequencer + logoscore daemon, loads the
# platform + agent modules, funds the agent on the live chain, and has the agent
# pay a fresh peer from its OWN shielded account with a REAL RISC0 proof
# (RISC0_DEV_MODE=0). No pre-running daemon and no pre-funded account required.
#
# Criteria exercised: F1 (modules load), F2 (agent's own shielded account),
# F8 (autonomous agent-to-peer payment), S5 (reproducible real-proof demo).
#
# Binaries are taken from the environment with sensible defaults so the script
# runs from a clean clone after building the LEZ stack (see README "Build").
#
#   LOGOSCORE_BIN  path to the `logoscore` CLI             (default: on PATH)
#   LEZ_BUILD      path to the built lez-build checkout     (default: ../../lez-build)
#   MODULES_DIR    dir of built module bundles             (default: ./runtime-modules)
#   SEQ_PORT       sequencer RPC port                      (default: 3040)
#
# Usage:  bash tests/demo-real.sh
set -u

# ── Configuration (env-driven, clean-clone safe) ──────────────────────────────
# Auto-detect the LEZ build and the module bundles across layouts:
#   • this repo:      ./lez-build  and  ./runtime-modules   (relative to repo root)
#   • monorepo:       ../lez-build (sibling of the module dir)
HERE="$(cd "$(dirname "$0")" && pwd)"
_first_dir(){ for d in "$@"; do [ -d "$d" ] && { cd "$d" && pwd; return; }; done; }
LOGOSCORE="${LOGOSCORE_BIN:-logoscore}"
LEZ_BUILD="${LEZ_BUILD:-$(_first_dir "$HERE/../lez-build" "$HERE/../../lez-build")}"
MODULES_DIR="${MODULES_DIR:-$(_first_dir "$HERE/../runtime-modules" "$HERE/../modules" "$HERE/../../lp0008-modules-persist")}"
SEQ_PORT="${SEQ_PORT:-3040}"
SEQ_URL="http://127.0.0.1:${SEQ_PORT}"
WALLET="${LEZ_WALLET:-$LEZ_BUILD/target/release/wallet}"
SEQUENCER="${SEQUENCER_BIN:-$LEZ_BUILD/target/release/sequencer_service}"
SEQ_CONFIG="${SEQ_CONFIG:-$HERE/lez-seq-config.json}"
WORK="${WORK_DIR:-$(mktemp -d /tmp/lp0008-demo.XXXXXX)}"
SLOG="$WORK/sequencer.log"; DLOG="$WORK/daemon.log"
GENESIS="${GENESIS_PUBLIC:-Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV}"
export RISC0_DEV_MODE=0

GRN='\033[1;32m'; CY='\033[1;36m'; DIM='\033[2m'; RED='\033[1;31m'; N='\033[0m'
YEL='\033[1;33m'
say(){ printf "${CY}\xe2\x96\x8c %s${N}\n" "$1"; }
ok(){  printf "${GRN}  \xe2\x9c\x93 %s${N}\n" "$1"; }
warn(){ printf "${YEL}  ! %s${N}\n" "$1"; }
die(){ printf "${RED}\xe2\x9c\x97 %s${N}\n" "$1" >&2; exit 1; }
jq_result(){ python3 -c "import sys,json;print(json.load(sys.stdin).get('result',''))" 2>/dev/null; }

# ── Preflight: verify binaries exist (clear errors, not silent failures) ───────
say "Preflight — RISC0_DEV_MODE=$RISC0_DEV_MODE (real proofs)"
{ command -v "$LOGOSCORE" >/dev/null 2>&1 || [ -x "$LOGOSCORE" ]; } || die "logoscore not found. Set LOGOSCORE_BIN=/path/to/logoscore (see README Build)."
[ -x "$SEQUENCER" ] || die "sequencer_service not found at $SEQUENCER. Build lez-build or set LEZ_BUILD."
[ -x "$WALLET" ]    || die "wallet not found at $WALLET. Build lez-build or set LEZ_BUILD."
[ -d "$MODULES_DIR" ] || die "modules dir not found at $MODULES_DIR. Set MODULES_DIR."
[ -f "$SEQ_CONFIG" ] || die "sequencer config not found at $SEQ_CONFIG. Set SEQ_CONFIG."
ok "binaries present; work dir $WORK"

cleanup(){ [ -n "${DAEMON_PID:-}" ] && kill "$DAEMON_PID" 2>/dev/null; [ -n "${SEQ_PID:-}" ] && kill "$SEQ_PID" 2>/dev/null; }
trap cleanup EXIT
pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f "sequencer_service" 2>/dev/null; sleep 2
# Start the agent from a clean wallet home so funding/settlement amounts are
# deterministic (a stale note synced to a prior chain has no valid membership
# proof and would abort the proving circuit; see docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md).
rm -rf "$HOME/.logoscore/data/lez_wallet_module" 2>/dev/null

# ── F1: boot the chain + load modules ─────────────────────────────────────────
say "F1 — start the LEZ sequencer and load the modules"
( cd "$LEZ_BUILD" && RISC0_DEV_MODE=0 "$SEQUENCER" "$SEQ_CONFIG" -p "$SEQ_PORT" >"$SLOG" 2>&1 ) &
SEQ_PID=$!
TIP=""
for i in $(seq 1 20); do
  TIP=$(curl -s -m5 -X POST "$SEQ_URL" -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","method":"getLastBlockId","params":{},"id":1}' 2>/dev/null | grep -o '"result":[0-9]*' | grep -o '[0-9]*')
  [ -n "$TIP" ] && break; sleep 2
done
[ -n "$TIP" ] || die "sequencer did not come up (see $SLOG)"
printf "${DIM}  chain tip: %s${N}\n" "$TIP"
RISC0_DEV_MODE=0 "$LOGOSCORE" -D -m "$MODULES_DIR" >"$DLOG" 2>&1 &
DAEMON_PID=$!
sleep 8
for mod in storage_module lez_wallet_module agent_module; do "$LOGOSCORE" load-module "$mod" >/dev/null 2>&1; done
sleep 2
LOADED=$("$LOGOSCORE" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin)['modules_summary'];print(d['loaded'],d['crashed'])" 2>/dev/null)
echo "$LOADED" | grep -qE "^[0-9]+ 0$" || die "modules failed to load cleanly: $LOADED (see $DLOG)"
ok "modules loaded: $LOADED (loaded crashed)"

# ── F2: the agent has its own shielded account ────────────────────────────────
say "F2 — the agent's own shielded LEZ account"
"$LOGOSCORE" call lez_wallet_module ensure_account >/dev/null 2>&1
"$LOGOSCORE" call lez_wallet_module balance >/dev/null 2>&1   # forces wallet_storage.json creation
"$LOGOSCORE" call lez_wallet_module sync_private >/dev/null 2>&1
WS=$(find "$HOME/.logoscore/data/lez_wallet_module" -name wallet_storage.json 2>/dev/null | head -1)
[ -n "$WS" ] || die "wallet storage not created"
# Derive npk AND vpk from the SAME source the spend path uses (wallet_storage.json),
# so funding lands on the identity the agent actually spends from.
read -r AGENT_NPK AGENT_VPK < <(python3 - "$WS" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    for e in d.get("accounts",[]):
        p=e.get("Private")
        if p:
            v=p.get("data",{}).get("value",[{}])[0]
            npk=v.get("nullifier_public_key")
            h=v.get("private_key_holder",{})
            vpk=h.get("viewing_public_key") or v.get("viewing_public_key")
            print((bytes(npk).hex() if npk else ""), (bytes(vpk).hex() if vpk else ""))
            break
except Exception:
    print("", "")
PY
)
{ [ -n "$AGENT_NPK" ] && [ -n "$AGENT_VPK" ]; } || die "could not derive agent npk/vpk from wallet storage"
printf "${DIM}  agent npk: %s${N}\n" "$AGENT_NPK"
ok "agent identity ready (spend-path npk + vpk)"

# ── Fund the agent on the live chain (public→private, real proof) ─────────────
say "Fund the agent on the live chain (public->private, real proof)"
BAL=""
if [ -n "$AGENT_VPK" ]; then
  RISC0_DEV_MODE=0 "$WALLET" auth-transfer send --from "$GENESIS" --to-npk "$AGENT_NPK" --to-vpk "$AGENT_VPK" --amount 100 >"$WORK/fund.log" 2>&1 \
    || printf "${DIM}  (funding via wallet CLI; see %s)${N}\n" "$WORK/fund.log"
fi
# Funding is a real-proof public->private tx (~90-180s) — poll generously for settlement.
for i in $(seq 1 40); do "$LOGOSCORE" call lez_wallet_module sync_private >/dev/null 2>&1; BAL=$("$LOGOSCORE" call lez_wallet_module balance 2>/dev/null | jq_result); [ "$BAL" = "100" ] && break; sleep 6; done
if [ "$BAL" != "100" ]; then
  warn "agent did not claim the funding note (balance=$BAL). The public->private funding tx settles"
  warn "on-chain, but the agent's viewing-key claim depends on a consistent keystore/storage"
  warn "identity (a documented polish item, docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md 'Scope/honesty')."
  warn "F1 (modules load) + F2 (agent account) are verified above against the real sequencer with"
  warn "RISC0_DEV_MODE=0. The real-proof autonomous payment (agent 100->95, peer 0->5) is recorded"
  warn "in docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md. Exiting NON-ZERO so this is never a false pass."
  exit 1
fi
ok "agent funded + synced — balance $BAL (in-tree note, valid membership proof)"

# ── F8: the agent pays a fresh peer from its OWN funds (real proof) ────────────
say "F8 — agent pays a fresh peer from its own shielded funds (REAL proof)"
PEER_HOME="$WORK/peer-home"; mkdir -p "$PEER_HOME"
cp "$(dirname "$WS")/wallet_config.json" "$PEER_HOME/wallet_config.json" 2>/dev/null \
  || echo '{"sequencer_addr":"'"$SEQ_URL"'/","seq_poll_timeout":"12s","seq_tx_poll_max_blocks":5,"seq_poll_max_retries":5,"seq_block_poll_max_amount":100}' > "$PEER_HOME/wallet_config.json"
PEER=$(printf 'demo\ndemo\n' | NSSA_WALLET_HOME_DIR="$PEER_HOME" RISC0_DEV_MODE=0 "$WALLET" account new private -l peer 2>&1)
PEER_NPK=$(echo "$PEER" | grep -oE 'npk [0-9a-f]{64}' | awk '{print $2}')
PEER_VPK=$(echo "$PEER" | grep -oE 'vpk [0-9a-f]{66}' | awk '{print $2}')
{ [ -n "$PEER_NPK" ] && [ -n "$PEER_VPK" ]; } || die "could not create peer account"
printf "${DIM}  peer npk: %s${N}\n" "$PEER_NPK"
printf "${DIM}  \$ logoscore call lez_wallet_module send_to <peer_npk> <peer_vpk> 5${N}\n"
# send_to triggers a real RISC0 proof (~90-180s); the RPC may time out while the
# proof completes in the background, so we confirm by settled balances below.
"$LOGOSCORE" call lez_wallet_module send_to "$PEER_NPK" "$PEER_VPK" 5 >/dev/null 2>&1 || true
say "waiting for the real proof to settle (balances are the source of truth)..."
SETTLED=""; ABAL=""; PBAL=""
for i in $(seq 1 30); do
  "$LOGOSCORE" call lez_wallet_module sync_private >/dev/null 2>&1
  ABAL=$("$LOGOSCORE" call lez_wallet_module balance 2>/dev/null | jq_result)
  NSSA_WALLET_HOME_DIR="$PEER_HOME" RISC0_DEV_MODE=0 "$WALLET" account sync-private >/dev/null 2>&1
  PBAL=$(NSSA_WALLET_HOME_DIR="$PEER_HOME" "$WALLET" account get -l peer 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*')
  if [ "$PBAL" = "5" ] && [ "$ABAL" = "95" ]; then SETTLED=1; break; fi
  sleep 6
done
if [ -z "$SETTLED" ]; then
  warn "payment did not settle in-window (agent=$ABAL peer=$PBAL); real proving can exceed the poll"
  warn "window on a loaded machine. The settled real-proof run (agent 100->95, peer 0->5) is recorded"
  warn "in docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md. Daemon log: $DLOG"
  warn "Exiting NON-ZERO so an unsettled run is never reported as a pass."
  exit 1
fi
ok "SETTLED with a real proof — agent 100->$ABAL, peer 0->$PBAL"

say "Done — F1 modules load, F2 agent account, F8 autonomous self-funded payment, all RISC0_DEV_MODE=0."
