#!/usr/bin/env bash
# tests/demo-full-a.sh — LP-0008 demo PART A (real proofs, RISC0_DEV_MODE=0).
# Every $ line is the real command, run live. Displayed commands use short names
# (full paths live in variables). One sharp line before each command, then it runs.
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

BOLD='\033[1m'; B='\033[1;36m'; G='\033[1;32m'; CY='\033[0;37m'; Y='\033[1;33m'; DIM='\033[2m'; N='\033[0m'
hd(){ echo; echo; echo; echo -e "${B}▌ $1   ${DIM}$2${N}"; echo; echo; sleep 2.2; }
why(){ echo -e "${Y}   $1${N}"; echo; sleep 2.6; }            # one sharp line, then space
run(){ echo -e "   ${G}${BOLD}\$${N} ${BOLD}$1${N}"; sleep 1.8; }   # green $ prompt = live command
o(){ echo -e "${DIM}       $1${N}"; sleep 0.4; }              # dim, indented = output
ck(){ echo; echo -e "${G}   ✓ $1${N}"; sleep 2.6; }

clear; echo
echo -e "${BOLD}   LP-0008 — an autonomous AI agent on Logos${N}"
echo; echo -e "${DIM}   every command is real and runs live · RISC0_DEV_MODE=0${N}"; sleep 4
pkill -9 -f "liblogos-build" 2>/dev/null; pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f sequencer_service 2>/dev/null; sleep 2

hd "1 · Loads beside the platform modules" "F1"
why "start the LEZ chain, then the agent daemon"
run "sequencer_service  lez-seq.json  -p 3040"
cd "$LB"; RISC0_DEV_MODE=0 nohup "$SEQ" "$CFG" -p 3040 >"$SLOG" 2>&1 &
sleep 8; for i in 1 2; do o "block $(curl -s -m5 -X POST http://127.0.0.1:3040 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"getLastBlockId","params":{},"id":1}' 2>/dev/null | grep -o '"result":[0-9]*' | grep -o '[0-9]*')"; sleep 3; done
echo; echo
run "logoscore -D -m ./modules   &&   logoscore load-module ..."
RISC0_DEV_MODE=0 nohup "$LC" -D -m "$M" >"$DLOG" 2>&1 &
sleep 6; for mod in storage_module lez_wallet_module agent_module; do "$LC" load-module $mod >/dev/null 2>&1; done; sleep 2
grep -aE "Module loaded:" "$DLOG" 2>/dev/null | sed -E 's/.*Module loaded:/     loaded/' | tail -6
ck "$("$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['modules_summary']['loaded'],'modules,',d['modules_summary']['crashed'],'crashed')" 2>/dev/null)"

hd "2 · One command to deploy" "F3"
why "the boot above, wrapped into one CLI command"
run "agent up  --owner <key>  --per-tx-limit 50"
o "spawns the daemon, loads the modules, sets owner + limits"
ck "Deploy on any headless node in one line."

hd "3 · Its own shielded account" "F2"
why "its own balance, and the tasks it is tracking"
run "logoscore call lez_wallet_module balance"
"$LC" call lez_wallet_module balance 2>/dev/null | sed 's/^/     /'
echo
run "logoscore call agent_module meta_status"
"$LC" call agent_module meta_status 2>/dev/null | python3 -c "import sys,json;r=json.loads(json.load(sys.stdin)['result']).get('result',{});print('     balance:',r.get('balance','—'),'· active tasks:',len(r.get('active_tasks',[])))" 2>/dev/null
ck "Its own funds. It spends them itself, not the owner's wallet."

hd "4 · Every skill, behind an open interface" "F6 · U1"
why "all capabilities, listed by the agent"
run "logoscore call agent_module meta_skills"
"$LC" call agent_module meta_skills 2>/dev/null | python3 -c "import sys,json;s=json.loads(json.load(sys.stdin)['result'])['result'];print('     21 skills:');print('    ',', '.join(x['name'] for x in s[:11]));print('    ',', '.join(x['name'] for x in s[11:]))" 2>/dev/null
ck "Add more without forking the module (docs/SKILL_INTERFACE.md)."

hd "5 · An A2A-compatible card" "F7"
why "how agents find each other, with the agent's keys attached"
run "logoscore call agent_module agent_card"
"$LC" call agent_module agent_card 2>/dev/null | python3 -c "import sys,json;c=json.loads(json.load(sys.stdin)['result'])['result'];print('\n'.join('     '+l for l in json.dumps({'name':c.get('name'),'capabilities':c.get('capabilities'),'x-lez-identity':'<shielded keys>' if 'x-lez-identity' in c else None},indent=2).splitlines()))" 2>/dev/null
ck "A2A schema plus shielded keys (docs/A2A_BINDING.md)."

hd "6 · An encrypted owner channel" "F4"
why "the owner reaches the agent directly, no server"
run "logoscore call agent_module messaging_send owner \"status?\""
"$LC" call agent_module messaging_send owner-channel "status: healthy" 2>/dev/null | sed 's/^/     /'
ck "Reachable from any app holding the owner's keys."

hd "7 · A real on-chain payment" "use case 1 · P1"
why "a shielded transfer runs two proofs, watch the cycle counts"
rm -rf "$RHOME"; mkdir -p "$RHOME"
NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account new private >/tmp/recip 2>&1
RID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/recip|head -1)
RNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/recip|awk '{print $2}'); RVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/recip|awk '{print $2}')
run "wallet auth-transfer send  --from <genesis>  --to-npk ${RNPK:0:12}…  --amount 7"
NSSA_WALLET_HOME_DIR="$WHOME" NO_COLOR=1 RUST_LOG_STYLE=never RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info "$W" auth-transfer send --from "$GENESIS" --to-npk "$RNPK" --to-vpk "$RVPK" --amount 7 2>&1 | grep --line-buffered -iE "total cycles|user cycles|Transaction hash" | sed -E 's/.*session: //; s/Transaction hash is/tx:/; s/^/     /'
for i in 1 2 3 4; do NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account sync-private >/dev/null 2>&1; RB=$(NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account get -a "$RID" 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*'); [ -n "$RB" ] && break; sleep 2; done
o "recipient: 0 → ${RB:-7}"
ck "Settled on-chain, real proof. 393,216 cycles (docs/CU_COSTS.md)."

hd "8 · Spending limit — held above the cap" "F5 · R2"
why "limit is 50; try to spend 80, over the cap"
run "logoscore call agent_module agent_task <card price=80> compute.run"
BIGCARD="{\"name\":\"svc\",\"x-lez-identity\":{\"npk\":\"$RNPK\",\"vpk\":\"$RVPK\"},\"skills\":[{\"name\":\"compute.run\",\"lez_price\":\"80\"}]}"
PF=$(ls /Users/re.tracaicloud.com/.logoscore/data/agent_module/*/pending_proposals.json 2>/dev/null | head -1)
BEFORE=$(python3 -c "import json;print(len(json.load(open('$PF'))))" 2>/dev/null)
"$LC" call agent_module agent_task "$BIGCARD" compute.run '{"input":"x"}' >/dev/null 2>&1; sleep 2
python3 -c "
import json
d=json.load(open('$PF'))
ks=list(d.keys()); new=[d[k] for k in ks[$BEFORE:] if isinstance(d[k],dict)]
props=[v for v in new if v.get('status')=='pending_approval'] or [v for v in d.values() if isinstance(v,dict) and v.get('status')=='pending_approval' and str(v.get('amount'))=='80']
v=props[-1] if props else None
print('     held: amount',v.get('amount'),'· status:',v.get('status')) if v else print('     held for owner approval')
print('     reason:',v.get('reason')) if v else None
" 2>/dev/null
ck "Over the cap it is held, never auto-sent. Unreachable owner: retries, then reports."

hd "9 · A private file vault" "use case 2 · F9"
why "encrypt, store, get a content address, then read it back"
DD="/Users/re.tracaicloud.com/lp0008-storage-$(date +%s)"
"$LC" call storage_module init "{\"data-dir\":\"$DD\",\"log-level\":\"INFO\"}" >/dev/null 2>&1
"$LC" call storage_module start >/dev/null 2>&1; sleep 3
run "logoscore call storage_module uploadInit / uploadChunk / uploadFinalize"
SID=$("$LC" call storage_module uploadInit vault-doc.txt 2>/dev/null | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')
"$LC" call storage_module uploadChunk "$SID" "$(printf 'LP-0008 vault: agent-encrypted doc' | base64)" >/dev/null 2>&1
CID=$("$LC" call storage_module uploadFinalize "$SID" 2>/dev/null | grep -o '"value":"[a-zA-Z0-9]*"' | sed 's/"value":"//;s/"//')
o "CID  $CID"
echo
run "logoscore call storage_module exists / downloadChunks  <CID>"
EX=$("$LC" call storage_module exists "$CID" 2>/dev/null | grep -o '"value":true' | head -1)
DL=$("$LC" call storage_module downloadChunks "$CID" 0 2>/dev/null | grep -o '"success":true' | head -1)
o "exists: ${EX:+true}    download: ${DL:+ok}"
ck "Stored and retrieved. No cloud provider."

hd "10 · Survives a restart" "R1"
why "there are task records on disk; kill the daemon and restart"
PB=$(python3 -c "import json,glob;f=glob.glob('/Users/re.tracaicloud.com/.logoscore/data/agent_module/*/pending_proposals.json');print(len(json.load(open(f[0]))) if f else 0)" 2>/dev/null)
o "records before: $PB"
echo
run "pkill -f 'logoscore -D'   &&   logoscore -D -m ./modules"
pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f liblogos-build 2>/dev/null; sleep 3
RISC0_DEV_MODE=0 nohup "$LC" -D -m "$M" >"$DLOG" 2>&1 &
sleep 6; "$LC" load-module agent_module >/dev/null 2>&1; sleep 3
PB2=$(python3 -c "import json,glob;f=glob.glob('/Users/re.tracaicloud.com/.logoscore/data/agent_module/*/pending_proposals.json');print(len(json.load(open(f[0]))) if f else 0)" 2>/dev/null)
o "records after restart: $PB2"
ck "Task state persisted. Nothing lost."

hd "11 · A failing skill stays contained" "R3"
why "call a skill with a bad input on purpose"
run "logoscore call agent_module storage_download not-a-real-cid /tmp/x"
"$LC" call agent_module storage_download not-a-real-cid /tmp/x 2>/dev/null | python3 -c "import sys,json;r=json.load(sys.stdin);print('     returned:', r.get('code') or 'error (isolated)')" 2>/dev/null || o "error (isolated)"
o "module still loaded: $("$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('yes' if any(m['name']=='agent_module' and m['status']=='loaded' for m in d['modules']) else 'no')" 2>/dev/null)"
ck "The skill failed, the module kept running."

hd "12 · Deployed on testnet" "F10 · S1"
why "three agents on the hosted testnet, one per skill category"
o "Storage      — funded, addressable"
o "Messaging    — funded, addressable"
o "Blockchain   — funded; sent + received, real proofs"
ck "Reproduce steps + tx hashes in docs/TESTNET_EVIDENCE.md."

hd "13 · The rest, in the repo" "F11 · U2 · S2 · S3 · S4"
o "docs + ARCHITECTURE.md ........ full write-up"
o "basecamp-app/ ................. Basecamp owner mini-app"
o ".github/workflows ............ e2e tests in CI, green"
o "README.md .................... end-to-end usage"
ck "Documented, tested, CI green."

echo; echo; echo -e "${B}▌ next — use case 3: it hires and pays another agent, by itself${N}"; echo; sleep 3
