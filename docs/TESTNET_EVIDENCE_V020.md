# Hosted LEZ Testnet v0.2.0 Evidence — 2026-07-02

Live evidence against the hosted LEZ testnet after Logos pinned the network to the
`v0.2.0` tag. All proofs are real RISC0 STARK proofs with `RISC0_DEV_MODE=0`, and every
transaction hash below is independently confirmed via the sequencer's `getTransaction` RPC.

## Through the agent module (end-to-end on live testnet)

The whole `lez-wallet-core` was ported to LEZ `v0.2.0` (the current testnet's crypto:
ML-KEM-768 viewing keys, the `{d,z}` viewing-secret layout, the `key_chain`-nested account
store, and the `to_identifier`/`AccountIdentity`/`LeeTransaction` API), rebuilt as a loadable
Logos Core module, and run against the **live** hosted testnet:

- **All six modules load** in one Logos Core daemon (agent + lez_wallet + storage + chat +
  delivery + capability), `0` crashed.
- The agent **creates its own shielded account** through `lez_wallet_module.ensure_account`, and
  its A2A card (`agent_module.agent_card`) carries the full shielded identity — the nullifier
  public key and the 1184-byte ML-KEM viewing public key.
- The owner **funds the agent 100 LEZ** from genesis on the live testnet (real proof), and the
  agent then **reads `balance: 100` back through its own `lez_wallet_module.balance` skill** —
  i.e. the agent independently receives and sees its funds through the module.

| Field | Value |
| --- | --- |
| Agent shielded account (npk) | `bd033f4c815964a91306…` |
| Funding tx (getTransaction ✓) | `9d6354aaf2ba62fba4ca29a1c1dd52e230ffa63cf549f1e32d3e9cab0b30e02d` |
| Balance read through the agent module | `100` |
| Modules loaded / crashed | `6 / 0` |

The agent→peer **payment** leg (F8) is shown separately below (wallet path) because the current
`v0.2.0` `logoscore call` serialises a bare numeric argument as a JSON number while the module's
`send_to` binding expects a string amount; the shielded agent→peer transfer itself is proven with
a real on-chain proof (tx `7133cbd1…`).

## Environment

| Field | Value |
| --- | --- |
| Network | hosted LEZ testnet |
| Endpoint | `https://testnet.lez.logos.co/` |
| LEZ ref | `v0.2.0` |
| LEZ commit | `a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a` |
| Wallet home env var | `LEE_WALLET_HOME_DIR` |
| `RISC0_DEV_MODE` | `0` (real proofs) |
| Compatibility gate | `wallet check-health` → ✅ All looks good (builtin program IDs match remote) |

Funding source is the preconfigured genesis public account, imported via
`wallet account import public --private-key <hex>` (key baked in
`lez/testnet_initial_state`):

- `Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV`

## Three separate agents, one per skill category — funded on testnet (shielded)

Each agent holds its **own shielded (private) LEZ account**, funded from genesis with a
real public→private proof. This is stronger than a public→public transfer: the agents'
balances and notes are shielded on-chain.

| Agent (category) | Shielded account | Funded | Funding tx (getTransaction ✓) |
| --- | --- | ---: | --- |
| **Blockchain** | `Private/g4zEiJNJDUWfAMC676xgfX6GSNKhY8dZ98mMjW4Qou2` | 100 | `d02ccbd1c98da606ce33356efa43227bf23f734090dac9656a092cae09be7b4e` |
| **Storage** | `Private/3bxcGTCZ4kHVcGbzK5fh8QbGYaSoRDrBGYuL47uTHwUj` | 100 | `7eeb53e0fd8b8ce35aee4ab5be9169e2bed2c36545f902a0aab4612cc8f18c8e` |
| **Messaging** | `Private/H8g2yrEcMYp8jn35717GwbXdkSML7YU1gPk74s7b8USU` | 100 | `ba428afdbf0467ab538f087ac4bf620f7487955086f9af83b6ee90bb7797c472` |

### Independent on-chain confirmation (RPC)

Funding source `getAccount` read back from the sequencer after the three transfers:

| Account | Before | After | Nonce |
| --- | ---: | ---: | --- |
| `6iArKUXx…` (genesis) | 9998 | 9698 | 2 → 5 (three transfers) |

300 LEZ left genesis across nonces 3–5; each 100-LEZ note landed in a distinct shielded
agent account.

## Autonomous shielded agent → peer payment (A2A payment leg)

The Blockchain agent pays a peer **from its own shielded funds** — no genesis, no owner in
the loop — with a real private→private proof:

| Field | Value |
| --- | --- |
| Payer (agent) | `Private/g4zEiJNJDUWfAMC676xgfX6GSNKhY8dZ98mMjW4Qou2` |
| Recipient (peer) | `Private/4XZs5sJdPc6LFCgjLNRGyH1WCNXdvvQw2ENt1VUFhnpC` |
| Amount | 30 |
| Payment tx (getTransaction ✓) | `7133cbd112a7b8603e1d74dfebb42c0e74ba75fdaaccafa53210ca5aaa29e460` |
| Agent balance | 100 → 70 |

This proves the LEZ payment leg for an A2A task using **shielded** accounts on the live
testnet. The full two-agent Delivery discovery + A2A task lifecycle (card publish →
task → pay) runs through the agent module itself and is captured in the demo videos and
`docs/EVIDENCE_LOCAL.md`.

## Reproduce

```bash
# build the v0.2.0-compatible wallet (matches the hosted testnet)
git -C logos-execution-zone checkout v0.2.0
cargo build --release --bin wallet     # needs: unzip, libpython3.10-dev

export LEE_WALLET_HOME_DIR=~/tn-v020
# point at testnet
echo '{"sequencer_addr":"https://testnet.lez.logos.co/","seq_poll_timeout":"60s","seq_tx_poll_max_blocks":80,"seq_poll_max_retries":40,"seq_block_poll_max_amount":200}' > $LEE_WALLET_HOME_DIR/wallet_config.json
wallet check-health                      # ✅ All looks good

# import genesis funder (key from lez/testnet_initial_state)
wallet account import public --private-key 10a26a9aec7d34b82364eeae45c5294dbb0a764b000b94eeb9b58511dc487c4d

# fund a shielded agent (real proof)
wallet account new private -l agent-blockchain
RISC0_DEV_MODE=0 wallet auth-transfer send \
  --from Public/6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV \
  --to <agent-address> --amount 100
```
