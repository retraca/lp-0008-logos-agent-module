# ARCHITECTURE.md — LP-0008 Agent Module Architecture

Companion to `LEARNING.md` (stack + API citations) and `SUBMISSION.md` (build instructions).
Covers the as-built architecture of `lez_wallet_module` and `agent_module`. Where an
integration layer is declared but not yet live-wired, the gap is called out explicitly.

---

## 1. Component overview

```
                      Owner's laptop (Logos Basecamp)
   +----------------------------------------------------------+
   |  owner_chat_ui (ui_qml)  <— E2E chat-module conversation  |
   +----------------------------------------------------------+
                         |  Logos Messaging (chat-module, E2E)
                         |  owner channel = 1:1 conversation
                         v
   Remote node (logoscore -D, headless)
   +----------------------------------------------------------+
   |  agent_module  (core, universal C++)                     |
   |   - runtime loop / skill dispatcher                      |
   |   - owner channel handler + spending-threshold gate      |
   |   - A2A binding (cards, task lifecycle) over messaging   |
   |   - pluggable inference adapter (local or API)           |
   |        |          |            |              |          |
   |        v          v            v              v          |
   |  chat_module  delivery_module storage_module  lez_wallet_module  <-- NEW (gap)
   |  (E2E 1:1)    (topics/groups) (CID files)     (shielded wallet + LEZ programs)
   +----------------------------------------------------------+
                         |
                         v   bedrock_client HTTP / sequencer RPC + Risc0 proofs
                   LEZ sequencer (testnet / standalone)
```

The agent is a **`core` universal module** loaded by `logoscore` on a remote node. It calls the
four backend modules over `LogosAPI` (LEARNING §4). The owner drives it from Basecamp over an
E2E chat conversation. The one module that does not exist yet — **`lez_wallet_module`** — is the
critical new build (LEARNING §6d).

---

## 2. Runtime

- **Module type:** `core`, `"interface": "universal"` (single `agent_module_impl.{h,cpp}`,
  no hand-written Qt). Pattern per LEARNING §2b.
- **Event loop:** `logoscore` hosts the module in the Qt event loop. The agent reacts to:
  (a) owner messages (chat push events `chatNewMessage`), (b) peer A2A messages, (c) delivery
  topic events (discovery, task streams), (d) timers for autonomous monitoring (DAO/alerter use
  cases). All async via `LogosModuleContext` event subscriptions; no blocking calls on the loop.
- **Inference is pluggable** (prize requirement, out of scope to pick a model): an
  `InferenceAdapter` interface with a `complete(prompt, tools) -> action` method. Implementations:
  local (llama.cpp/ollama via subprocess) or API (HTTP). The adapter only decides *which skill to
  invoke with which params*; it never touches keys or the chain directly.
- **Reliability** (prize: recover from restarts, isolate skill failures):
  - Pending-task state persisted to `storage_module` (or a local JSON in the module data dir),
    keyed by A2A `taskId`; reloaded on start.
  - Each skill call wrapped so an exception/timeout becomes a `failed` skill result, never a
    module crash (LEARNING §4 — remote-call errors are values, not crashes).
  - Above-threshold tx that cannot reach the owner is **never executed**: retry the chat
    notification N times, then mark the proposal `failed` and report. (Prize Reliability criterion.)

---

## 3. Identity

The agent owns a single root secret from which everything derives:
- **LEZ shielded identity:** NSK (`NullifierSecretKey`) → NPK (`NullifierPublicKey`) → private
  `AccountId` (LEARNING §6b). NSK generated on first deploy from a BIP39 mnemonic (mirrors
  `WalletCore::new_init_storage`, `lez-build/wallet/src/main.rs`). VPK for viewing.
- **Messaging address:** the prize wants it *derived from* the LEZ identity. Concretely:
  seed the `liblogoschat` identity deterministically from the NSK (or, if the chat backend will
  not accept a supplied seed, publish an Agent Card that **binds** the chat `introBundle` to the
  NPK with a signature). This binding is a **gap to build** (LEARNING §9, §10 gap 2).
- **Custody:** the NSK lives only on the remote node, in the module's data dir, encrypted at rest
  with an owner-supplied passphrase (same shape as the wallet keystore). The owner's laptop never
  holds the agent's NSK — it holds the *owner's* keys for the chat channel. "No custodian" holds.

---

## 4. Owner channel

- A dedicated **E2E 1:1 chat-module conversation** between owner and agent (LEARNING §5b).
- Bootstrapped at deploy: the deploy CLI passes the owner's `introBundle`; the agent calls
  `newPrivateConversation(ownerIntroBundle, firstMessage)` and pins that `convoId` as the owner
  channel. Owner address is also stored as `meta.configure` config.
- All owner interaction (commands, approvals, summaries) flows over this conversation. Because it
  is E2E and serverless, the "no intermediary server" criterion holds.
- The owner reaches the agent **from any Basecamp instance holding the owner's keys** — chat
  identity is key-derived, not device-bound.

---

## 5. Spending threshold (the approval gate)

State (set via `meta.configure`): `per_tx_limit`, `per_period_limit`, `period_seconds`,
`owner_address`. A rolling spend counter persisted with task state.

Gate logic, applied inside `wallet.send`, `program.call`, and A2A payment:
```
amount <= per_tx_limit AND (period_spent + amount) <= per_period_limit
   -> execute autonomously (sign + post SignedMantleTx via lez_wallet_module)
else
   -> build the proposed tx, send it to the owner over the owner channel as a
      structured approval request {action, recipient, amount, reason, task_id},
      enter A2A `input-required`/local "pending-approval", and WAIT.
      On "approve" reply -> execute. On "reject"/timeout -> failed, report.
```
This is a software policy in front of the wallet module; the chain itself does not enforce it.
For a stronger guarantee, above-threshold spends could route through an on-chain M-of-N
(LP-0002 multisig) where the owner is a required signer — noted as an upgrade, not the baseline.

---

## 6. Skill interface (third-party skills without touching the core)

Use Logos **dependency interfaces** (LEARNING §4) as the extension mechanism:
- Define a contract header `interfaces/skill.h` (a `LogosModuleContext`-style contract):
  ```cpp
  // interfaces/skill.h  (the third-party skill contract)
  class ISkill {
  public:
      std::string skill_name();                 // e.g. "translate"
      std::string skill_schema();               // JSON: params + IO schema (for Agent Card)
      std::string invoke(const std::string& params_json);  // returns result JSON
  logos_events:
      void progress(const std::string& task_id, const std::string& status_json);
  };
  ```
- A skill provider is its own `core` module exposing `ISkill`. The agent **binds** it at runtime:
  `auto s = modules().bind_skill("translate_module"); s.invoke(params);` — no core-module change,
  no validation crash if the provider is imperfect (LEARNING §4).
- A **skill registry**: the agent reads a config list of provider module names (or discovers them
  from loaded modules via `logoscore list-modules`), binds each, and calls `skill_schema()` to
  build `meta.skills()` and the Agent Card.
- The 20 default skills below are implemented *inside* the agent module as built-ins that call the
  backend modules directly; third parties add *new* skills as separate `ISkill` providers.

---

## 7. The 20 default skills → real API mapping

Legend: **[direct]** maps to a real backend call; **[build]** needs the new `lez_wallet_module`;
**[compose]** needs agent-side logic beyond a single call; **[gap]** no native primitive (LEARNING §10).

### Storage
| Skill | Mapping |
| --- | --- |
| `storage.upload(path,label)` | **[direct/compose]** `storage_module.uploadUrl(file://path)` → cid; agent keeps `cid→label` map. Prize says "encrypts": **[gap]** agent must encrypt bytes before upload (libstorage is plain CID). |
| `storage.download(address,path)` | **[direct]** `storage_module.downloadToUrl(cid, file://path)` (+ decrypt). |
| `storage.list()` | **[compose]** `storage_module.manifests()` joined with the label map. |
| `storage.share(address,recipient)` | **[gap]** no native share. Agent sends `{cid, decryptKey}` to recipient over chat-module. |

### Messaging
| Skill | Mapping |
| --- | --- |
| `messaging.send(recipient,message)` | **[direct]** chat-module `sendMessage(convoId, hex)` (1:1, E2E) or open via `newPrivateConversation`. |
| `messaging.join(group_id)` | **[compose/gap]** chat has no groups. `delivery_module.subscribe(group_topic)`; group E2E keying is agent-built. |
| `messaging.create_group(members)` | **[compose/gap]** allocate a delivery content topic, distribute the topic + group key to members over 1:1 chat. |

### Blockchain (all need the new module)
| Skill | Mapping |
| --- | --- |
| `wallet.balance()` | **[build]** `lez_wallet_module` reads the agent's account via sequencer RPC (`Account.balance`, LEARNING §6c). |
| `wallet.send(recipient,amount)` | **[build]** shielded transfer (`native_token_transfer/shielded`) + spending gate (§5). |
| `wallet.history()` | **[build]** derive from synced private account updates / chain scan (`Account SyncPrivate`). |
| `program.query(program_id,params)` | **[build]** read program/account state via sequencer RPC. |
| `program.call(program_id,instruction,params)` | **[build]** build+sign+post `SignedMantleTx`; spending gate. |
| `program.deploy(binary_path)` | **[build]** `ProgramDeploymentTransaction` (LEARNING §6c). |

### Agent coordination (A2A)
| Skill | Mapping |
| --- | --- |
| `agent.card()` | **[compose]** build signed Agent Card JSON (A2A schema, LEARNING §9) from `meta.skills()` + NPK + LEZ price; publish to the discovery delivery topic. |
| `agent.discover(topic)` | **[compose]** `delivery_module.subscribe(topic)`, collect + verify cards. |
| `agent.task(agent_address,skill,params)` | **[compose]** A2A SendMessage over chat to peer; follow `working→input-required→completed/failed`; on acceptance pay LEZ price via `wallet.send`/`program.call`. |
| `agent.subscribe(agent_address,task_id)` | **[compose]** map A2A SubscribeToTask to chat push events / a per-task delivery topic. |
| `agent.cancel(agent_address,task_id)` | **[compose]** A2A CancelTask message; trigger refund logic if the provider supports it. |

### Meta (all agent-internal)
| Skill | Mapping |
| --- | --- |
| `meta.skills()` | **[compose]** built-in list + bound `ISkill.skill_schema()` for each registered provider. |
| `meta.status()` | **[compose]** `wallet.balance()` + `storage_module.space()` + active-task table. |
| `meta.configure(key,value)` | **[compose]** update persisted config (thresholds, owner address, discovery topic). |

---

## 8. A2A binding (concrete)

- **Card** = A2A AgentCard JSON (`id`,`name`,`provider`,capability flags,`securitySchemes`,
  `agentInterfaces`,`signature`) extended with a `x-lez-price` per skill and the NPK as identity.
  Signed with the LEZ key. Published on a delivery discovery topic.
- **Transport binding** = "A2A over Logos Messaging": each abstract A2A operation (SendMessage,
  GetTask, CancelTask, SubscribeToTask) is a JSON-RPC-shaped message carried as a chat-module
  message (1:1, E2E) or, for discovery/broadcast, a delivery topic post. Documented as a custom
  binding per A2A's Layer-3 extensibility (LEARNING §9).
- **Payment** = on `working→completed` (or on acceptance, configurable), transfer `x-lez-price`
  to the provider's NPK via the shielded wallet. This is the LEZ contribution A2A lacks.
- **Refund** on cancel/failure = a reverse shielded transfer or an escrow program (escrow = a LEZ
  program; baseline ships direct transfer + best-effort refund, escrow noted as upgrade).

---

## 9. Security model (what the agent can/can't do without the owner)

- **Can autonomously:** read balances/state, receive funds, store/fetch its own files, send
  messages, join/create topics, publish/discover Agent Cards, run skills, and spend **up to the
  configured per-tx and per-period limits**.
- **Cannot without owner approval:** any spend above threshold (`wallet.send`, `program.call`,
  `program.deploy` if it costs above threshold, A2A payments above threshold). These are held and
  require an explicit approve reply on the E2E owner channel.
- **Key custody:** NSK never leaves the remote node; encrypted at rest. Owner holds only owner
  keys. Compromise of the node exposes the agent's funds up to its balance but not the owner's
  wallet.
- **Failure-safe:** unreachable owner ⇒ above-threshold tx not executed (retry then fail).
