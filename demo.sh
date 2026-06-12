#!/usr/bin/env bash
# End-to-end demo for LP-0008: Autonomous AI Agent Module
# Demonstrates: wallet creation, balance, NPK derivation, program deploy, program call.
#
# Prerequisites:
#   - lez-agent-cli built: cd lez-wallet-module/lez-agent-cli && cargo build --release --features lez-bridge
#     (requires the full lez-build workspace; see docs/DEPLOYMENT.md §4)
#   - OR: set LEZ=/path/to/your/lez binary
#
# Chain options (set SEQUENCER env var):
#   Local:   cd lez-build && DOCKER_DEFAULT_PLATFORM=linux/amd64 docker-compose up -d
#   Testnet: export SEQUENCER=https://testnet.lez.logos.co
#
# Usage:
#   ./demo.sh                            # local chain (default)
#   SEQUENCER=https://testnet.lez.logos.co ./demo.sh   # testnet

set -euo pipefail

LEZ="${LEZ:-./lez-wallet-module/lez-agent-cli/target/release/lez}"
SEQUENCER="${SEQUENCER:-http://127.0.0.1:3040}"
AGENT1_HOME="$(mktemp -d)/agent1"
AGENT2_HOME="$(mktemp -d)/agent2"
PASSPHRASE="demo-pass-$$"
PROGRAM_BINARY="${PROGRAM_BINARY:-./lez-wallet-module/lez-wallet-core/tests/fixtures/counter.bin}"

mkdir -p "$AGENT1_HOME" "$AGENT2_HOME"

echo ""
echo "=== LP-0008 End-to-End Demo ==="
echo "Sequencer: $SEQUENCER"
echo "RISC0_DEV_MODE=${RISC0_DEV_MODE:-not set -- set to 0 for real proofs}"
echo ""

# --------------------------------------------------------------------------
# 1. Create agent wallets
# --------------------------------------------------------------------------
echo "--- [1/7] Creating agent wallets ---"
ACCOUNT1=$("$LEZ" ensure-account --home "$AGENT1_HOME" --passphrase "$PASSPHRASE" --sequencer "$SEQUENCER" | python3 -c "import sys,json; print(json.load(sys.stdin)['ok'])")
echo "Agent 1 account: $ACCOUNT1"

ACCOUNT2=$("$LEZ" ensure-account --home "$AGENT2_HOME" --passphrase "$PASSPHRASE" --sequencer "$SEQUENCER" | python3 -c "import sys,json; print(json.load(sys.stdin)['ok'])")
echo "Agent 2 account: $ACCOUNT2"

# --------------------------------------------------------------------------
# 2. Get NPKs (shielded identities)
# --------------------------------------------------------------------------
echo ""
echo "--- [2/7] Fetching NPKs (shielded identities) ---"
NPK1=$("$LEZ" npk --home "$AGENT1_HOME" --passphrase "$PASSPHRASE" | python3 -c "import sys,json; print(json.load(sys.stdin)['ok'])")
NPK2=$("$LEZ" npk --home "$AGENT2_HOME" --passphrase "$PASSPHRASE" | python3 -c "import sys,json; print(json.load(sys.stdin)['ok'])")
echo "Agent 1 NPK: $NPK1"
echo "Agent 2 NPK: $NPK2"

# --------------------------------------------------------------------------
# 3. Check balances
# --------------------------------------------------------------------------
echo ""
echo "--- [3/7] Checking balances ---"
BAL1=$("$LEZ" balance --home "$AGENT1_HOME" --passphrase "$PASSPHRASE" --sequencer "$SEQUENCER" | python3 -c "import sys,json; print(json.load(sys.stdin)['ok'])")
echo "Agent 1 balance: $BAL1 LEZ"

# --------------------------------------------------------------------------
# 4. Sync private state
# --------------------------------------------------------------------------
echo ""
echo "--- [4/7] Syncing private chain state ---"
"$LEZ" sync --home "$AGENT1_HOME" --sequencer "$SEQUENCER"
echo "Sync complete"

# --------------------------------------------------------------------------
# 5. Deploy a LEZ program
# --------------------------------------------------------------------------
echo ""
echo "--- [5/7] Deploying LEZ program ---"
if [ -f "$PROGRAM_BINARY" ]; then
    PROGRAM_ID=$("$LEZ" program deploy \
        --home "$AGENT1_HOME" \
        --passphrase "$PASSPHRASE" \
        --sequencer "$SEQUENCER" \
        --binary "$PROGRAM_BINARY" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['ok'])")
    echo "Program deployed: $PROGRAM_ID"

    # --------------------------------------------------------------------------
    # 6. Call the program
    # --------------------------------------------------------------------------
    echo ""
    echo "--- [6/7] Calling LEZ program ---"
    CALL_RESULT=$("$LEZ" program call \
        --home "$AGENT1_HOME" \
        --passphrase "$PASSPHRASE" \
        --sequencer "$SEQUENCER" \
        --program-id "$PROGRAM_ID" \
        --instruction "increment" \
        --params '{"accounts":[],"instruction_words":[1]}')
    echo "Call result: $CALL_RESULT"

    # --------------------------------------------------------------------------
    # 7. Query program state
    # --------------------------------------------------------------------------
    echo ""
    echo "--- [7/7] Querying program state ---"
    QUERY_RESULT=$("$LEZ" program query \
        --sequencer "$SEQUENCER" \
        --program-id "$PROGRAM_ID" \
        --params '{}')
    echo "State: $QUERY_RESULT"
else
    echo "Skipping program deploy (binary not found at $PROGRAM_BINARY)"
    echo "--- [6/7] Skipped ---"
    echo "--- [7/7] Skipped ---"
fi

echo ""
echo "=== Demo complete ==="
echo "Agent 1 account: $ACCOUNT1  NPK: $NPK1"
echo "Agent 2 account: $ACCOUNT2  NPK: $NPK2"
echo ""
echo "Next: load both modules into logoscore and exercise the agent skill surface:"
echo "  logoscore -D \\"
echo "    -m lez-wallet-module/qt-module/liblez_wallet_module_plugin.so \\"
echo "    -m scaffold/libagent_module_plugin.so"
echo "  logoscore -c 'lez_wallet_module.ensure_account(\"$PASSPHRASE\")'"
echo "  logoscore -c 'agent_module.meta_skills()'"
echo "  logoscore -c 'agent_module.meta_configure(\"per_tx_limit\", \"10.0\")'"
echo "  logoscore -c 'agent_module.wallet_balance()'"
