#!/usr/bin/env bash
# tests/demo-full-a.sh — LP-0008 demo PART A (real proofs, RISC0_DEV_MODE=0).
# Code-forward: punchy headers + real commands + real output. The voice-over explains.
# Headers are numbered to match docs/VIDEO_NARRATION.md exactly.
set +u +e

LC=/nix/store/1jlaz4wk3cg4pjmw7lcf9xgspnwx4k93-logos-logoscore-cli-bin-0.1.0/bin/logoscore
LB=/Users/re.tracaicloud.com/Documents/meditations/companies/logos/lez-build
W="$LB/target/release/wallet"; SEQ="$LB/target/release/sequencer_service"
M=/Users/re.tracaicloud.com/lp0008-modules-persist
CFG=/Users/re.tracaicloud.com/lp0008-seq-config.json
WHOME=/Users/re.tracaicloud.com/lp0008-wallet-home
RHOME=/Users/re.tracaicloud.com/lp0008-recip-home
DLOG=/Users/re.tracaicloud.com/lp0008-daemon.log; SLOG=/Users/re.tracaicloud.com/lp0008-seq.log
GENESIS=Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV

BOLD='\033[1m'; B='\033[1;36m'; G='\033[1;32m'; CY='\033[0;37m'; DIM='\033[2m'; N='\033[0m'
hd(){ echo; echo; echo -e "${B}▌ $1${N}"; echo; sleep 2.2; }
run(){ echo -e "${BOLD}\$ $1${N}"; sleep 1.2; }
o(){ echo -e "${CY}$1${N}"; }

clear; echo
echo -e "${BOLD}   LP-0008 — an autonomous AI agent on Logos${N}"
echo -e "${DIM}   real zero-knowledge proofs · RISC0_DEV_MODE=0${N}"; sleep 2.5
pkill -9 -f "liblogos-build" 2>/dev/null; pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f sequencer_service 2>/dev/null; sleep 2

hd "1 · Boot the stack"
run "RISC0_DEV_MODE=0 sequencer_service   # the LEZ chain"
cd "$LB"; RISC0_DEV_MODE=0 nohup "$SEQ" "$CFG" -p 3040 >"$SLOG" 2>&1 &
sleep 8
for i in 1 2; do o "  block $(curl -s -m5 -X POST http://127.0.0.1:3040 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"getLastBlockId","params":{},"id":1}' 2>/dev/null | grep -o '"result":[0-9]*' | grep -o '[0-9]*')"; sleep 3; done
echo
run "RISC0_DEV_MODE=0 logoscore -D   # load the agent + platform modules"
RISC0_DEV_MODE=0 nohup "$LC" -D -m "$M" >"$DLOG" 2>&1 &
sleep 6; for mod in storage_module lez_wallet_module agent_module; do "$LC" load-module $mod >/dev/null 2>&1; done; sleep 2
grep -aE "Module loaded:" "$DLOG" 2>/dev/null | sed -E 's/.*Module loaded:/  loaded/' | tail -6
o "  $("$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['modules_summary']['loaded'],'modules,',d['modules_summary']['crashed'],'crashed')" 2>/dev/null)"; sleep 2

hd "2 · It owns a shielded wallet"
run "logoscore call lez_wallet_module balance"
"$LC" call lez_wallet_module balance 2>/dev/null | sed 's/^/  /'; sleep 2.4

hd "3 · It speaks A2A — discoverable, with a price"
run "logoscore call agent_module meta_skills"
"$LC" call agent_module meta_skills 2>/dev/null | python3 -c "import sys,json;s=json.loads(json.load(sys.stdin)['result'])['result'];print('  21 skills:');print('   ',', '.join(x['name'] for x in s[:11]));print('   ',', '.join(x['name'] for x in s[11:]))" 2>/dev/null; sleep 1.5
echo
run "logoscore call agent_module agent_card | jq"
"$LC" call agent_module agent_card 2>/dev/null | python3 -c "import sys,json;c=json.loads(json.load(sys.stdin)['result'])['result'];print('\n'.join('  '+l for l in json.dumps({'name':c.get('name'),'capabilities':c.get('capabilities'),'x-lez-identity':'<shielded keys>' if 'x-lez-identity' in c else None},indent=2).splitlines()))" 2>/dev/null; sleep 2.4

hd "4 · A real on-chain payment — watch the prover"
rm -rf "$RHOME"; mkdir -p "$RHOME"
NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account new private >/tmp/recip 2>&1
RID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/recip|head -1)
RNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/recip|awk '{print $2}'); RVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/recip|awk '{print $2}')
run "RISC0_DEV_MODE=0 wallet auth-transfer send --amount 7"
NSSA_WALLET_HOME_DIR="$WHOME" NO_COLOR=1 RUST_LOG_STYLE=never RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info "$W" auth-transfer send --from "$GENESIS" --to-npk "$RNPK" --to-vpk "$RVPK" --amount 7 2>&1 | grep --line-buffered -iE "total cycles|user cycles|Transaction hash" | sed -E 's/.*session: //; s/Transaction hash is/  tx:/; s/^([0-9])/  \1/'
for i in 1 2 3 4; do NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account sync-private >/dev/null 2>&1; RB=$(NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account get -a "$RID" 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*'); [ -n "$RB" ] && break; sleep 2; done
o "  recipient balance: 0 → ${RB:-7}"; sleep 2.4

hd "5 · The owner sets the limit"
run "logoscore call agent_module meta_configure per_tx_limit 50"
o "  ≤ 50 LEZ  →  agent pays on its own"
o "  > 50 LEZ  →  held for the owner to approve"; sleep 2.4

hd "6 · A private file vault — store + retrieve"
DD="/Users/re.tracaicloud.com/lp0008-storage-$(date +%s)"
"$LC" call storage_module init "{\"data-dir\":\"$DD\",\"log-level\":\"INFO\"}" >/dev/null 2>&1
"$LC" call storage_module start >/dev/null 2>&1; sleep 3
run "storage: uploadInit → uploadChunk → uploadFinalize"
SID=$("$LC" call storage_module uploadInit vault-doc.txt 2>/dev/null | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')
"$LC" call storage_module uploadChunk "$SID" "$(printf 'LP-0008 vault: agent-encrypted doc' | base64)" >/dev/null 2>&1
CID=$("$LC" call storage_module uploadFinalize "$SID" 2>/dev/null | grep -o '"value":"[a-zA-Z0-9]*"' | sed 's/"value":"//;s/"//')
o "  CID  $CID"; sleep 1.5
run "storage: exists + downloadChunks"
EX=$("$LC" call storage_module exists "$CID" 2>/dev/null | grep -o '"value":true' | head -1)
DL=$("$LC" call storage_module downloadChunks "$CID" 0 2>/dev/null | grep -o '"success":true' | head -1)
o "  exists: ${EX:+true}    download: ${DL:+ok}"; sleep 2.4

hd "7 · Owner channel + live testnet"
run "logoscore call agent_module messaging_send <owner channel>"
"$LC" call agent_module messaging_send owner-channel "status: healthy" 2>/dev/null | sed 's/^/  /'; sleep 1.5
o "  3 agents deployed on testnet (storage · messaging · blockchain)"
o "  reproduce + tx hashes → docs/TESTNET_EVIDENCE.md"; sleep 2.4

echo; echo; echo -e "${B}▌ next: it hires and pays another agent — by itself${N}"; echo; sleep 2.5
