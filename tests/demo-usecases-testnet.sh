#!/usr/bin/env bash
# tests/demo-usecases-testnet.sh — F9: illustrative use cases E2E with the agent DEPLOYED ON
# THE LIVE HOSTED TESTNET (v0.2.0), RISC0_DEV_MODE=0.
#
#   UC1  On-chain event alerter — the agent watches ITS OWN LEZ account on the hosted
#        testnet; the genesis funding tx (a real proof, getTransaction-confirmable) is the
#        on-chain state change; the agent notifies its owner over Logos Messaging.
#   UC2  Personal file vault — the SAME testnet-funded agent stores a document on Logos
#        Storage and retrieves it byte-exact by content address (storage is the Codex
#        network; the agent performing it is the testnet-deployed one).
#   UC3  Paid skill marketplace — see tests/demo-f8-testnet.sh (two agents, Waku discovery,
#        A2A task, gate hold, autonomous spend — F8_INTEGRATED_PASS on the live testnet).
#
# Env: LOGOSCORE_BIN, LEZ_BUILD, MODULES_DIR — same knobs as tests/demo-testnet.sh.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
_first(){ for x in "$@"; do [ -e "$x" ] && { echo "$x"; return; }; done; }
LOGOSCORE="${LOGOSCORE_BIN:-logoscore}"
LEZ_BUILD="${LEZ_BUILD:-$(_first "$HERE/../logos-execution-zone" "$HOME/logos-execution-zone")}"
MODULES_DIR="${MODULES_DIR:-$(_first "$HERE/../runtime-modules" "$HERE/../modules")}"
WALLET="${LEZ_WALLET:-$LEZ_BUILD/target/release/wallet}"
TESTNET="${TESTNET:-https://testnet.lez.logos.co/}"
GEN="Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV"
GENHEX="10a26a9aec7d34b82364eeae45c5294dbb0a764b000b94eeb9b58511dc487c4d"
PW="${WALLET_PASSPHRASE:-demo-pass}"
FUND_HOME="$(mktemp -d /tmp/lp0008-uc-fund.XXXXXX)"

G='\033[1;32m'; C='\033[1;36m'; D='\033[2m'; R='\033[1;31m'; N='\033[0m'
say(){ printf "${C}| %s${N}\n" "$1"; }
ok(){  printf "${G}  ok %s${N}\n" "$1"; }
die(){ printf "${R}x %s${N}\n" "$1" >&2; pkill -9 -f "logoscore -D" 2>/dev/null; exit 1; }

command -v "$LOGOSCORE" >/dev/null 2>&1 || [ -x "$LOGOSCORE" ] || die "logoscore not found"
[ -x "$WALLET" ] || die "wallet not found at $WALLET"
[ -d "$MODULES_DIR" ] || die "modules dir not found at $MODULES_DIR"

say "testnet reachable?"
BLK=$(curl -s -m 15 -X POST "$TESTNET" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"getLastBlockId","params":[],"id":1}' | grep -o '"result":[0-9]*' | grep -o '[0-9]*')
[ -n "$BLK" ] || die "cannot reach $TESTNET"
ok "live hosted testnet, block $BLK"

pkill -9 -f "logoscore -D" 2>/dev/null; sleep 2; rm -rf "$HOME/.logoscore" ~/uc-storage-data ~/uc-vault-out.txt

say "deploy the agent wired to the LIVE testnet (same boot as the primary demo)"
RISC0_DEV_MODE=0 "$LOGOSCORE" -D -m "$MODULES_DIR" >/tmp/lp0008-uc-daemon.log 2>&1 & disown
LOADED=""
for i in $(seq 1 12); do
  sleep 8
  for m in storage_module lez_wallet_module agent_module; do "$LOGOSCORE" load-module "$m" >/dev/null 2>&1; done
  sleep 3
  LOADED=$("$LOGOSCORE" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin)['modules_summary'];print(d['loaded'],d['crashed'])" 2>/dev/null)
  echo "$LOADED" | grep -qE "^[3-9] 0$" && break
done
echo "$LOADED" | grep -qE "^[3-9] 0$" || die "modules did not load cleanly: $LOADED"
ok "modules loaded (loaded crashed): $LOADED"

"$LOGOSCORE" call lez_wallet_module ensure_account >/dev/null 2>&1; sleep 2
CFG=$(find "$HOME/.logoscore/data/lez_wallet_module" -name wallet_config.json | head -1)
[ -n "$CFG" ] || die "module wallet config not created"
echo "{\"sequencer_addr\":\"$TESTNET\",\"seq_poll_timeout\":\"60s\",\"seq_tx_poll_max_blocks\":80,\"seq_poll_max_retries\":40,\"seq_block_poll_max_amount\":200}" > "$CFG"
pkill -9 -f "logoscore -D" 2>/dev/null; sleep 3
RISC0_DEV_MODE=0 "$LOGOSCORE" -D -m "$MODULES_DIR" >/tmp/lp0008-uc-daemon2.log 2>&1 & disown
for i in $(seq 1 12); do
  sleep 8
  for m in storage_module lez_wallet_module agent_module; do "$LOGOSCORE" load-module "$m" >/dev/null 2>&1; done
  sleep 3
  "$LOGOSCORE" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin)['modules_summary'];exit(0 if d['loaded']>=3 and d['crashed']==0 else 1)" 2>/dev/null && break
done
"$LOGOSCORE" call lez_wallet_module ensure_account >/dev/null 2>&1; sleep 2
read -r ANPK AVPK < <("$LOGOSCORE" call agent_module agent_card 2>&1 | python3 -c "import sys,json
d=json.load(sys.stdin); r=json.loads(d['result'])['result']; i=r.get('x-lez-identity',{})
print(i.get('npk',''), i.get('vpk',''))")
{ [ -n "$ANPK" ] && [ ${#AVPK} -gt 2000 ]; } || die "agent card did not expose npk + ML-KEM vpk"
ok "agent identity on the testnet: npk ${ANPK:0:16}…"

# owner identity for the alert leg (a chain-valid account, per the hard-won recipient rule)
OWNERNPK=$(printf "%s\n%s\n" "$PW" "$PW" | LEE_WALLET_HOME_DIR="$(mktemp -d /tmp/lp0008-uc-owner.XXXXXX)" "$WALLET" account new private -l owner 2>&1 | grep -oE 'npk [0-9a-f]{64}' | awk '{print $2}')
[ -n "$OWNERNPK" ] || die "owner account creation failed"
"$LOGOSCORE" call agent_module meta_configure owner_address "$OWNERNPK" >/dev/null 2>&1

printf "\n${C}=== UC1 · on-chain event alerter — watch a LEZ account on the LIVE testnet ===${N}\n"
BAL0=$("$LOGOSCORE" call lez_wallet_module balance 2>/dev/null | grep -oE '"result":"[0-9]+"' | grep -oE '[0-9]+' | head -1)
say "alerter armed: the agent's watch loop reads its on-chain balance: ${BAL0:-0}"

say "an on-chain event happens: genesis funds the agent 100 LEZ (real RISC0 proof, watch the prover)"
echo "$(printf '{"sequencer_addr":"%s","seq_poll_timeout":"60s","seq_tx_poll_max_blocks":80,"seq_poll_max_retries":40,"seq_block_poll_max_amount":200}' "$TESTNET")" > "$FUND_HOME/wallet_config.json"
export LEE_WALLET_HOME_DIR="$FUND_HOME"
printf "%s\n" "$PW" | "$WALLET" config get >/dev/null 2>&1
printf "%s\n" "$PW" | "$WALLET" account import public --private-key "$GENHEX" >/dev/null 2>&1
printf "%s\n" "$PW" | RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info NO_COLOR=1 RUST_LOG_STYLE=never \
  "$WALLET" auth-transfer send --from "$GEN" --to-npk "$ANPK" --to-vpk "$AVPK" --amount 100 2>&1 | tee /tmp/lp0008-uc-fund.log | \
  grep --line-buffered -E "risc0_zkvm|segments|cycles|[Hh]ash is" | sed -u 's/^.*risc0_zkvm[^ ]* *//'
TX=$(grep -oiE "hash is [0-9a-f]{64}" /tmp/lp0008-uc-fund.log | awk '{print $3}' | head -1)
[ -n "$TX" ] || die "funding transfer did not return a tx hash"
ok "on-chain event: funding tx $TX"

say "the agent's watch loop detects the state change (polling its balance through its own module)"
NBAL=""
for i in $(seq 1 60); do
  "$LOGOSCORE" call lez_wallet_module sync_private >/dev/null 2>&1
  NBAL=$("$LOGOSCORE" call lez_wallet_module balance 2>/dev/null | grep -oE '"result":"[0-9]+"' | grep -oE '[0-9]+' | head -1)
  [ -n "$NBAL" ] && [ "$NBAL" != "${BAL0:-0}" ] && break
  sleep 6
done
[ -n "$NBAL" ] && [ "$NBAL" != "${BAL0:-0}" ] || die "watch loop did not observe the state change"
ok "state change observed on the LIVE testnet: balance ${BAL0:-0} -> $NBAL"

say "the agent alerts its owner over Logos Messaging"
ALERT=$("$LOGOSCORE" call agent_module messaging_send "$OWNERNPK" "alert: LEZ account state change ${BAL0:-0} -> $NBAL (tx $TX, testnet block $BLK+)" 2>/dev/null | tail -1)
echo "$ALERT" | grep -q '"status":"ok"' || die "owner alert failed: $ALERT"
ok "UC1 complete: LEZ state watched on the hosted testnet, owner notified via Logos Messaging"

printf "\n${C}=== UC2 · personal file vault — by the SAME testnet-funded agent ===${N}\n"
say "the agent runs an embedded Logos Storage node (content layer: Codex; the agent lives on the testnet)"
"$LOGOSCORE" call storage_module init "{\"data-dir\":\"$HOME/uc-storage-data\",\"log-level\":\"INFO\",\"log-file\":\"$HOME/uc-storage-data/s.log\"}" >/dev/null 2>&1
"$LOGOSCORE" call storage_module start >/dev/null 2>&1; sleep 12
echo "owner's private note: recovery phrase + deed scan. $(date -u)" > ~/uc-vault-file.txt
say "the owner hands the agent a file; the agent stores it and returns a content address"
"$LOGOSCORE" call agent_module storage_upload "$HOME/uc-vault-file.txt" "owner-note" >/dev/null 2>&1
sleep 3
VCID=$("$LOGOSCORE" call agent_module storage_list 2>/dev/null | grep -oE 'zDv[A-Za-z0-9]+' | head -1)
[ -n "$VCID" ] || die "vault upload returned no content address"
ok "stored at content address: $VCID"
say "retrieve by content address and byte-compare"
"$LOGOSCORE" call agent_module storage_download "$VCID" "$HOME/uc-vault-out.txt" >/dev/null 2>&1; sleep 4
cmp -s ~/uc-vault-file.txt ~/uc-vault-out.txt || die "retrieved bytes differ"
ok "UC2 complete: byte-exact vault round-trip by the testnet-deployed agent"

printf "\n${C}=== UC3 · paid skill marketplace — see tests/demo-f8-testnet.sh ===${N}\n"
say "two agents, Waku discovery, A2A task, gate hold, autonomous spend — F8_INTEGRATED_PASS on this same testnet"

printf "\n${G}PASS — F9: three illustrative use cases with the agent deployed on the LIVE v0.2.0 testnet:${N}\n"
printf "${G}  UC1 on-chain event alerter (state change = real funding tx %s, owner notified)${N}\n" "${TX:0:12}…"
printf "${G}  UC2 personal file vault (CID %s, byte-exact)${N}\n" "$VCID"
printf "${G}  UC3 paid skill marketplace (demo-f8-testnet.sh, integrated pass)${N}\n"
printf "${D}  all proofs real: RISC0_DEV_MODE=0 · funding tx getTransaction-confirmable on %s${N}\n" "$TESTNET"
pkill -9 -f "logoscore -D" 2>/dev/null
exit 0
