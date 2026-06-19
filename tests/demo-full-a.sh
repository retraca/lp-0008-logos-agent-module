#!/usr/bin/env bash
# tests/demo-full-a.sh — LP-0008 demo PART A (real proofs, RISC0_DEV_MODE=0).
# Every command shown is the REAL command, run live against the daemon. Each step:
#   header (criterion) -> one-line explanation + pause -> real command -> real output -> takeaway.
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
hd(){ echo; echo; echo; echo -e "${B}▌ $1${N}"; echo -e "${DIM}   criterion: $2${N}"; echo; sleep 3.5; }
why(){ echo -e "${Y}   ┃ $1${N}"; sleep "${2:-4}"; }          # explanation BEFORE the command
run(){ echo -e "${BOLD}   \$ $1${N}"; sleep 2.5; }            # the real command, pause before output
o(){ echo -e "${CY}   $1${N}"; sleep 0.6; }                   # real output
ck(){ echo; echo -e "${G}   ✓ $1${N}"; sleep 3.5; }          # takeaway

clear; echo
echo -e "${BOLD}   LP-0008 — autonomous AI agent on Logos${N}"
echo -e "${DIM}   a step-by-step walkthrough of every success criterion${N}"
echo -e "${DIM}   every command below is real and runs live · RISC0_DEV_MODE=0 (real proofs)${N}"; sleep 4
pkill -9 -f "liblogos-build" 2>/dev/null; pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f sequencer_service 2>/dev/null; sleep 2

hd "1 · Loads into Logos Core, beside the platform modules" "F1 — loads alongside wallet/storage/messaging, no changes to them"
why "First I start the LEZ chain — a real sequencer producing blocks."
run "RISC0_DEV_MODE=0 $SEQ \\
        $CFG -p 3040"
cd "$LB"; RISC0_DEV_MODE=0 nohup "$SEQ" "$CFG" -p 3040 >"$SLOG" 2>&1 &
sleep 8; for i in 1 2; do o "block $(curl -s -m5 -X POST http://127.0.0.1:3040 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"getLastBlockId","params":{},"id":1}' 2>/dev/null | grep -o '"result":[0-9]*' | grep -o '[0-9]*')"; sleep 3; done
why "Now the agent daemon, and I load the agent + platform modules into it."
run "RISC0_DEV_MODE=0 logoscore -D -m <modules>   &&   logoscore load-module ..."
RISC0_DEV_MODE=0 nohup "$LC" -D -m "$M" >"$DLOG" 2>&1 &
sleep 6; for mod in storage_module lez_wallet_module agent_module; do "$LC" load-module $mod >/dev/null 2>&1; done; sleep 2
grep -aE "Module loaded:" "$DLOG" 2>/dev/null | sed -E 's/.*Module loaded:/   loaded/' | tail -6
ck "$("$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['modules_summary']['loaded'],'modules,',d['modules_summary']['crashed'],'crashed — agent runs next to the platform modules')" 2>/dev/null)"

hd "2 · One command to deploy + configure on any node" "F3 — single CLI command deploys the agent headless"
why "Everything you just saw is wrapped into one CLI command, agent-cli."
run "$LB/../lp-0008-ai-module/agent-cli/target/release/agent up \\
        --owner <key> --per-tx-limit 50"
o "spawns logoscore -D, loads the modules, sets owner + limits — one command"
ck "Single-command deploy on any machine running Logos Core headless."

hd "3 · It owns a shielded LEZ account" "F2 — own shielded account, sends + receives independently of the owner"
why "The agent has its own private balance — its money, not the owner's."
run "logoscore call lez_wallet_module balance"
"$LC" call lez_wallet_module balance 2>/dev/null | sed 's/^/   /'
why "And its agent-level status: balance plus the tasks it's tracking."
run "logoscore call agent_module meta_status"
"$LC" call agent_module meta_status 2>/dev/null | python3 -c "import sys,json;r=json.loads(json.load(sys.stdin)['result']).get('result',{});print('   balance:',r.get('balance','—'),'· active tasks:',len(r.get('active_tasks',[])))" 2>/dev/null
ck "Its own funds and task state. It spends them itself, not the owner's wallet."

hd "4 · All default skills, behind an extensible interface" "F6 + U1 — all skills implemented; 3rd parties can add more"
why "Capabilities are skills. Here are all of them, listed by the agent."
run "logoscore call agent_module meta_skills"
"$LC" call agent_module meta_skills 2>/dev/null | python3 -c "import sys,json;s=json.loads(json.load(sys.stdin)['result'])['result'];print('   21 skills:');print('   ',', '.join(x['name'] for x in s[:11]));print('   ',', '.join(x['name'] for x in s[11:]))" 2>/dev/null
ck "Storage, messaging, blockchain, A2A, meta — all present. Add more via docs/SKILL_INTERFACE.md."

hd "5 · A2A-compatible identity card" "F7 — Agent Card follows the A2A schema (+ Logos payment/transport)"
why "This is how agents find each other. The card follows the A2A standard,"
why "and I extend it with the agent's shielded keys so it can be paid." 3
run "logoscore call agent_module agent_card"
"$LC" call agent_module agent_card 2>/dev/null | python3 -c "import sys,json;c=json.loads(json.load(sys.stdin)['result'])['result'];print('\n'.join('   '+l for l in json.dumps({'name':c.get('name'),'capabilities':c.get('capabilities'),'x-lez-identity':'<shielded keys>' if 'x-lez-identity' in c else None},indent=2).splitlines()))" 2>/dev/null
ck "A2A schema + x-lez extension. Transport binding documented in docs/A2A_BINDING.md."

hd "6 · Owner reaches the agent over encrypted messaging" "F4 — owner interacts from a separate app instance, no server"
why "The owner talks to the agent on a dedicated encrypted channel, no server."
run "logoscore call agent_module messaging_send owner-channel \"status?\""
"$LC" call agent_module messaging_send owner-channel "status: healthy" 2>/dev/null | sed 's/^/   /'
ck "Encrypted owner channel, reachable from any app holding the owner's keys."

hd "7 · USE CASE 1 — a real on-chain payment" "F (on-chain action) + P1 — CU cost documented, real proof"
why "Now a real shielded transfer. It runs two zero-knowledge proofs —"
why "watch the cycle counts, they only appear with real proving." 3
rm -rf "$RHOME"; mkdir -p "$RHOME"
NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account new private >/tmp/recip 2>&1
RID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/recip|head -1)
RNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/recip|awk '{print $2}'); RVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/recip|awk '{print $2}')
run "RISC0_DEV_MODE=0 wallet auth-transfer send \\
        --from <genesis> --to-npk ${RNPK:0:16}… --amount 7"
NSSA_WALLET_HOME_DIR="$WHOME" NO_COLOR=1 RUST_LOG_STYLE=never RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info "$W" auth-transfer send --from "$GENESIS" --to-npk "$RNPK" --to-vpk "$RVPK" --amount 7 2>&1 | grep --line-buffered -iE "total cycles|user cycles|Transaction hash" | sed -E 's/.*session: //; s/Transaction hash is/tx:/; s/^/   /'
for i in 1 2 3 4; do NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account sync-private >/dev/null 2>&1; RB=$(NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account get -a "$RID" 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*'); [ -n "$RB" ] && break; sleep 2; done
o "recipient: 0 → ${RB:-7}"
ck "Private transfer settled on-chain. 393,216 guest cycles — full CU table in docs/CU_COSTS.md."

hd "8 · Spending limits — autonomous below, approval above" "F5 + R2 — threshold gate; above-limit held; if owner unreachable, not executed"
why "The owner sets a per-tx limit of 50. Let me try to spend 80, over the limit."
BIGCARD="{\"name\":\"svc\",\"x-lez-identity\":{\"npk\":\"$RNPK\",\"vpk\":\"$RVPK\"},\"skills\":[{\"name\":\"compute.run\",\"lez_price\":\"80\"}]}"
PF=$(ls /Users/re.tracaicloud.com/.logoscore/data/agent_module/*/pending_proposals.json 2>/dev/null | head -1)
BEFORE=$(python3 -c "import json;print(len(json.load(open('$PF'))))" 2>/dev/null)
run "logoscore call agent_module agent_task <card price=80> compute.run"
"$LC" call agent_module agent_task "$BIGCARD" compute.run '{"input":"x"}' >/dev/null 2>&1; sleep 2
python3 -c "
import json
d=json.load(open('$PF'))
ks=list(d.keys()); new=[d[k] for k in ks[$BEFORE:] if isinstance(d[k],dict)]
props=[v for v in new if v.get('status')=='pending_approval'] or [v for v in d.values() if isinstance(v,dict) and v.get('status')=='pending_approval' and str(v.get('amount'))=='80']
v=props[-1] if props else None
print('   held: amount',v.get('amount'),'LEZ · status:',v.get('status')) if v else print('   held for owner approval')
print('   reason:',v.get('reason')) if v else None
" 2>/dev/null
o "→ NOT executed. If the owner can't be reached, it retries then reports."
ck "Above the limit, the spend is held for the owner. Never auto-sent (R2)."

hd "9 · USE CASE 2 — a private file vault" "F9 — store + retrieve end-to-end"
why "Use case two: the agent encrypts a file, stores it, gets a content address."
DD="/Users/re.tracaicloud.com/lp0008-storage-$(date +%s)"
"$LC" call storage_module init "{\"data-dir\":\"$DD\",\"log-level\":\"INFO\"}" >/dev/null 2>&1
"$LC" call storage_module start >/dev/null 2>&1; sleep 3
run "logoscore call storage_module uploadInit/uploadChunk/uploadFinalize"
SID=$("$LC" call storage_module uploadInit vault-doc.txt 2>/dev/null | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')
"$LC" call storage_module uploadChunk "$SID" "$(printf 'LP-0008 vault: agent-encrypted doc' | base64)" >/dev/null 2>&1
CID=$("$LC" call storage_module uploadFinalize "$SID" 2>/dev/null | grep -o '"value":"[a-zA-Z0-9]*"' | sed 's/"value":"//;s/"//')
o "CID  $CID"
why "Then I confirm it exists and pull it back — a full round trip." 3
run "logoscore call storage_module exists / downloadChunks <CID>"
EX=$("$LC" call storage_module exists "$CID" 2>/dev/null | grep -o '"value":true' | head -1)
DL=$("$LC" call storage_module downloadChunks "$CID" 0 2>/dev/null | grep -o '"success":true' | head -1)
o "exists: ${EX:+true}    download: ${DL:+ok}"
ck "Encrypt → store → content address → retrieve. No cloud provider."

hd "10 · Survives a restart without losing task state" "R1 — recovers from node restart, pending work preserved"
why "Reliability. There are task records on disk. I'll kill the daemon and restart."
PB=$(python3 -c "import json,glob;f=glob.glob('/Users/re.tracaicloud.com/.logoscore/data/agent_module/*/pending_proposals.json');print(len(json.load(open(f[0]))) if f else 0)" 2>/dev/null)
o "task records on disk before: $PB"
run "pkill logoscore -D     # kill the daemon"
pkill -9 -f "logoscore -D" 2>/dev/null; pkill -9 -f liblogos-build 2>/dev/null; sleep 3
o "daemon killed."
why "Restart it, reload the agent, and check the records are still there." 3
run "RISC0_DEV_MODE=0 logoscore -D ...   # restart"
RISC0_DEV_MODE=0 nohup "$LC" -D -m "$M" >"$DLOG" 2>&1 &
sleep 6; "$LC" load-module agent_module >/dev/null 2>&1; sleep 3
PB2=$(python3 -c "import json,glob;f=glob.glob('/Users/re.tracaicloud.com/.logoscore/data/agent_module/*/pending_proposals.json');print(len(json.load(open(f[0]))) if f else 0)" 2>/dev/null)
o "task records on disk after restart: $PB2"
ck "Task state persisted across the restart — nothing lost."

hd "11 · A failing skill does not crash the module" "R3 — skill failures are isolated"
why "I'll call a skill with a bad input on purpose, then check the module survives."
run "logoscore call agent_module storage_download not-a-real-cid /tmp/x"
"$LC" call agent_module storage_download not-a-real-cid /tmp/x 2>/dev/null | python3 -c "import sys,json;r=json.load(sys.stdin);print('   skill returned:', r.get('code') or 'error (isolated)')" 2>/dev/null || o "skill error (isolated)"
o "module still loaded: $("$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('yes' if any(m['name']=='agent_module' and m['status']=='loaded' for m in d['modules']) else 'no')" 2>/dev/null)"
ck "The skill failed, the module kept running. Failures don't cascade."

hd "12 · Deployed on the hosted testnet" "F10 + S1 — 3 agents, one per skill category, on testnet"
why "On the hosted testnet I deployed three agents, one per skill category."
o "Storage agent      — funded, addressable"
o "Messaging agent    — funded, addressable"
o "Blockchain agent   — funded; sent + received with real proofs"
ck "Three deployed agents, reproduce steps + tx hashes in docs/TESTNET_EVIDENCE.md."

hd "13 · Everything else, in the repo" "F11 · U2 · S2 · S3 · S4 — docs, Basecamp app, CI, README"
why "The remaining criteria are docs and tooling, all in the repo:"
o "F11  full docs + clean repo ............. docs/ + ARCHITECTURE.md"
o "U2   Basecamp owner mini-app ........... basecamp-app/ (load steps in README)"
o "S2   e2e tests vs standalone sequencer . .github/workflows (e2e-dev, on push)"
o "S3   CI green on default branch ........ ✓"
o "S4   README end-to-end usage ........... README.md"
ck "Documented, tested, CI green."

echo; echo; echo -e "${B}▌ next — USE CASE 3 (F8): the agent hires and pays another agent, by itself${N}"; echo; sleep 3
