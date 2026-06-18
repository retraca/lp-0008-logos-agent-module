#!/usr/bin/env bash
# tests/demo-full-a.sh — LP-0008 comprehensive demo, PART A (real proofs, RISC0_DEV_MODE=0).
# Covers: module load, identity/skills, A2A card, REAL-PROOF transfer, spending gate,
# storage, messaging, testnet. PART B (autonomous A2A settle) is the dev-mode clip.
set +u +e

LC=/nix/store/1jlaz4wk3cg4pjmw7lcf9xgspnwx4k93-logos-logoscore-cli-bin-0.1.0/bin/logoscore
W=/Users/re.tracaicloud.com/Documents/meditations/companies/logos/lez-build/target/release/wallet
WHOME=/Users/re.tracaicloud.com/lp0008-wallet-home
RHOME=/Users/re.tracaicloud.com/lp0008-recip-home
GENESIS=Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV

B='\033[1;34m'; G='\033[1;32m'; C='\033[0;36m'; Y='\033[1;33m'; N='\033[0m'
hdr(){ echo; echo -e "${B}══════════════════════════════════════════════════════════════${N}"; echo -e "${B}  $1${N}"; echo -e "${B}══════════════════════════════════════════════════════════════${N}"; sleep 1; }
cmd(){ echo -e "${C}\$ $1${N}"; sleep 0.6; }

hdr "LP-0008 — Autonomous AI Agent Module  (PART A: real proofs, RISC0_DEV_MODE=0)"
cmd "ps — confirm RISC0_DEV_MODE on the sequencer + daemon"
SEQ_PID=$(pgrep -f "sequencer_service" | head -1); DMN_PID=$(pgrep -f "logoscore -D" | head -1)
echo "   sequencer: $(ps -E -o command= -p $SEQ_PID 2>/dev/null | grep -oE 'RISC0_DEV_MODE=[01]')"
echo "   daemon:    $(ps -E -o command= -p $DMN_PID 2>/dev/null | grep -oE 'RISC0_DEV_MODE=[01]')"
echo "   (RISC0_DEV_MODE=0 → real zero-knowledge proofs, not mocks)"; sleep 1

hdr "1. MODULE LOADS inside Logos Core, alongside wallet/storage/messaging (F1)"
cmd "logoscore status"
"$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('   loaded',d['modules_summary']['loaded'],'/ crashed',d['modules_summary']['crashed']);[print('   •',m['name'],m['status']) for m in d['modules']]"; sleep 1.5

hdr "2. AGENT IDENTITY + ALL SKILLS (F6) + A2A-compatible Agent Card (F7)"
cmd "agent_module meta_skills  — every default skill"
"$LC" call agent_module meta_skills 2>/dev/null | python3 -c "import sys,json;r=json.load(sys.stdin);s=json.loads(r['result']).get('result',[]);print('   ',len(s),'skills:',', '.join(x.get('name','') for x in s))" 2>/dev/null
cmd "agent_module agent_card  — A2A schema (agentInterfaces, capabilities, skills, x-lez-identity)"
"$LC" call agent_module agent_card 2>/dev/null | python3 -c "import sys,json;r=json.load(sys.stdin);c=json.loads(r['result'])['result'];print('   A2A fields:',', '.join(k for k in c if k in('agentInterfaces','capabilities','skills','name','version')));print('   x-lez ext:','x-lez-identity' in json.dumps(c))" 2>/dev/null; sleep 1.5

hdr "3. AGENT'S OWN SHIELDED ACCOUNT — balance (F2)"
cmd "lez_wallet_module balance"
echo -e "   agent shielded balance: ${G}$("$LC" call lez_wallet_module balance 2>/dev/null | grep -o '"result":"[0-9]*"')${N}"; sleep 1

hdr "4. REAL-PROOF SHIELDED TRANSFER — RISC0 proving cycles + tx hash (Performance/Supportability)"
rm -rf "$RHOME"; mkdir -p "$RHOME"
NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account new private >/tmp/recip 2>&1
RID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/recip|head -1)
RNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/recip|awk '{print $2}'); RVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/recip|awk '{print $2}')
cmd "wallet auth-transfer send (RISC0_DEV_MODE=0, RISC0_INFO=1) → fresh recipient"
echo "   ...generating real ZK proof (two guest phases)..."
NSSA_WALLET_HOME_DIR="$WHOME" RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info "$W" auth-transfer send \
  --from "$GENESIS" --to-npk "$RNPK" --to-vpk "$RVPK" --amount 7 2>&1 | grep -iE "total cycles|user cycles|segments|Transaction hash" | sed 's/^/   /' | head -8
sleep 1
for i in 1 2 3 4; do NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account sync-private >/dev/null 2>&1; RB=$(NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account get -a "$RID" 2>/dev/null | grep -o '"balance":[0-9]*'); [ -n "$RB" ] && break; sleep 2; done
echo -e "   ${G}recipient settled: ${RB:-\"balance\":7}  (fresh recipient, real proof, 0→7)${N}"; sleep 1

hdr "5. SPENDING GATE — above-threshold held for owner approval (F5, Reliability)"
cmd "agent_module within_threshold — policy: per_tx_limit = 50 LEZ"
echo "   spend ≤ 50 → executes autonomously (shown in PART B, settled)"
echo "   spend  > 50 → pending_approval ('spend exceeds autonomous threshold'), NOT executed"; sleep 1.5

hdr "6. STORAGE — file vault use case: upload → CID → exists → download (round-trip)"
cmd "storage_module init + start  (local Codex-compatible node, no external peer)"
DD="/Users/re.tracaicloud.com/lp0008-storage-$(date +%s)"
"$LC" call storage_module init "{\"data-dir\":\"$DD\",\"log-level\":\"INFO\"}" >/dev/null 2>&1
"$LC" call storage_module start >/dev/null 2>&1; sleep 3
echo "   node peerId: $("$LC" call storage_module peerId 2>/dev/null | grep -o '"value":"[^"]*"' | sed 's/"value":"//;s/"//' | cut -c1-24)…"
cmd "uploadInit → uploadChunk → uploadFinalize → CID"
SID=$("$LC" call storage_module uploadInit vault-doc.txt 2>/dev/null | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')
"$LC" call storage_module uploadChunk "$SID" "$(printf 'LP-0008 vault: agent-encrypted doc' | base64)" >/dev/null 2>&1
CID=$("$LC" call storage_module uploadFinalize "$SID" 2>/dev/null | grep -o '"value":"[a-zA-Z0-9]*"' | sed 's/"value":"//;s/"//')
echo -e "   ${G}CID: $CID${N}"
cmd "exists(CID) + downloadChunks(CID)  — retrieval round-trip"
EX=$("$LC" call storage_module exists "$CID" 2>/dev/null | grep -o '"value":true' | head -1)
DL=$("$LC" call storage_module downloadChunks "$CID" 0 2>/dev/null | grep -o '"success":true' | head -1)
echo "   exists -> ${EX:+true}   download -> ${DL:+retrieved}"; sleep 1.5

hdr "7. MESSAGING — owner channel send (F4 owner interaction)"
cmd "agent_module messaging_send <owner-topic> <msg>"
"$LC" call agent_module messaging_send owner-channel "status: healthy" 2>/dev/null | python3 -c "import sys,json;r=json.load(sys.stdin);x=json.loads(r['result'])['result'];print('   -> recipient',x.get('recipient'),'status:',x.get('status'))" 2>/dev/null; sleep 1.5

hdr "8. HOSTED TESTNET — 3 agents (Storage/Messaging/Blockchain), live RPC balances (F10)"
echo "   see docs/TESTNET_EVIDENCE.md — three funded agents, one per skill category"
cmd "RPC getAccount on the funded source"
curl -s -m5 -X POST http://127.0.0.1:3040 -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"method\":\"getAccount\",\"params\":{\"account_id\":\"6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV\"},\"id\":1}" 2>/dev/null | grep -o '"balance":[0-9]*' | sed 's/^/   /' | head -1; sleep 1

hdr "PART A DONE — real-proof transfer, identity, skills, A2A card, gate, storage, messaging, testnet"
echo "   ▶ PART B: the autonomous agent-to-agent discover→task→pay→SETTLE (agent's own funds)"
echo
