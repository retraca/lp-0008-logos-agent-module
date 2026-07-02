#!/usr/bin/env bash
# tests/e2e.sh — TEMPLATE for a fully-scripted multi-agent e2e run.
#
# NOTE: this is a template. It requires you to fill in the account constants below
# (AGENT_MNEMONIC / RECIPIENT_ADDRESS / STORAGE_ENDPOINT). For a runnable real-proof
# demo with NO manual config, use tests/demo-real.sh. The CI integration test is
# tests/e2e-dev.sh (standalone sequencer, RISC0_DEV_MODE=1, on every push).
#
# Prerequisites (set as environment variables or export before running):
#   SEQUENCER      URL of the running LEZ standalone sequencer (JSON-RPC)
#                  Default: http://127.0.0.1:3040
#   MODULES_DIR    Directory containing the built agent_module .so + metadata.json
#                  Default: ./result-agent
#   LOGOSCORE_BIN  Path to the logoscore CLI binary
#                  Default: logoscore (must be on PATH)
#   RISC0_DEV_MODE Must be "0" for the real-proof run required by the spec.
#                  Set to "1" only for fast local iteration (skip proofs).
#
# TODO (runtime milestone): fill in the funded-account constants below once
# the lez_wallet_module is built and a dev-net account is seeded.
#
# Usage:
#   RISC0_DEV_MODE=0 SEQUENCER=http://127.0.0.1:3040 bash tests/e2e.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
SEQUENCER="${SEQUENCER:-http://127.0.0.1:3040}"
MODULES_DIR="${MODULES_DIR:-./result-agent}"
LOGOSCORE_BIN="${LOGOSCORE_BIN:-logoscore}"
RISC0_DEV_MODE="${RISC0_DEV_MODE:-0}"

export RISC0_DEV_MODE

# ---------------------------------------------------------------------------
# TODO (runtime milestone): replace these placeholders with real values once
# the lez_wallet_module is built and a funded test account exists on the
# standalone sequencer (seeded via sequencer_config.json initial_accounts).
# ---------------------------------------------------------------------------
# The agent's shielded account mnemonic (BIP39, 24 words).
AGENT_MNEMONIC="${AGENT_MNEMONIC:-TODO_FILL_IN_AGENT_MNEMONIC}"
# A second account address to test messaging_send and wallet transfers.
RECIPIENT_ADDRESS="${RECIPIENT_ADDRESS:-TODO_FILL_IN_RECIPIENT_ADDRESS}"
# A storage endpoint reachable from the sequencer node (IPFS-compat CID gateway).
STORAGE_ENDPOINT="${STORAGE_ENDPOINT:-TODO_FILL_IN_STORAGE_ENDPOINT}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[e2e] $*"; }

# Call logoscore to invoke a skill and capture the JSON result.
# Usage: logos_call <module_name> <skill_call_expression>
logos_call() {
    local mod="$1"
    local expr="$2"
    "${LOGOSCORE_BIN}" \
        -m "${MODULES_DIR}" \
        -s "${SEQUENCER}" \
        -l "${mod}" \
        -c "${expr}" \
        --quit-on-finish \
        --json-output
}

# Assert that a JSON string does not contain an "error" key at the top level.
assert_no_error() {
    local label="$1"
    local json="$2"
    if echo "${json}" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'error' not in d else 1)" 2>/dev/null; then
        log "PASS: ${label}"
    else
        log "FAIL: ${label} — response contained error field"
        echo "  Response: ${json}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
log "=== LP-0008 e2e demo (RISC0_DEV_MODE=${RISC0_DEV_MODE}) ==="
log "Sequencer: ${SEQUENCER}"
log "Modules:   ${MODULES_DIR}"
log "logoscore: ${LOGOSCORE_BIN}"

# Verify sequencer is up
log "Checking sequencer health ..."
health=$(curl -sf -m 10 -X POST "${SEQUENCER}" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"checkHealth","params":[],"id":1}')
echo "  Health response: ${health}"

# Verify the modules directory has the expected plugin
if ! ls "${MODULES_DIR}" | grep -q 'agent_module_plugin\|libagent_module_plugin'; then
    log "ERROR: agent_module plugin not found in ${MODULES_DIR}"
    log "Build it first: cd scaffold && nix build .#lib --out-link ../result-agent"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Configure spending limits via meta_configure
# ---------------------------------------------------------------------------
log "--- Step 1: meta.configure (spending limits) ---"
# TODO (runtime milestone): adjust per_tx_limit / per_period_limit to match
# the seeded account balance so below-threshold tests pass without approval.
configure_result=$(logos_call "agent_module" \
    'meta.configure("per_tx_limit","10000"); meta.configure("per_period_limit","100000"); meta.configure("period_seconds","86400")')
log "configure result: ${configure_result}"
assert_no_error "meta.configure (spending limits)" "${configure_result}"

# ---------------------------------------------------------------------------
# Step 2: Skill category — Blockchain: wallet_balance
# ---------------------------------------------------------------------------
log "--- Step 2: wallet.balance ---"
# TODO (runtime milestone): this step requires the lez_wallet_module to be
# built (built via nix) and loaded alongside agent_module. The
# agent_module's wallet.balance skill delegates to lez_wallet_module via
# the LogosAPI interface binding.
balance_result=$(logos_call "agent_module" 'wallet.balance()')
log "wallet.balance result: ${balance_result}"
assert_no_error "wallet.balance" "${balance_result}"

# ---------------------------------------------------------------------------
# Step 3: Skill category — Storage: storage_upload
# ---------------------------------------------------------------------------
log "--- Step 3: storage.upload ---"
# Create a small test file to upload.
TEST_FILE="/tmp/lp0008-e2e-test-$(date +%s).txt"
echo "LP-0008 agent_module e2e test payload — $(date --iso-8601=seconds)" > "${TEST_FILE}"

# TODO (runtime milestone): storage_upload delegates to the storage_module
# backend which requires a running Logos storage node or IPFS gateway
# (STORAGE_ENDPOINT above). Update the endpoint and any auth headers needed.
upload_result=$(logos_call "agent_module" \
    "storage.upload(\"${TEST_FILE}\", \"e2e-test-file\")")
log "storage.upload result: ${upload_result}"
assert_no_error "storage.upload" "${upload_result}"

# Extract the CID from the upload result for the download step.
# TODO (runtime milestone): adjust the jq/python path to match the actual
# response schema once the skill implementation is finalized.
UPLOADED_CID=$(echo "${upload_result}" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('cid','TODO_CID'))" 2>/dev/null \
    || echo "TODO_CID")
log "Uploaded CID: ${UPLOADED_CID}"

# ---------------------------------------------------------------------------
# Step 4: Skill category — Messaging: messaging_send
# ---------------------------------------------------------------------------
log "--- Step 4: messaging.send ---"
# TODO (runtime milestone): messaging.send requires a running Logos Core
# daemon with the chat_module and delivery_module loaded. RECIPIENT_ADDRESS
# must be set to a valid Logos chat identity (introBundle or address) that
# exists on the local sequencer/testnet.
#
# The call below will reach the spending-gate check first; since the
# message itself has no LEZ cost, it should auto-execute below threshold.
send_result=$(logos_call "agent_module" \
    "messaging.send(\"${RECIPIENT_ADDRESS}\", \"LP-0008 e2e test message from agent\")")
log "messaging.send result: ${send_result}"
assert_no_error "messaging.send" "${send_result}"

# ---------------------------------------------------------------------------
# Step 5: meta.status — verify overall agent state
# ---------------------------------------------------------------------------
log "--- Step 5: meta.status ---"
status_result=$(logos_call "agent_module" 'meta.status()')
log "meta.status result: ${status_result}"
assert_no_error "meta.status" "${status_result}"

# ---------------------------------------------------------------------------
# All assertions passed
# ---------------------------------------------------------------------------
log "=== All e2e assertions PASSED ==="
log ""
log "Summary of calls:"
log "  meta.configure  — spending limits set"
log "  wallet.balance  — non-error JSON returned (RISC0_DEV_MODE=${RISC0_DEV_MODE})"
log "  storage.upload  — file uploaded, CID: ${UPLOADED_CID}"
log "  messaging.send  — message dispatched to ${RECIPIENT_ADDRESS}"
log "  meta.status     — agent state readable"
