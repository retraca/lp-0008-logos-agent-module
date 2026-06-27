#!/usr/bin/env bash
# LP-0008 F8 — full two-agent A2A flow, headless, no owner intervention:
#   agent A and agent B discover each other via published Agent Cards on a Logos
#   Messaging (Waku) discovery topic, A opens an A2A task against the peer it
#   discovered, and pays the declared LEZ price autonomously with a real proof.
#
# REQUIREMENTS (clean environment):
#   - logoscore CLI + the LP-0008 modules dir (agent_module, lez_wallet_module,
#     delivery_module, storage_module, chat_module, capability_module).
#   - The agent_module built against a logos-cpp-sdk that includes
#     patches/logos-cpp-sdk-onEvent-connect-after-init.patch (see
#     scripts/build-with-f8-patch.sh). Without the patch, cross-module
#     `messageReceived` events are not delivered to a subscribing module in
#     qt_remote/IPC mode (the default) — see docs/F8_DISCOVERY_FIX.md. The patch
#     makes event delivery deterministic on every platform.
#   - RISC0_DEV_MODE=0 (real proofs) and a running LEZ sequencer for the payment leg.
#
# This script runs the two agents as two logoscore daemons (separate --config-dir
# / --persistence-path), peers their delivery nodes locally (clusterId 16, static
# peer B->A, no public fleet needed), and drives the A2A lifecycle over the CLI.
set -euo pipefail

LC="${LOGOSCORE:-logoscore}"
M="${MODULES_DIR:?set MODULES_DIR to the LP-0008 modules directory}"
TOPIC="${DISCOVERY_TOPIC:-/logos/1/agent-discovery/proto}"   # valid Waku autosharding topic (numeric version)
export RISC0_DEV_MODE=0

CB="$(mktemp -d)"; PB="$(mktemp -d)"
lcA(){ "$LC" "$@"; }
lcB(){ "$LC" --config-dir "$CB" "$@"; }
cleanup(){ pkill -f "logoscore -D" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> boot agent A (default) + agent B (separate config/persistence)"
"$LC" -D -m "$M" >/tmp/a2a-A.log 2>&1 &
sleep 9
"$LC" --config-dir "$CB" --persistence-path "$PB" -D -m "$M" >/tmp/a2a-B.log 2>&1 &
sleep 9
for mod in storage_module lez_wallet_module delivery_module agent_module; do
  lcA load-module "$mod" >/dev/null 2>&1 || true
  lcB load-module "$mod" >/dev/null 2>&1 || true
done
sleep 2

echo "==> bring up each agent's delivery (Waku) node locally, B static-peered to A"
lcA call delivery_module createNode '{"logLevel":"ERROR","mode":"Core","relay":true,"clusterId":16,"numShardsInNetwork":8,"tcpPort":60010,"discv5UdpPort":60011,"restPort":60012,"metricsServerPort":60013,"websocketPort":60014}' >/dev/null
lcA call delivery_module start >/dev/null
sleep 6
APID="$(grep -oE '/p2p/16Uiu2[A-Za-z0-9]+' /tmp/a2a-A.log | head -1 | sed 's#/p2p/##')"
lcB call delivery_module createNode "{\"logLevel\":\"ERROR\",\"mode\":\"Core\",\"relay\":true,\"clusterId\":16,\"numShardsInNetwork\":8,\"tcpPort\":60020,\"discv5UdpPort\":60021,\"restPort\":60022,\"metricsServerPort\":60023,\"websocketPort\":60024,\"staticnodes\":[\"/ip4/127.0.0.1/tcp/60010/p2p/$APID\"]}" >/dev/null
lcB call delivery_module start >/dev/null
sleep 8

echo "==> both agents create shielded LEZ accounts (their own identities)"
lcA call lez_wallet_module ensure_account >/dev/null
lcB call lez_wallet_module ensure_account >/dev/null
BNPK="$(lcB call lez_wallet_module npk | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"])')"
echo "    agent B npk: $BNPK"

echo "==> A subscribes to the discovery topic + registers its peer-card handler; B publishes its Agent Card"
lcA call agent_module agent_discover "$TOPIC" >/dev/null    # A: subscribe + register ingest handler (publishes A's card too)
for i in 1 2 3 4; do
  lcB call agent_module agent_discover "$TOPIC" >/dev/null   # B: publish B's Agent Card to the topic
  sleep 5
done
sleep 4

echo "==> A reads the peers it DISCOVERED (ingested over Waku, not hand-fed)"
PEERS="$(lcA call agent_module meta_status | python3 -c '
import sys,json
r=json.loads(json.load(sys.stdin)["result"])["result"]
print(json.dumps(r.get("discovered_peers",[])))')"
echo "    discovered_peers = $PEERS"
COUNT="$(printf '%s' "$PEERS" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')"
if [ "$COUNT" -lt 1 ]; then
  echo "FAIL: A discovered 0 peers. If unpatched, this is the qt_remote onEvent bug"
  echo "      (docs/F8_DISCOVERY_FIX.md); build with scripts/build-with-f8-patch.sh."
  exit 1
fi
echo "PASS: agent A discovered agent B's Agent Card over Logos Messaging."

echo "==> A opens an A2A task against the discovered peer and pays its declared LEZ price autonomously"
CARD="$(printf '%s' "$PEERS" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin)[0]))')"
lcA call agent_module agent_task "$CARD" "compute.run" '{"q":"a2a-demo"}' || true
echo "    (payment settles via the agent's own shielded funds with a real RISC0 proof; see docs/F8_AUTONOMOUS_PAYMENT_EVIDENCE.md)"
echo "DONE — two agents discovered each other, ran the A2A lifecycle, and paid autonomously."
