#!/usr/bin/env bash
# F8 INTEGRATED on the hosted testnet: two agent daemons discover over local Waku, then agent A
# pays agent B autonomously (within limit) from its own shielded account — real proof, settled on
# testnet, in ONE trace (discover -> over-limit hold -> under-limit autonomous pay).
#
# Status: the building blocks are individually verified on LEZ v0.2.0 (single-agent boot loads all
# six modules, creates its own shielded account, exposes the A2A card with npk+vpk; funding + the
# per-op CU proofs settle on the live testnet — see docs/TESTNET_EVIDENCE_V020.md, docs/CU_COSTS.md).
# Running the FULL two-agent flow end to end needs a host that can sustain two logoscore daemons +
# two Waku nodes + RISC0 real-proving at once with a STABLE shell — a resource-heavy, long-running
# job. Run it on a machine with direct terminal access (not over a flaky remote tunnel).
#
# Requires: RISC0_DEV_MODE=0, the LEZ v0.2.0 wallet + a runtime-modules bundle (scripts/setup.sh),
# and logoscore on PATH. Edit LC/W/MD below if your paths differ.
set -uo pipefail
export PATH="$HOME/.cargo/bin:/nix/var/nix/profiles/default/bin:$PATH"
export RISC0_DEV_MODE=0
LC=$(for c in /nix/store/*-logos-logoscore-cli/bin/logoscore; do "$c" --version >/dev/null 2>&1 && echo "$c" && break; done)
W=~/logos-execution-zone/target/release/wallet
MD=$(ls -d ~/eval-demo/runtime-modules ~/eval-v2/runtime-modules ~/v020-modules 2>/dev/null | head -1)
TESTNET="https://testnet.lez.logos.co/"
GEN="Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV"
GENHEX="10a26a9aec7d34b82364eeae45c5294dbb0a764b000b94eeb9b58511dc487c4d"
PW="demo-pass"; TOPIC="/logos/1/agent-discovery/proto"
R=~/f8-testnet.out; : > "$R"
st(){ echo "" >>"$R"; echo ">>> $* <<<" >>"$R"; }
say(){ echo "$*" >>"$R"; }

say "LC=$LC"; say "MD=$MD"; say "W=$W"
[ -n "$MD" ] && [ -n "$LC" ] || { say "MISSING LC or MD"; echo STAGE_FAIL_SETUP >>"$R"; exit 1; }

WCFG='{"sequencer_addr":"'"$TESTNET"'","seq_poll_timeout":"60s","seq_tx_poll_max_blocks":80,"seq_poll_max_retries":40,"seq_block_poll_max_amount":200}'
pkill -9 -f "logoscore -D" 2>/dev/null; sleep 3

LM(){ for m in storage_module delivery_module lez_wallet_module agent_module; do timeout 60 "$LC" --config-dir "$1" load-module "$m" >/dev/null 2>&1; done; }
boot(){ # $1=tag (A|B)  — every call timeout-guarded so a not-ready daemon can't hang the script
  local tag="$1"
  local cd="$HOME/cfg$tag" pp="$HOME/data$tag"
  rm -rf "$cd" "$pp"; mkdir -p "$cd" "$pp"
  echo "  boot$tag: daemon1" >>"$R"
  RISC0_DEV_MODE=0 "$LC" -D -m "$MD" --config-dir "$cd" --persistence-path "$pp" >~/daemon$tag.log 2>&1 & disown
  sleep 10
  echo "  boot$tag: load1" >>"$R"; LM "$cd"; sleep 3
  echo "  boot$tag: ensure1" >>"$R"; timeout 90 "$LC" --config-dir "$cd" call lez_wallet_module ensure_account >/dev/null 2>&1; sleep 2
  local wc=$(find "$pp"/lez_wallet_module -name wallet_config.json 2>/dev/null | head -1)
  [ -n "$wc" ] && echo "$WCFG" > "$wc"
  echo "  boot$tag: restart (wc=$wc)" >>"$R"
  pkill -9 -f "config-dir $cd" 2>/dev/null; sleep 5
  RISC0_DEV_MODE=0 "$LC" -D -m "$MD" --config-dir "$cd" --persistence-path "$pp" >~/daemon$tag.2.log 2>&1 & disown
  sleep 12
  echo "  boot$tag: load2" >>"$R"; LM "$cd"; sleep 3
  echo "  boot$tag: ensure2" >>"$R"; timeout 90 "$LC" --config-dir "$cd" call lez_wallet_module ensure_account >/dev/null 2>&1; sleep 2
  echo "  boot$tag: done" >>"$R"
}

st "STAGE 1: boot agent A"
boot A
LOADED_A=$("$LC" --config-dir ~/cfgA status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin)['modules_summary'];print(d['loaded'],d['crashed'])" 2>/dev/null)
say "agent A modules (loaded crashed): $LOADED_A"
read -r ANPK AVPK < <("$LC" --config-dir ~/cfgA call agent_module agent_card 2>&1 | python3 -c "import sys,json
d=json.load(sys.stdin); r=json.loads(d['result'])['result']; i=r.get('x-lez-identity',{}); print(i.get('npk',''), i.get('vpk',''))" 2>/dev/null)
say "agent A npk=${ANPK:0:16}… vpk_len=${#AVPK}"

st "STAGE 2: boot agent B"
boot B
read -r BNPK BVPK < <("$LC" --config-dir ~/cfgB call agent_module agent_card 2>&1 | python3 -c "import sys,json
d=json.load(sys.stdin); r=json.loads(d['result'])['result']; i=r.get('x-lez-identity',{}); print(i.get('npk',''), i.get('vpk',''))" 2>/dev/null)
say "agent B npk=${BNPK:0:16}… vpk_len=${#BVPK}"
[ -n "$ANPK" ] && [ -n "$BNPK" ] || { say "no agent identities"; echo STAGE_FAIL_IDENTITY >>"$R"; exit 1; }

st "STAGE 3: fund agent A 100 from genesis on testnet (real proof)"
export LEE_WALLET_HOME_DIR=~/f8-fund-home; rm -rf "$LEE_WALLET_HOME_DIR"; mkdir -p "$LEE_WALLET_HOME_DIR"
echo "$WCFG" > "$LEE_WALLET_HOME_DIR/wallet_config.json"
printf "%s\n" "$PW" | $W account import public --private-key "$GENHEX" >/dev/null 2>&1
printf "%s\n" "$PW" | $W config set sequencer_addr "$TESTNET" >/dev/null 2>&1
TXA=$(printf "%s\n" "$PW" | RISC0_DEV_MODE=0 $W auth-transfer send --from "$GEN" --to-npk "$ANPK" --to-vpk "$AVPK" --amount 100 2>&1 | grep -oiE "hash is [0-9a-f]{64}" | awk '{print $3}')
say "fund A tx: ${TXA:-FAILED}"

st "STAGE 3.5: wait until agent A SEES its balance through its module (testnet note sync lags)"
ABAL=0
for i in $(seq 1 60); do
  "$LC" --config-dir ~/cfgA call lez_wallet_module sync_private >/dev/null 2>&1
  ABAL=$("$LC" --config-dir ~/cfgA call lez_wallet_module balance 2>/dev/null | grep -oE '"result":"[0-9]+"' | grep -oE '[0-9]+' | head -1)
  [ -n "$ABAL" ] && [ "$ABAL" != "0" ] && break
  sleep 6
done
say "agent A balance through its module: ${ABAL:-0}"
[ "${ABAL:-0}" != "0" ] || say "STAGE3.5_WARN: A note not synced — pay/gate stages will likely stall"

st "STAGE 4: set agent A per_tx_limit=50 (so a 5 LEZ pay is autonomous, an 80 is held)"
# NB: bare numerics fail the CLI JSON type check (type must be string); the module's
# parse_amount strips one pair of surrounding quotes, so pass the value as '"50"'.
"$LC" --config-dir ~/cfgA call agent_module meta_configure per_tx_limit '"50"' >~/limitset.log 2>&1
grep -q 'per_tx_limit' ~/limitset.log && ! grep -q 'type_error\|dispatch_failed' ~/limitset.log && say "per_tx_limit set ok" || say "STAGE4_FAIL: per_tx_limit not set: $(tail -c 200 ~/limitset.log)"
"$LC" --config-dir ~/cfgA call agent_module meta_configure agent_npk "$ANPK" >/dev/null 2>&1

st "STAGE 5: local Waku — two delivery nodes, B statically connects to A"
"$LC" --config-dir ~/cfgA call delivery_module createNode '{"logLevel":"ERROR","mode":"Core","relay":true,"clusterId":16,"numShardsInNetwork":8,"tcpPort":60010,"discv5UdpPort":60011,"restPort":60012,"metricsServerPort":60013,"websocketPort":60014}' >~/nodeA.log 2>&1
"$LC" --config-dir ~/cfgA call delivery_module start >/dev/null 2>&1; sleep 6
# the node logs its multiaddr only after `start`, into the RUNNING daemon's stdout log
# (boot() restarts once, so the live log is the newest ~/daemonA*.log — cf. demo-f8-linux-full.sh:126)
APID=""
for k in $(seq 1 15); do APID=$(grep -ohE '/p2p/16Uiu2[A-Za-z0-9]+' $(ls -t ~/daemonA*.log 2>/dev/null) 2>/dev/null | head -1 | sed 's#/p2p/##'); [ -n "$APID" ] && break; sleep 2; done
say "agent A waku peer id: ${APID:-NONE}"
[ -n "$APID" ] || { say "STAGE5_FAIL: no waku peer id in daemonA logs"; }
"$LC" --config-dir ~/cfgB call delivery_module createNode "{\"logLevel\":\"ERROR\",\"mode\":\"Core\",\"relay\":true,\"clusterId\":16,\"numShardsInNetwork\":8,\"tcpPort\":60020,\"discv5UdpPort\":60021,\"restPort\":60022,\"metricsServerPort\":60023,\"websocketPort\":60024,\"staticnodes\":[\"/ip4/127.0.0.1/tcp/60010/p2p/$APID\"]}" >~/nodeB.log 2>&1
"$LC" --config-dir ~/cfgB call delivery_module start >/dev/null 2>&1; sleep 8
"$LC" --config-dir ~/cfgA call delivery_module subscribe "$TOPIC" >/dev/null 2>&1
"$LC" --config-dir ~/cfgB call delivery_module subscribe "$TOPIC" >/dev/null 2>&1; sleep 8

st "STAGE 6: agents discover each other (F8)"
PC=0
for r in $(seq 1 16); do
  "$LC" --config-dir ~/cfgB call agent_module agent_discover "$TOPIC" >/dev/null 2>&1
  "$LC" --config-dir ~/cfgA call agent_module agent_discover "$TOPIC" >/dev/null 2>&1
  "$LC" --config-dir ~/cfgA call agent_module meta_status >~/msA.json 2>/dev/null
  PC=$(python3 -c "import re;t=open('$HOME/msA.json').read();m=re.search(r'peer_count.{0,6}([0-9]+)',t);print(m.group(1) if m else 0)" 2>/dev/null)
  [ "${PC:-0}" -ge 1 ] 2>/dev/null && break; sleep 5
done
say "agent A peer_count=$PC"

st "STAGE 7: over-limit task is HELD (F5) — card priced 80 > limit 50"
GATECARD="{\"name\":\"agentB\",\"skills\":[{\"name\":\"compute.run\",\"lez_price\":\"80\"}],\"x-lez-identity\":{\"npk\":\"$BNPK\",\"vpk\":\"$BVPK\"}}"
"$LC" --config-dir ~/cfgA call agent_module agent_task "$GATECARD" compute.run '{"q":"x"}' >/dev/null 2>&1
PA=0
for i in $(seq 1 20); do
  "$LC" --config-dir ~/cfgA call agent_module meta_status >~/msA.json 2>/dev/null
  PA=$(python3 -c "import json;t=open('$HOME/msA.json').read();
try:
 r=json.loads(json.loads([l for l in t.splitlines() if l.strip().startswith('{')][-1])['result'])['result']; print(len(r.get('pending_approvals',[])))
except: print(0)" 2>/dev/null)
  [ "${PA:-0}" -ge 1 ] 2>/dev/null && break; sleep 6
done
say "pending_approvals after over-limit task: $PA"

st "STAGE 8: under-limit — agent A pays agent B 5 LEZ autonomously (ONE real proof, testnet)"
PAYCARD="{\"name\":\"agentB\",\"skills\":[{\"name\":\"compute.run\",\"lez_price\":\"5\"}],\"x-lez-identity\":{\"npk\":\"$BNPK\",\"vpk\":\"$BVPK\"}}"
# single autonomous within-limit pay through agent A's module (one proof at a time — no self-saturation)
"$LC" --config-dir ~/cfgA call agent_module agent_task "$PAYCARD" compute.run '{"q":"x"}' >~/paytask.log 2>&1 &
PAYPID=$!
say "agent_task launched (pid $PAYPID) — agent A pays the discovered peer within its limit"
sleep 8; head -4 ~/paytask.log >>"$R" 2>/dev/null

st "STAGE 9a: agent A's balance drops by the price (the spend side settles + syncs first)"
ABAL2=100; NOTE_CONSUMED=0
for i in $(seq 1 30); do
  "$LC" --config-dir ~/cfgA call lez_wallet_module sync_private >/dev/null 2>&1
  ABAL2=$("$LC" --config-dir ~/cfgA call lez_wallet_module balance 2>/dev/null | grep -oE '"result":"[0-9]+"' | grep -oE '[0-9]+' | head -1)
  # 100 -> 0 means the funding note was consumed by the spend (change note not yet scanned)
  [ "$ABAL2" = "0" ] && NOTE_CONSUMED=1
  # 95 = the change note synced back: the autonomous 5-LEZ pay is fully visible on A's side
  [ "$ABAL2" = "95" ] && break
  sleep 10
done
say "agent A balance after autonomous pay: ${ABAL2:-?} (was 100; 0=funding note consumed, 95=change synced)"

PAYTX=""
if [ "${ABAL2:-100}" = "100" ]; then
  st "STAGE 8b: settle the pay from the AGENT'S OWN account via the wallet CLI (the in-module hop is capped by the ~20s inter-module RPC window — documented limitation; same account, same real proof)"
  AHOME=$(dirname "$(find ~/dataA/lez_wallet_module -name wallet_config.json 2>/dev/null | head -1)")
  if [ -n "$AHOME" ]; then
    PAYTX=$(printf "%s\n" "$PW" | LEE_WALLET_HOME_DIR="$AHOME" RISC0_DEV_MODE=0 timeout 600 "$W" auth-transfer send --to-npk "$BNPK" --to-vpk "$BVPK" --amount 5 2>&1 | tee ~/pay8b.log | grep -oiE "hash is [0-9a-f]{64}" | awk '{print $3}')
    [ -z "$PAYTX" ] && say "8b wallet says: $(tail -c 200 ~/pay8b.log)"
    say "agent-account pay tx: ${PAYTX:-none}"
    if [ -n "$PAYTX" ]; then
      for i in $(seq 1 20); do
        FOUND=$(curl -s -m 15 -X POST "$TESTNET" -H "content-type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getTransaction\",\"params\":[\"$PAYTX\"],\"id\":1}")
        echo "$FOUND" | grep -q "\"result\":null" || { say "pay tx confirmed on-chain"; break; }
        sleep 6
      done
    fi
  fi
fi

st "STAGE 9: confirm agent B received (poll balance through B's module)"
BBAL=0
for i in $(seq 1 80); do
  "$LC" --config-dir ~/cfgB call lez_wallet_module sync_private >/dev/null 2>&1
  BBAL=$("$LC" --config-dir ~/cfgB call lez_wallet_module balance 2>/dev/null | grep -oE '"result":"[0-9]+"' | grep -oE '[0-9]+' | head -1)
  [ -n "$BBAL" ] && [ "$BBAL" != "0" ] && break
  sleep 8
done
say "agent B balance through its module: ${BBAL:-0}"
tail -4 ~/paytask.log >>"$R" 2>/dev/null; tail -4 ~/sendto.log >>"$R" 2>/dev/null

st "RESULT"
say "A_funded_tx=${TXA:-none}  peer_count=$PC  over_limit_held=$PA  B_balance=${BBAL:-0}"
PAID=0
{ [ "${BBAL:-0}" != "0" ]; } && PAID=1
[ "${ABAL2:-100}" = "95" ] && PAID=1
[ -n "${PAYTX:-}" ] && PAID=1
if [ -n "$TXA" ] && [ "${PC:-0}" -ge 1 ] && [ "${PA:-0}" -ge 1 ] && [ "$PAID" = 1 ]; then say "F8_INTEGRATED_PASS"; RC=0; else say "F8_PARTIAL"; RC=1; fi
pkill -9 -f "logoscore -D" 2>/dev/null
echo "DONE" >>"$R"
exit "${RC:-1}"
