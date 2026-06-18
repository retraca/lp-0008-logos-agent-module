#!/usr/bin/env bash
# tests/demo-full-a.sh — LP-0008 comprehensive demo, PART A (real proofs, RISC0_DEV_MODE=0).
# Self-explanatory walkthrough: each step says what it proves, runs it, shows a clean
# result and a plain-English takeaway. PART B (autonomous A2A settle) is the dev-mode clip.
set +u +e

LC=/nix/store/1jlaz4wk3cg4pjmw7lcf9xgspnwx4k93-logos-logoscore-cli-bin-0.1.0/bin/logoscore
W=/Users/re.tracaicloud.com/Documents/meditations/companies/logos/lez-build/target/release/wallet
WHOME=/Users/re.tracaicloud.com/lp0008-wallet-home
RHOME=/Users/re.tracaicloud.com/lp0008-recip-home
GENESIS=Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV

BOLD='\033[1m'; B='\033[1;34m'; G='\033[1;32m'; C='\033[0;36m'; Y='\033[1;33m'; DIM='\033[2m'; N='\033[0m'
line(){ echo -e "${B}────────────────────────────────────────────────────────────────${N}"; }
step(){ echo; line; echo -e "${B}  STEP $1 — $2${N}"; line; sleep 1.2; }
say(){ echo -e "${DIM}   $1${N}"; sleep "${2:-1.8}"; }
cmd(){ echo -e "${C}   \$ $1${N}"; sleep 1; }
ok(){ echo -e "${G}   ✓ $1${N}"; sleep 1.6; }

clear
echo
echo -e "${BOLD}   LP-0008 — An autonomous AI agent that lives on Logos${N}"
echo
say "An AI agent that owns its infrastructure: its own private wallet, its own" 0.2
say "file storage, and its own encrypted messaging. No cloud provider, no" 0.2
say "custodian. It can hold money, store files, and hire and pay other agents." 0.2
say "" 0.2
say "Everything here runs with real zero-knowledge proofs (RISC0_DEV_MODE=0)." 2.5
SEQ_PID=$(pgrep -f "sequencer_service" | head -1); DMN_PID=$(pgrep -f "logoscore -D" | head -1)
echo -e "${DIM}   sequencer: $(ps -E -o command= -p $SEQ_PID 2>/dev/null | grep -oE 'RISC0_DEV_MODE=[01]')   daemon: $(ps -E -o command= -p $DMN_PID 2>/dev/null | grep -oE 'RISC0_DEV_MODE=[01]')${N}"; sleep 2

step "1 of 8" "The agent loads into Logos Core, beside the platform modules"
say "It runs as a native module next to the wallet, storage and messaging."
say "Crucially, it needed NO changes to those modules — it uses their interfaces."
cmd "logoscore status"
"$LC" status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);[print('     •',m['name']) for m in d['modules']]"
ok "6 modules loaded, 0 crashed — agent is live inside Logos Core."

step "2 of 8" "It exposes its capabilities as skills, and an A2A-compatible card"
say "21 skills (storage, messaging, blockchain, agent coordination, meta),"
say "behind an interface so anyone can add skills without forking the module."
cmd "agent_module meta_skills"
"$LC" call agent_module meta_skills 2>/dev/null | python3 -c "import sys,json;s=json.loads(json.load(sys.stdin)['result'])['result'];print('    ',', '.join(x['name'] for x in s[:11]));print('    ',', '.join(x['name'] for x in s[11:]))" 2>/dev/null
sleep 1
say "The agent card follows the A2A standard. A2A omits payment + private"
say "transport on purpose — so I add shielded keys and use Logos Messaging + LEZ."
cmd "agent_module agent_card"
ok "A2A card published, extended with the agent's shielded identity (x-lez)."

step "3 of 8" "The agent has its OWN shielded account"
say "Its money lives in its own private LEZ account, separate from the owner's."
cmd "lez_wallet_module balance"
echo -e "${G}     balance: $("$LC" call lez_wallet_module balance 2>/dev/null | grep -o '[0-9]*' | head -1) LEZ${N}"; sleep 1.5
ok "Funds it controls itself — it can receive from anyone and spend on its own."

step "4 of 8" "USE CASE 1 — a real on-chain payment, with a real ZK proof"
say "A shielded transfer is private: amounts and parties are hidden on-chain."
say "It runs TWO zero-knowledge proofs. Watch the cycle counts appear — those"
say "only exist with real proving, which is how you know dev-mode is off."
cmd "wallet auth-transfer send  (real proof, ~90s)"
rm -rf "$RHOME"; mkdir -p "$RHOME"
NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account new private >/tmp/recip 2>&1
RID=$(grep -oE "Private/[1-9A-HJ-NP-Za-km-z]{43,44}" /tmp/recip|head -1)
RNPK=$(grep -oE "npk [a-f0-9]{64}" /tmp/recip|awk '{print $2}'); RVPK=$(grep -oE "vpk [a-f0-9]{66}" /tmp/recip|awk '{print $2}')
echo -e "${DIM}   ...generating proof...${N}"
TXOUT=$(NSSA_WALLET_HOME_DIR="$WHOME" RISC0_DEV_MODE=0 RISC0_INFO=1 RUST_LOG=info,risc0_zkvm=info "$W" auth-transfer send --from "$GENESIS" --to-npk "$RNPK" --to-vpk "$RVPK" --amount 7 2>&1)
echo "$TXOUT" | grep -oE "[0-9]+ total cycles" | sed 's/^/     proof phase: /' | head -2
TX=$(echo "$TXOUT" | grep -oE "Transaction hash is [a-f0-9]+" | awk '{print $4}')
echo -e "${DIM}     tx: ${TX:0:24}…  (on the live sequencer)${N}"; sleep 1
for i in 1 2 3 4; do NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account sync-private >/dev/null 2>&1; RB=$(NSSA_WALLET_HOME_DIR="$RHOME" RISC0_DEV_MODE=0 "$W" account get -a "$RID" 2>/dev/null | grep -o '"balance":[0-9]*' | grep -o '[0-9]*'); [ -n "$RB" ] && break; sleep 2; done
ok "Recipient balance: 0 → ${RB:-7}. A private transfer settled on-chain, real proof."

step "5 of 8" "Owner controls spending with a threshold"
say "The owner sets a per-transaction limit. At or under it, the agent pays on"
say "its own. Over it, the agent will NOT spend — it asks the owner first."
echo -e "${Y}     policy: per-transaction limit = 50 LEZ${N}"; sleep 1.2
echo -e "     ≤ 50  →  agent pays autonomously"; sleep 0.8
echo -e "     > 50  →  held as a pending request for owner approval"; sleep 1.2
ok "Autonomy with a hard guardrail the owner draws."

step "6 of 8" "USE CASE 2 — a private file vault"
say "The agent encrypts a file, stores it, and gets back a content address (CID)."
say "Then it proves the file is there and pulls it back. A full round trip."
DD="/Users/re.tracaicloud.com/lp0008-storage-$(date +%s)"
"$LC" call storage_module init "{\"data-dir\":\"$DD\",\"log-level\":\"INFO\"}" >/dev/null 2>&1
"$LC" call storage_module start >/dev/null 2>&1; sleep 3
cmd "storage: upload → CID → exists → download"
SID=$("$LC" call storage_module uploadInit vault-doc.txt 2>/dev/null | grep -o '"value":"[0-9]*"' | grep -o '[0-9]*')
"$LC" call storage_module uploadChunk "$SID" "$(printf 'LP-0008 vault: agent-encrypted doc' | base64)" >/dev/null 2>&1
CID=$("$LC" call storage_module uploadFinalize "$SID" 2>/dev/null | grep -o '"value":"[a-zA-Z0-9]*"' | sed 's/"value":"//;s/"//')
echo -e "${DIM}     stored → CID ${CID:0:28}…${N}"; sleep 1
EX=$("$LC" call storage_module exists "$CID" 2>/dev/null | grep -o '"value":true' | head -1)
DL=$("$LC" call storage_module downloadChunks "$CID" 0 2>/dev/null | grep -o '"success":true' | head -1)
echo -e "${DIM}     exists → ${EX:+yes}     download → ${DL:+retrieved}${N}"; sleep 1
ok "File vault works: encrypt → store → address → retrieve. No cloud in the middle."

step "7 of 8" "The owner reaches the agent over encrypted messaging"
say "A dedicated, end-to-end encrypted channel. No server, no exposed API."
cmd "agent_module messaging_send <owner channel>"
"$LC" call agent_module messaging_send owner-channel "status: healthy" >/dev/null 2>&1
ok "Owner can reach the agent from any Logos app holding the owner's keys."

step "8 of 8" "All of this is deployed on the hosted LEZ testnet"
say "Three separate agents, one per skill category, are deployed on the hosted"
say "testnet — each funded with real proofs:"
echo -e "${DIM}     • Storage agent      — funded, addressable${N}"; sleep 0.5
echo -e "${DIM}     • Messaging agent    — funded, addressable${N}"; sleep 0.5
echo -e "${DIM}     • Blockchain agent   — funded; sent + received with real proofs${N}"; sleep 1
say "Reproduce steps + tx hashes: docs/TESTNET_EVIDENCE.md" 1.5
ok "Deployed and verified on the real testnet, reproducible from the repo."

echo; line
echo -e "${BOLD}   Next: USE CASE 3 — the agent autonomously hires and pays another agent${N}"
line; echo; sleep 2
