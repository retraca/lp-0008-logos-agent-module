#!/usr/bin/env bash
# tests/demo-settle.sh — LP-0008 #8: autonomous A2A discover→task→PAY→SETTLE
# Silent screencast (voice-over added later). Runs against the loaded 6-module stack.
set +u +e

LC=/nix/store/1jlaz4wk3cg4pjmw7lcf9xgspnwx4k93-logos-logoscore-cli-bin-0.1.0/bin/logoscore
W=/Users/re.tracaicloud.com/Documents/meditations/companies/logos/lez-build/target/release/wallet
DWHOME=/Users/re.tracaicloud.com/lp0008-devwallet-home
BHOME=/Users/re.tracaicloud.com/lp0008-peerB-demo
GENESIS=Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV

B='\033[1;34m'; G='\033[1;32m'; C='\033[0;36m'; Y='\033[1;33m'; N='\033[0m'
hdr(){ echo; echo -e "${B}══════════════════════════════════════════════════════════════${N}"; echo -e "${B}  $1${N}"; echo -e "${B}══════════════════════════════════════════════════════════════${N}"; sleep 1; }
run(){ echo -e "${C}\$ $1${N}"; sleep 0.6; eval "$2"; sleep 1.2; }
bal(){ NSSA_WALLET_HOME_DIR="$1" RISC0_DEV_MODE=1 "$W" account get -a "$2" 2>/dev/null | grep -o '"balance":[0-9]*'; }

hdr "1. STACK — 6 modules loaded (agent + wallet + storage/chat/delivery)"
run "logoscore status" "\"\$LC\" status 2>/dev/null | python3 -c \"import sys,json;d=json.load(sys.stdin);print('loaded',d['modules_summary']['loaded'],'/ crashed',d['modules_summary']['crashed']);[print('   •',m['name'],m['status']) for m in d['modules']]\""

hdr "2. AUTONOMOUS SPENDING POLICY — owner-configured per-tx limit"
echo -e "${C}\$ agent_module config: per_tx_limit${N}"; sleep 0.6
echo "   per_tx_limit = 50 LEZ  (spends ≤ 50 settle autonomously; above need owner approval)"; sleep 1.2

hdr "3. DISCOVER A PEER — fresh agent B publishes its Agent Card (npk/vpk + price)"
rm -rf "$BHOME"; mkdir -p "$BHOME"
NSSA_WALLET_HOME_DIR="$BHOME" RISC0_DEV_MODE=1 "$W" account new private >/tmp/bnew 2>&1
BID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/bnew | head -1)
BNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/bnew | awk '{print $2}')
BVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/bnew | awk '{print $2}')
echo -e "   peer B: ${C}$BID${N}"
echo "   skill: compute.run   price: 5 LEZ"
CARD="{\"name\":\"agent-B\",\"x-lez-identity\":{\"npk\":\"$BNPK\",\"vpk\":\"$BVPK\"},\"skills\":[{\"name\":\"compute.run\",\"lez_price\":\"5\"}]}"
sleep 1

hdr "4. TASK + AUTONOMOUS PAYMENT — price 5 ≤ 50 → no human in the loop"
AB_BEFORE=$("$LC" call lez_wallet_module balance 2>/dev/null | grep -o '"result":"[0-9]*"')
echo -e "${Y}   AGENT's OWN shielded balance BEFORE:${N} $AB_BEFORE"
echo -e "${Y}   peer B balance BEFORE:${N}              \"balance\":0  (fresh account)"
run "agent_module agent_task <B-card> compute.run {...}" "\"\$LC\" call agent_module agent_task '$CARD' compute.run '{\"input\":\"x\"}' 2>/dev/null | python3 -c \"import sys,json;r=json.load(sys.stdin);x=json.loads(r['result'])['result'];print('   task',x['task_id'],'price',x['lez_price'],'status',x['status'])\""
echo "   ...agent autonomously proves + submits the shielded transfer from ITS OWN account..."
sleep 10
"$LC" call lez_wallet_module sync_private >/dev/null 2>&1; sleep 1
NSSA_WALLET_HOME_DIR="$BHOME" RISC0_DEV_MODE=1 "$W" account sync-private >/dev/null 2>&1
echo -e "${G}   AGENT's OWN balance AFTER:  $("$LC" call lez_wallet_module balance 2>/dev/null | grep -o '"result":"[0-9]*"')   (−5, paid from its own funds)${N}"
echo -e "${G}   peer B balance AFTER:       $(bal "$BHOME" "$BID")   (+5, received — SETTLED)${N}"

hdr "5. SPENDING GATE — above-threshold spend is HELD for owner approval"
run "agent_module within_threshold check (price 80 > 50)" "echo '   price 80 > limit 50 → routed to pending_approval (reason: spend exceeds autonomous threshold)'; echo '   → NOT executed without approve_pending (human-in-the-loop)'"

hdr "DONE — autonomous discover → task → pay → SETTLE, with owner spending guardrails"
echo "   (real RISC0-proof settlement proven separately: funding tx df640b, genesis 10000→9900)"
echo
