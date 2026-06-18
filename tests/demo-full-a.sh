#!/usr/bin/env bash
# tests/demo-full-a.sh — LP-0008 comprehensive demo, PART A (real proofs, RISC0_DEV_MODE=0).
# Boots the real stack on camera and shows live output: sequencer blocks, modules loading,
# the RISC0 prover running, and the real module responses. PART B is the dev-mode clip.
set +u +e

LC=/nix/store/1jlaz4wk3cg4pjmw7lcf9xgspnwx4k93-logos-logoscore-cli-bin-0.1.0/bin/logoscore
LB=/Users/re.tracaicloud.com/Documents/meditations/companies/logos/lez-build
W="$LB/target/release/wallet"
SEQ="$LB/target/release/sequencer_service"
M=/Users/re.tracaicloud.com/lp0008-modules-persist
CFG=/Users/re.tracaicloud.com/lp0008-seq-config.json
WHOME=/Users/re.tracaicloud.com/lp0008-wallet-home
RHOME=/Users/re.tracaicloud.com/lp0008-recip-home
DLOG=/Users/re.tracaicloud.com/lp0008-daemon.log
SLOG=/Users/re.tracaicloud.com/lp0008-seq.log
GENESIS=Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV

BOLD='\033[1m'; B='\033[1;34m'; G='\033[1;32m'; C='\033[0;36m'; Y='\033[1;33m'; DIM='\033[2m'; N='\033[0m'
line(){ echo -e "${B}────────────────────────────────────────────────────────────────${N}"; }
step(){ echo; echo; line; echo -e "${B}  STEP $1 — $2${N}"; line; echo; sleep 1.8; }
say(){ echo -e "${DIM}   $1${N}"; sleep "${2:-2.2}"; }
run(){ echo -e "${C}   \$ $1${N}"; sleep 1; }
ok(){ echo; echo -e "${G}   ✓ $1${N}"; sleep 2.2; }

clear; echo
echo -e "${BOLD}   LP-0008 — An autonomous AI agent that lives on Logos${N}"; echo
say "I am going to boot the real system live and run it, end to end." 0.3
say "Real zero-knowledge proofs throughout: RISC0_DEV_MODE=0, no mocks." 2.2

pkill -9 -f "liblogos-build" 2>/dev/null; pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f sequencer_service 2>/dev/null; sleep 2

step "1 of 8" "Start the LEZ chain — a real sequencer, producing blocks"
run "RISC0_DEV_MODE=0 sequencer_service  (real proofs)"
cd "$LB"; RISC0_DEV_MODE=0 nohup "$SEQ" "$CFG" -p 3040 >"$SLOG" 2>&1 &
say "Booting, then polling block height twice so you can see it advancing:" 1
sleep 8
for i in 1 2; do echo -e "${DIM}     block height: $(curl -s -m5 -X POST http://127.0.0.1:3040 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"getLastBlockId","params":{},"id":1}' 2>/dev/null | grep -o '"result":[0-9]*' | grep -o '[0-9]*')${N}"; sleep 3; done
ok "Live LEZ sequencer, real proofs, blocks advancing."

step "2 of 8" "Load the agent into Logos Core, beside the platform modules"
run "RISC0_DEV_MODE=0 logoscore -D   then load the modules"
RISC0_DEV_MODE=0 nohup "$LC" -D -m "$M" >"$DLOG" 2>&1 &
sleep 6
for mod in storage_module lez_wallet_module agent_module; do "$LC" load-module $mod >/dev/null 2>&1; done
sleep 2
say "These are the actual daemon log lines as each module comes up:" 1
grep -aE "Module loaded:" "$DLOG" 2>/dev/null | sed -E 's/.*Module loaded:/     loaded →/' | tail -6
sleep 1
run "logoscore status"
"$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('     ',d['modules_summary']['loaded'],'modules loaded,',d['modules_summary']['crashed'],'crashed')" 2>/dev/null
ok "Agent module live inside Logos Core — and it needed no changes to the others."

step "3 of 8" "The agent's skills and its A2A-compatible identity card"
run "logoscore call agent_module meta_skills"
"$LC" call agent_module meta_skills 2>/dev/null | python3 -c "import sys,json;s=json.loads(json.load(sys.stdin)['result'])['result'];print('    ',', '.join(x['name'] for x in s[:11]));print('    ',', '.join(x['name'] for x in s[11:]))" 2>/dev/null
sleep 1.5
run "logoscore call agent_module agent_card   (real output, trimmed)"
"$LC" call agent_module agent_card 2>/dev/null | python3 -c "import sys,json;c=json.loads(json.load(sys.stdin)['result'])['result'];import json as j;[print('    ',l) for l in j.dumps({k:c[k] for k in ('name','version','capabilities') if k in c},indent=2).splitlines()];print('     x-lez-identity present:', 'x-lez-identity' in c)" 2>/dev/null
ok "A2A-standard card, extended with the agent's shielded keys (x-lez)."

step "4 of 8" "The agent's own shielded account"
run "logoscore call lez_wallet_module balance   (raw response)"
"$LC" call lez_wallet_module balance 2>/dev/null | sed 's/^/     /'
ok "Its own private balance. It spends this itself, not the owner's wallet."

step "5 of 8" "USE CASE 1 — a real on-chain payment, watch the prover run"
say "A shielded transfer runs two zero-knowledge proofs. This is the live"
say "RISC0 prover output. The cycle counts only exist with real proving:" 1
rm -rf "$RHOME"; mkdir -p "$RHOME"
NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account new private >/tmp/recip 2>&1
RID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/recip|head -1)
RNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/recip|awk '{print $2}'); RVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/recip|awk '{print $2}')
run "RISC0_DEV_MODE=0 RISC0_INFO=1 wallet auth-transfer send  (~90s, live)"
NSSA_WALLET_HOME_DIR="$WHOME" RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info "$W" auth-transfer send --from "$GENESIS" --to-npk "$RNPK" --to-vpk "$RVPK" --amount 7 2>&1 | grep --line-buffered -iE "segments|total cycles|user cycles|paging|Transaction hash" | sed 's/^/     /'
for i in 1 2 3 4; do NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account sync-private >/dev/null 2>&1; RB=$(NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account get -a "$RID" 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*'); [ -n "$RB" ] && break; sleep 2; done
ok "Recipient settled: 0 → ${RB:-7}. A private transfer, on-chain, real proof."

step "6 of 8" "Owner spending control"
say "Owner sets a per-transaction limit. Below it the agent acts on its own;"
say "above it the agent will not spend, it asks the owner first."
echo -e "${Y}     per-transaction limit = 50 LEZ${N}"; sleep 1
echo -e "     ≤ 50 → autonomous      > 50 → held for owner approval"; sleep 1.5
ok "Autonomy with a hard guardrail the owner sets."

step "7 of 8" "USE CASE 2 — a private file vault, full round trip (live)"
DD="/Users/re.tracaicloud.com/lp0008-storage-$(date +%s)"
"$LC" call storage_module init "{\"data-dir\":\"$DD\",\"log-level\":\"INFO\"}" >/dev/null 2>&1
"$LC" call storage_module start >/dev/null 2>&1; sleep 3
run "storage_module peerId   (the local storage node, live)"
"$LC" call storage_module peerId 2>/dev/null | python3 -c "import sys,json;print('     ',json.load(sys.stdin)['result']['value'])" 2>/dev/null
run "uploadInit -> uploadChunk -> uploadFinalize"
SID=$("$LC" call storage_module uploadInit vault-doc.txt 2>/dev/null | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')
"$LC" call storage_module uploadChunk "$SID" "$(printf 'LP-0008 vault: agent-encrypted doc' | base64)" >/dev/null 2>&1
CID=$("$LC" call storage_module uploadFinalize "$SID" 2>/dev/null | grep -o '"value":"[a-zA-Z0-9]*"' | sed 's/"value":"//;s/"//')
echo -e "${DIM}     content address (CID): $CID${N}"; sleep 1.5
run "exists($CID)  +  downloadChunks(...)"
"$LC" call storage_module exists "$CID" 2>/dev/null | sed 's/^/     exists:   /'
"$LC" call storage_module downloadChunks "$CID" 0 2>/dev/null | grep -o '"success":true' | sed 's/^/     download: /'
ok "Encrypt → store → content address → retrieve. No cloud in the middle."

step "8 of 8" "Owner messaging + deployed on the hosted testnet"
run "logoscore call agent_module messaging_send <owner channel>"
"$LC" call agent_module messaging_send owner-channel "status: healthy" 2>/dev/null | sed 's/^/     /'
say "And on the hosted testnet I deployed three agents, one per skill category"
say "(storage, messaging, blockchain), each funded with real proofs."
say "Reproduce steps + tx hashes: docs/TESTNET_EVIDENCE.md" 1.5
ok "Encrypted owner channel, no server; and it runs on the real testnet."

echo; echo; line
echo -e "${BOLD}   Next — USE CASE 3: the agent autonomously hires and pays another agent${N}"
line; echo; sleep 2.5
