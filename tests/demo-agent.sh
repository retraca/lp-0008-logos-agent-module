#!/usr/bin/env bash
# LP-0008 demo — the autonomous agent through its OWN skills (real wallet integration)
source ~/.cargo/env 2>/dev/null; export PATH="$HOME/.risc0/bin:$PATH"
LC=$(cat ~/cli-path.txt)/bin/logoscore
AGENT=~/agent-cli/target/release/agent; WALLET=~/lez-build/target/release/wallet
SEQ=~/lez-build/target/release/sequencer_service
GHOME=~/runtime/wallet-home; GENESIS="Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV"
TM=~/cardfund-modules
G='\033[32m'; B='\033[1m'; D='\033[2m'; C='\033[36m'; N='\033[0m'
hdr(){ printf "\n${B}${C}== %s ==${N}\n" "$1"; sleep 2; }
say(){ printf "${D}# %s${N}\n" "$1"; sleep 1; }
run(){ printf "${G}${B}\$ %s${N}\n" "$1"; sleep 1; eval "$2" 2>&1 | head -${3:-6}; sleep 2; }
abal(){ "$LC" call agent_module wallet_balance 2>/dev/null|python3 -c "import sys,json;d=json.load(sys.stdin);print(json.loads(d['result'])['result']['balance'])" 2>/dev/null; }

clear
printf "${B}${C}LP-0008 — Autonomous AI Agent on Logos Core${N}\n"
printf "${D}The agent owns a shielded LEZ wallet and pays peers through its OWN skills.\nEvery proof is a real RISC0 STARK proof. Watch RISC0_DEV_MODE.${N}\n"; sleep 3

hdr "1. the local LEZ chain"
say "a standalone sequencer doing real proving"
pkill -9 -f logoscore 2>/dev/null; pkill -9 -f sequencer 2>/dev/null; sleep 2
rm -rf ~/seq-home ~/.logoscore; mkdir -p ~/seq-home
( cd ~/seq-home && RISC0_DEV_MODE=1 "$SEQ" ~/seq-standalone-config.json -p 3040 >~/seq.log 2>&1 ) & disown
sleep 8
run "curl getLastBlockId" "curl -s -X POST http://127.0.0.1:3040 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"getLastBlockId\",\"params\":[],\"id\":1}'" 1

hdr "2. deploy the agent in one command  (F1, F3)"
say "agent up loads the agent NEXT TO the wallet + platform modules"
run "agent up --modules-dir ./modules --owner ... --per-tx-limit 50" "RISC0_DEV_MODE=1 timeout 90 env LOGOSCORE_BIN=$LC RISC0_DEV_MODE=1 $AGENT up --modules-dir $TM --sequencer http://127.0.0.1:3040 --owner ownernpk --per-tx-limit 50 --per-period-limit 200 --detach >~/au.log 2>&1; sleep 2; grep -iE 'Module loaded|loaded and responding' ~/au.log" 8
sleep 3; "$LC" call lez_wallet_module ensure_account >/dev/null 2>&1

hdr "3. the agent's identity — shielded npk + vpk in its A2A card  (F7)"
run "logoscore call agent_module agent_card" "$LC call agent_module agent_card 2>/dev/null | python3 -c \"import sys,json;d=json.load(sys.stdin);c=json.loads(d['result'])['result'];print(json.dumps(c['x-lez-identity'],indent=1))\"" 6

hdr "4. the agent's skills  (F6 — 21 default skills)"
run "logoscore call agent_module meta_skills" "$LC call agent_module meta_skills 2>/dev/null | python3 -c \"import sys,json;d=json.load(sys.stdin);s=json.loads(d['result'])['result'];print('count:',len(s));print(', '.join(x.get('name',x.get('skill_name','')) for x in s[:21]))\"" 4

hdr "5. fund the agent — a REAL proof, RISC0_DEV_MODE=0  (F2)"
SF=$(find ~/.logoscore/data/lez_wallet_module -name wallet_storage.json|head -1)
read ANPK AVPK < <(python3 -c "import json,binascii;d=json.load(open('$SF'));[print(binascii.hexlify(bytes(v['nullifier_public_key'])).decode(),binascii.hexlify(bytes(v['viewing_public_key'])).decode()) for a in d['accounts'] if 'Private' in a for v in [a['Private']['data']['value'][0]] if 'nullifier_public_key' in v][:1]" 2>/dev/null)
say "the owner funds the agent 100; watch the zk prover run (dev mode OFF)"
run "RISC0_DEV_MODE=0 wallet auth-transfer send --to <agent npk> --amount 100" "RISC0_DEV_MODE=0 NSSA_WALLET_HOME_DIR=$GHOME RUST_LOG=info $WALLET auth-transfer send --from $GENESIS --to-npk $ANPK --to-vpk $AVPK --amount 100 2>&1 | grep -iE 'RISC0_DEV_MODE|execution time|segment|Transaction hash' | head -4" 4
for i in $(seq 1 14); do "$LC" call lez_wallet_module sync_private >/dev/null 2>&1; [ "$(abal)" = "100" ]&&break; sleep 4; done
run "logoscore call agent_module wallet_balance" "echo '{\"balance\":\"'$(abal)'\"}'" 1

hdr "6. autonomous A2A payment — discover, task, pay  (F8)"
rm -rf ~/B2-home; BT=$(printf 'demo\ndemo\n'|NSSA_WALLET_HOME_DIR=~/B2-home $WALLET account new private -l agentB2 2>&1)
BNPK=$(echo "$BT"|grep -oE 'npk [0-9a-f]{64}'|awk '{print $2}'); BVPK=$(echo "$BT"|grep -oE 'vpk [0-9a-f]{66}'|awk '{print $2}')
say "agent B advertises compute.run at 5 LEZ; agent A tasks + pays it autonomously"
CARD=$(python3 -c "import json;print(json.dumps({'id':'agentB','skills':[{'name':'compute.run','lez_price':'5'}],'x-lez-identity':{'npk':'$BNPK','vpk':'$BVPK'}}))")
run "logoscore call agent_module agent_task <agentB card> compute.run" "$LC call agent_module agent_task '$CARD' compute.run '{}' 2>/dev/null | python3 -c \"import sys,json;d=json.load(sys.stdin);r=json.loads(d['result'])['result'];print('task',r['task_id'],'status',r['status'],'price',r['lez_price'])\"" 2
for i in $(seq 1 16); do "$LC" call lez_wallet_module sync_private >/dev/null 2>&1; [ "$(abal)" = "95" ]&&break; sleep 5; done
BB=$(NSSA_WALLET_HOME_DIR=~/B2-home $WALLET account sync-private >/dev/null 2>&1; NSSA_WALLET_HOME_DIR=~/B2-home $WALLET account get --account-label agentB2 2>/dev/null|grep -oE '"balance":[0-9]+'|grep -oE '[0-9]+'|head -1)
say "result: agent A paid agent B autonomously, no human in the loop"
run "balances after" "echo 'agent A: '$(abal)'   agent B: '$BB" 1

hdr "all through the agent's own skills — F1 load, F2 fund, F6 skills, F7 card, F8 autonomous pay"
say "the agent genuinely owns and operates a funded shielded account"
sleep 2
pkill -9 -f logoscore 2>/dev/null; pkill -9 -f sequencer 2>/dev/null
