# LP-0008 — F10 local evidence: three separate agent deployments (one per category)

F10 asks for three separate agents deployed, one per default skill category (Storage,
Messaging, Blockchain), each with a reproducible deployment and evidence. The maintainers
relaxed this ("any way this is demonstrated and testable for us is fine"). Below are three
independent agent deployments on a local LEZ stack, each a distinct Logos Core daemon
(separate `--config-dir`, `--persistence-path`, and ports), each exercising its category.

Captured live on the build VM (RISC0_DEV_MODE=0):

```
## Agent 1 — Storage category
  npk=…  action=storage_upload  cid=zDvZRwzkzvFKEjpwSGufsFQHBgSRNeRKyB5kKF1LredeCYVXm7t7
## Agent 2 — Messaging category
  npk=…  action=publish+discover Agent Card over Logos Messaging
## Agent 3 — Blockchain category
  npk=4c538adfac0519ed841c57ae…  action=on-chain LEZ funding  tx=c6db63d77d4584d72a1bc010…
F10_DONE
```

## Reproducible deployment (per agent)

Each agent is deployed with the single-command CLI:

```
agent up --modules-dir ./modules --sequencer http://127.0.0.1:3040 \
         --owner <owner-npk> --per-tx-limit 50 --per-period-limit 200 --detach
```

- **Agent 1 (Storage):** loads storage_module, starts an embedded Logos Storage node, and
  uploads a file -> returns a real Codex content address (CID above). See the storage
  use-case video `docs/lp0008-uc-storage.mp4`.
- **Agent 2 (Messaging):** loads delivery_module, publishes its A2A Agent Card to the shared
  discovery topic and ingests peers over Logos Messaging. See `docs/lp0008-uc-messaging.mp4`.
- **Agent 3 (Blockchain):** holds a shielded LEZ account and settles an on-chain transfer
  with a real proof (tx above). See `docs/lp0008-uc-blockchain.mp4`.

The full repeatable script is `probeF10.sh` on the build VM. Hosted-testnet deployment
evidence is in `docs/TESTNET_EVIDENCE.md` / `docs/STORAGE_TESTNET_EVIDENCE.md` /
`docs/MESSAGING_TESTNET_EVIDENCE.md`.
