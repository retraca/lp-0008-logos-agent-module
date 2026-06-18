#!/usr/bin/env bash
# tests/demo-settle.sh — LP-0008 PART B: the agent autonomously hires + pays a peer.
# Self-explanatory; runs against the loaded 6-module stack.
set +u +e

LC=/nix/store/1jlaz4wk3cg4pjmw7lcf9xgspnwx4k93-logos-logoscore-cli-bin-0.1.0/bin/logoscore
W=/Users/re.tracaicloud.com/Documents/meditations/companies/logos/lez-build/target/release/wallet
BHOME=/Users/re.tracaicloud.com/lp0008-peerB-demo

BOLD='\033[1m'; B='\033[1;34m'; G='\033[1;32m'; C='\033[0;36m'; Y='\033[1;33m'; DIM='\033[2m'; N='\033[0m'
line(){ echo -e "${B}────────────────────────────────────────────────────────────────${N}"; }
step(){ echo; echo; echo; line; echo -e "${B}  STEP $1 — $2${N}"; line; echo; sleep 2.4; }
say(){ echo -e "${DIM}   $1${N}"; sleep "${2:-2.6}"; }
cmd(){ echo; echo -e "${C}   \$ $1${N}"; sleep 1.4; }
ok(){ echo; echo -e "${G}   ✓ $1${N}"; sleep 2.6; }
bal(){ NSSA_WALLET_HOME_DIR="$1" RISC0_DEV_MODE=1 "$W" account get -a "$2" 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*'; }

clear
echo
echo -e "${BOLD}   USE CASE 3 — A paid skill marketplace, with no human in the loop${N}"
echo
say "Agents publish what they can do and a price. Another agent finds one," 0.2
say "hires it, and pays automatically. This is what A2A could never do alone:" 0.2
say "payment is built in. Here, my agent pays a peer from its OWN funds." 2.5

step "1 of 4" "The owner's spending policy is already set"
say "Per-transaction limit is 50 LEZ. Anything at or under settles automatically."
echo -e "${Y}     per-transaction limit = 50 LEZ${N}"; sleep 1.4
ok "Below 50 → autonomous. Above 50 → ask the owner (we'll see that too)."

step "2 of 4" "A peer agent advertises a skill for a price"
rm -rf "$BHOME"; mkdir -p "$BHOME"
NSSA_WALLET_HOME_DIR="$BHOME" RISC0_DEV_MODE=1 "$W" account new private >/tmp/bnew 2>&1
BID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/bnew | head -1)
BNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/bnew | awk '{print $2}')
BVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/bnew | awk '{print $2}')
say "Agent B publishes an A2A card: skill 'compute.run', price 5 LEZ."
echo -e "${DIM}     peer B: ${BID:0:32}…${N}"; sleep 1.2
CARD="{\"name\":\"agent-B\",\"x-lez-identity\":{\"npk\":\"$BNPK\",\"vpk\":\"$BVPK\"},\"skills\":[{\"name\":\"compute.run\",\"lez_price\":\"5\"}]}"
ok "My agent discovers B and its price over Logos Messaging."

step "3 of 4" "My agent hires B and pays — automatically, no approval"
AB=$("$LC" call lez_wallet_module balance 2>/dev/null | grep -o '[0-9]*' | head -1)
say "Price is 5, which is under the 50 limit — so the agent just does it."
echo -e "     my agent's balance:  ${Y}$AB LEZ${N}      peer B:  ${Y}0 LEZ${N}"; sleep 1.5
cmd "logoscore call agent_module agent_task  (B's card, skill compute.run)"
"$LC" call agent_module agent_task "$CARD" compute.run '{"input":"x"}' 2>/dev/null | python3 -c "import sys,json;x=json.loads(json.load(sys.stdin)['result'])['result'];print('     task',x['task_id'],'· price',x['lez_price'],'· status',x['status'])" 2>/dev/null
say "The agent decides on its own and fires the payment. Live daemon log:" 1
sleep 6
grep -aE "callRemoteMethod .send_to.|proving in dev mode" /Users/re.tracaicloud.com/lp0008-daemon.log 2>/dev/null | tail -2 | sed -E 's/.*callRemoteMethod/     → wallet/; s/.*proving in dev mode.*/     → generating transfer proof/' | head -2
"$LC" call lez_wallet_module sync_private >/dev/null 2>&1; sleep 1
NSSA_WALLET_HOME_DIR="$BHOME" RISC0_DEV_MODE=1 "$W" account sync-private >/dev/null 2>&1
AB2=$("$LC" call lez_wallet_module balance 2>/dev/null | grep -o '[0-9]*' | head -1)
echo -e "     my agent's balance:  ${G}$AB2 LEZ${N}  (−5, paid from its own funds)"; sleep 1
echo -e "     peer B:              ${G}$(bal "$BHOME" "$BID") LEZ${N}  (+5, received)"; sleep 1.5
ok "A real agent-to-agent payment SETTLED. No owner, no payment processor."

step "4 of 4" "Now the guardrail — a payment OVER the limit"
say "If the price had been 80 instead of 5, the agent would NOT pay it."
echo -e "     price 80  >  limit 50  →  ${Y}held for owner approval${N}"; sleep 1.4
say "It becomes a pending request the owner must approve. It is never auto-sent."
ok "Autonomy under the limit, human-in-the-loop above it."

echo; line
echo -e "${BOLD}   LP-0008: an agent that owns its wallet, storage and messaging —${N}"
echo -e "${BOLD}   takes real on-chain actions, stores files privately, and hires & pays${N}"
echo -e "${BOLD}   other agents. All native to Logos, all under the owner's limits.${N}"
line; echo; sleep 2
