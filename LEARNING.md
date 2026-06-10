# LEARNING.md — The Logos Core Stack (reusable knowledge base)

Last researched: 2026-06-06. Lens: LP-0008 (autonomous AI agent module).

This is the durable artifact. It maps the Logos Core stack, the module build-and-load
mechanics, the real per-layer API surface, the A2A-over-Logos mapping, and an explicit
"documented vs gap/unknown" section. Every claim cites a file or doc actually read.

All repos cited are under `github.com/logos-co/*` unless noted as `logos-blockchain/*`
(the LEZ chain) or `logos-messaging/*` (the messaging backends). Local LEZ checkout used:
`companies/logos/lez-build` (a checkout of `logos-blockchain/logos-execution-zone`).

---

## 0. TL;DR — what the stack actually is

Logos Core is a **C++/Qt6 modular application framework**. An "app" is a set of
dynamically-loaded **modules** (Qt plugins, `.so`/`.dylib`) that run in isolated
host processes and talk to each other over **Qt Remote Objects** (IPC). Two frontends
load and drive modules:

- `logoscore` — a **headless CLI runtime** (daemon + client). This is the relevant one for an autonomous agent.
- `logos-basecamp` — the **desktop GUI shell** (the "Logos app" the prize's owner uses).

The "full Logos stack" the prize wants is **four independent modules**, each wrapping a
different backend library through the same plugin pattern:

| Layer (prize term) | Real module(s) | Backend lib | Nature |
| --- | --- | --- | --- |
| Messaging | `logos-chat-module` (E2E 1:1) + `logos-delivery-module` (pub/sub topics) | `liblogoschat`, `liblogosdelivery` (Waku) | two layers, see §5 |
| Storage | `logos-storage-module` | `libstorage` (Codex-style content-addressed) | CID upload/download |
| Wallet (EVM) | `logos-wallet-module` + `logos-accounts-module` | `go-wallet-sdk` (Ethereum) | NOT the shielded LEZ wallet |
| LEZ shielded wallet + programs | **No module exists yet.** Logic lives in the LEZ `wallet` crate (`lez-build/wallet`) | `nssa` / `bedrock_client` (Rust) | the central gap, see §6 |

**The single biggest finding:** the prize's "LEZ wallet (shielded NPK/ISK account)" and
"LEZ program query/call/deploy" skills have **no Logos Core module** today. The shielded
wallet exists only as a **Rust CLI** (`lez-build/wallet/src`) talking to a sequencer over
HTTP RPC. A conforming LP-0008 submission must build that bridge itself. See §6 and §9.

---

## 1. Repository map (what each repo is)

Source: `logos-tutorial/logos-developer-guide.md` "Key components" table + `gh repo list logos-co`.

Core runtime / SDK:
- `logos-liblogos` — core library (`logos_host`, `liblogos_core`); loads plugins, runs the IPC.
- `logos-cpp-sdk` — C++ SDK: `LogosAPI`, `LogosAPIClient`, `TokenManager`, the `logos-cpp-generator` codegen, `LogosResult`, JSON types. (`logos-cpp-sdk/cpp/*`)
- `logos-rust-sdk` — Rust bindings for writing provider modules (`logos-rust-sdk/src/{plugin,api,ffi}.rs`).
- `logos-module-builder` — Nix-based scaffolding + build system; `LogosModule.cmake`, `mkLogosModule.nix`, module templates.
- `logos-module` — plugin loader/introspection lib + the `lm` CLI (inspect a compiled plugin).

Frontends:
- `logos-logoscore-cli` — `logoscore` headless runtime (daemon + client, JSON output).
- `logos-logoscore-py` — Python wrapper over `logoscore` CLI (spawns `logoscore <cmd> --json`); has `LogoscoreDaemon` and `LogoscoreDockerDaemon`.
- `logos-logoscore-tui` — TUI frontend.
- `logos-basecamp` — desktop GUI shell (the owner-facing "Logos app").
- `logos-standalone-app` — minimal shell for running/testing a single UI module in isolation.

Packaging / distribution:
- `logos-package` — `.lgx` package format + `lgx` CLI.
- `logos-package-manager` — local install of `.lgx` into a `modules/` dir + `lgpm` CLI.
- `logos-package-downloader` — online catalog browse/download + `lgpd` CLI.
- `nix-bundle-lgx` — Nix bundler that produces `.lgx` packages.

The four backend modules:
- `logos-chat-module`, `logos-delivery-module`, `logos-storage-module`, `logos-wallet-module`, `logos-accounts-module`.

LEZ chain (separate org `logos-blockchain`):
- `logos-execution-zone` — the LEZ chain itself (Rust). Local checkout: `lez-build/`. Contains `nssa/` (account model + ZK), `wallet/` (the shielded wallet CLI), `programs/` (token/amm/ata), `bedrock_client/` (HTTP client to the sequencer), `examples/program_deployment/`.
- `scaffold` (in `logos-co`) — `logos-scaffold` / `lgs` Rust CLI that bootstraps a LEZ `program_deployment` project against a standalone sequencer. **This is the LEZ-program dev path, separate from the Qt module stack.**

Example modules (read these to learn the pattern):
- `logos-simple-module` — canonical minimal hand-written Qt plugin (no external lib).
- `logos-rust-example-module`, `logos-tutorial` (with `tests/*.test.yaml` executable docs).

AI tooling:
- `logos-ai-skills` — Claude skills + an honest `docs/builder-reality-matrix.md` (ground-truth compatibility caveats; quoted in §8).

---

## 2. Anatomy of a Logos Core module

There are **two patterns**. Source: `logos-tutorial/logos-developer-guide.md` §1.4 and the example modules.

### 2a. Hand-written Qt plugin (older, explicit) — `logos-simple-module`

A module is three files + a manifest (citations: `logos-simple-module/`):

1. **`metadata.json`** — single source of truth. Fields (from dev-guide §1.3):
   `name`, `version`, `type` (`core`|`ui`|`ui_qml`), `category`, `description`, `main`
   (entry plugin name without extension), `interface` (`"universal"` to opt into the
   pure-C++ codegen path), `dependencies` (other module names), `interface_dependencies`
   (runtime-bound contracts), `include` (extra shared libs to bundle, e.g.
   `liblogoschat.dylib`), `capabilities`, and a `nix` block (build/runtime packages,
   `external_libraries`, cmake `find_packages`/`extra_*`).

2. **`<name>_interface.h`** — abstract interface deriving `PluginInterface`, methods marked
   `Q_INVOKABLE virtual ... = 0`, an `eventResponse(QString, QVariantList)` signal, and
   `Q_DECLARE_INTERFACE(..., "org.logos.<Name>Interface")`. (`simple_module_interface.h`)

3. **`<name>_plugin.h/.cpp`** — `class FooPlugin : public QObject, public FooInterface` with
   `Q_OBJECT`, `Q_PLUGIN_METADATA(IID <iid> FILE "metadata.json")`, `Q_INTERFACES(...)`.
   Implements every method, plus `name()`, `version()`, and
   `Q_INVOKABLE void initLogos(LogosAPI*)` which stores the `LogosAPI*` for inter-module
   calls and event emission. (`simple_module_plugin.{h,cpp}`)

Events are emitted with:
`logosAPI->getClient("core_manager")->onEventResponse(this, "fooTriggered", eventData);`
(verbatim from `simple_module_plugin.cpp`). The `core_manager` client is the host event bus.

### 2b. Pure-C++ "universal" module (recommended) — used by chat/delivery/wallet

Set `"interface": "universal"` in `metadata.json` and write **one plain C++ class** with
**no Qt, no Q_OBJECT, no Q_PLUGIN_METADATA, no interface header**. At build time
`logos-cpp-generator --from-header` parses the header and generates the Qt plugin wrapper,
the interface, and inter-module glue. (Source: dev-guide §1.4; `logos-delivery-module/src/delivery_module_plugin.h` and `logos-wallet-module/src/wallet_module_impl.h` are real examples.)

Rules (dev-guide §1.4):
- Any `public` method is exposed (discoverable by `lm`, callable by `logoscore call`, reachable from other modules). `private` is not.
- Supported wire types only: `void, bool, int64_t, uint64_t, double, std::string,
  std::vector<std::string>, std::vector<uint8_t>, LogosMap/LogosList` (`<logos_json.h>`),
  `StdLogosResult` (`<logos_result.h>`). Use `int64_t`, never `int`.
- **Events** go in a `logos_events:` section; the class must inherit `LogosModuleContext`.
  Calling the event method routes typed args to subscribers (outside a host it is a no-op).
  Real example — `logos-delivery-module/src/delivery_module_plugin.h`:
  ```cpp
  logos_events:
      void messageReceived(const std::string& messageHash, const std::string& contentTopic,
                            const std::vector<uint8_t>& payload, int64_t timestamp);
  ```
- **Inter-module calls** via `LogosModuleContext`: `modules().other_module.someMethod(arg)`.
  Declare the dep in `metadata.json` `dependencies` + as a flake input.

You do NOT write `initLogos`, `name()/version()`, `Q_INVOKABLE`, or the event signal — generated.

### 2c. UI modules (out of LP-0008 scope but relevant to the owner channel)

`type: "ui_qml"` modules expose a QML view; a C++ backend variant uses a `.rep`
(Qt Remote Objects) file as the source of truth (`repc` generates SimpleSource + Replica).
QML calls core modules via `logos.callModule("module","method",[args])` or a typed replica.
(Source: dev-guide §7.2.) The prize's owner interface in Basecamp would be such a module.

---

## 3. Build, package, load (the toolchain)

Source: `logos-developer-guide.md` §1.5, §4, §5, §6; module `flake.nix`/`compile.sh`.

**Primary build tool is Nix (flakes).** Qt6 + CMake + Ninja come from the dev shell.

```bash
nix flake init -t github:logos-co/logos-module-builder   # scaffold a core module
git init && git add -A                                    # Nix needs files git-tracked
nix build            # plugin + generated SDK headers
nix build .#lib      # just the .so/.dylib
nix develop          # dev shell (cmake, ninja, Qt, SDK) for manual cmake -B build -GNinja
```
A non-Nix CMake path also exists (`logos-simple-module/scripts/compile.sh` does
`git submodule update --init --recursive` then `cmake` against vendored
`logos-liblogos` + `logos-cpp-sdk`, running `logos-cpp-generator` on `metadata.json`).

**Inspect** a built plugin without loading it (`lm` from `logos-module`):
`lm metadata ./result/lib/foo_plugin.so --json` and `lm methods ... --json`.

**Package** into `.lgx` (gzip tar with `manifest.json` + `variants/<os-arch>/foo_plugin.so`):
`nix build .#lgx` (dev) / `.#lgx-portable` (self-contained) / `nix bundle ...#dual`.
Variant naming matters: dev Basecamp wants `-dev` variants, portable wants plain. (§4.2)

**Install** into a `modules/` dir (`lgpm` from `logos-package-manager`):
`lgpm --modules-dir ./modules install --file ./foo-1.0.0.lgx`.

**Run / drive** with `logoscore` (from `logos-logoscore-cli`):
```bash
logoscore -D -m ./modules            # start daemon hosting modules in ./modules
logoscore load-module foo            # load
logoscore call foo doSomething hello # call a method
logoscore watch foo                  # stream events
logoscore status / stop
```
Inline one-shot: `logoscore -m ./modules -l foo -c "foo.method(arg)" --quit-on-finish`.
`@file.json` passes a file's contents as an argument.

**Python automation** (`logos-logoscore-py`): `LogoscoreDaemon(modules_dir=...)` →
`client.load_module / call / on_event`. `LogoscoreDockerDaemon` runs the daemon in a
container reachable over TCP (binds 6000 `core_service`, 6001 `capability_module`).

---

## 4. Inter-module communication (LogosAPI) — the IPC contract

Source: `logos-developer-guide.md` §8; `logos-cpp-sdk/cpp/logos_api*.{h,cpp}`.

Every module gets a `LogosAPI*` (via `initLogos`, or implicitly through `LogosModuleContext`).
- `logosAPI->getClient("other_module")` returns a `LogosAPIClient`.
- Sync: `client->invokeRemoteMethod("other_module","method", a1..a5)` → `QVariant` (blocks).
- Async (preferred): `client->invokeRemoteMethodAsync("other_module","method", cb, a1..)`.
- Typed wrappers via codegen: `LogosModules* logos = new LogosModules(api);` then
  `logos->other_module.method(args)` / `.methodAsync(args, cb)`.
- `LogosResult` carries structured success/error: `.success`, `.getString/getInt/getMap/getError`,
  keyed access `result.getString("name")`, typed `result.getValue<T>()`.
- **Dependency interfaces**: declare a contract (`interface_dependencies` in metadata) and
  bind a concrete provider at runtime via `modules().bind_<name>("provider_module")`. Binding
  is not validated — a non-conforming provider surfaces a normal remote-call error, never a
  crash. This is exactly how a third-party-skill system would late-bind skill providers.

**This IPC layer is how the agent module will call wallet/storage/messaging modules.**

---

## 5. Messaging layer — real API surface

Messaging is **two modules**, both wrapping Waku-family backends.

### 5a. `logos-delivery-module` (low-level pub/sub) — `liblogosdelivery`

Source: `logos-delivery-module/src/delivery_module_plugin.h` (full doc read).
Universal module. Methods (all synchronous, return `StdLogosResult`):
- `createNode(cfg_json)` — cfg maps to Waku `WakuNodeConf` (camelCase keys: `mode` Core/Edge,
  `preset` `"logos.dev"`/`"twn"`, `clusterId`, `entryNodes[]`, `relay`, `rlnRelay`, `tcpPort`,
  `numShardsInNetwork`, `maxMessageSize`, `logLevel`). Minimal: `{"mode":"Core","preset":"logos.dev"}`.
- `start()` / `stop()`
- `send(contentTopic, payload: vector<uint8_t>)` → requestId; builds
  `{"contentTopic":..., "payload":base64, "ephemeral":false}`.
- `subscribe(contentTopic)` / `unsubscribe(contentTopic)`
- `getAvailableNodeInfoIDs()`, `getNodeInfo(id)`, `getAvailableConfigs()`
- Events (`logos_events:`): `messageSent`, `messageError`, `messagePropagated`,
  `messageReceived(hash, contentTopic, payload, ts)`, `connectionStateChanged`.

Content-topic format is the messaging primitive for **topics/groups**:
ref `lip.logos.co/messaging/informational/23/topics.html#content-topics` (cited in the header).
Payload is raw bytes — **no E2E encryption at this layer**; it is transport.

### 5b. `logos-chat-module` (high-level E2E 1:1) — `liblogoschat`

Source: `logos-chat-module/src/chat_module_plugin.h` (full doc read).
Asynchronous request/event model. Methods return `bool` (accepted?) and deliver results via
`emitEvent(eventName, json)`:
- Lifecycle: `initChat(configJson)`, `setEventCallback()`, `startChat()`, `stopChat()`, `destroyChat()`.
- Identity: `getId()` → `chatGetIdResult`; `getIdentity()` (deprecated); `createIntroBundle()`
  → `chatCreateIntroBundleResult { introBundle }`. The intro bundle is the **public key
  material another party needs to start a 1:1** (X3DH-style). Shared out-of-band.
- Conversations: `listConversations()`, `getConversation(convoId)`,
  `newPrivateConversation(introBundleStr, contentHex)` (open + first message),
  `sendMessage(convoId, contentHex)` (content is hex-encoded bytes).
- Push events: `chatNewMessage`, `chatNewConversation`, `chatDeliveryAck` (each `{payload, timestamp}`).

**E2E encryption + delivery acks live here.** This is the layer for the prize's owner channel
and agent-to-agent encrypted messages.

### Messaging gaps (important)
- **No group/topic creation in `chat_module`** — only 1:1 conversations. `messaging.create_group`
  and `messaging.join(group_id)` from the prize have **no native chat-module call**. Groups must
  be built on `delivery_module` content topics (and you must add your own group-key/E2E scheme,
  or accept transport-only). Confirmed by grep: no `group`/`topic` symbols in `chat_module_plugin.h`.
- `chat_module` config (`liblogoschat`) sits on top of delivery; the exact `configJson` schema
  is undocumented in the module header (says "JSON configuration for the delivery service").

---

## 6. Wallet + LEZ programs — real API surface and the central gap

### 6a. What exists as a module: EVM wallet only

`logos-wallet-module` (`src/wallet_module_impl.h`) and `logos-accounts-module`
(`src/accounts_module_impl.h`) wrap **`go-wallet-sdk`** — i.e. **Ethereum**:
- wallet: `ethClientInit/GetBalance/RpcCall/ChainId`, `txGeneratorTransferETH/ERC20/ERC721/ERC1155`,
  `transactionJsonToRlp/RlpToJson/GetHash`.
- accounts: secp256k1 keystores (`keystoreNewAccount`, `keystoreSignTx`, `createRandomMnemonic`,
  `extKeystoreDerive`, BIP32/39 extended keys).

**This is NOT the LEZ shielded wallet.** It is EVM. The prize explicitly wants a shielded
LEZ NPK/ISK account. So these modules are the wrong wallet for LP-0008 (useful only if the
agent also needs to touch an EVM chain).

### 6b. The real LEZ shielded account model — `nssa` (Rust, no module yet)

Source: `lez-build/nssa/core/src/{account.rs,nullifier.rs}` and `lez-build/README.md`.

LEZ ("Logos Execution Zone") is a programmable chain with **public + private account state**
unified under one model. Privacy is protocol-level via Risc0 ZK proofs; programs are stateless
(all data passed in via accounts), RISC-V/Risc0 bytecode, parallel like Solana.

The shielded identity (the prize's "NPK/ISK"):
- `NullifierSecretKey = [u8; 32]` (the secret; call it ISK/NSK). (`nullifier.rs`)
- `NullifierPublicKey(pub [u8;32])` derived from NSK by a domain-separated SHA256
  (`prefix "LEE/keys" + nsk + suffix`). (`nullifier.rs` `From<&NullifierSecretKey>`)
- A **private `AccountId`** is `SHA256("/LEE/v0.3/AccountId/Private/" + npk)`. (`nullifier.rs` `From<&NullifierPublicKey> for AccountId`)
- Private accounts are never stored raw: each update emits a **commitment** + a **nullifier**
  (`Nullifier::for_account_update(commitment, nsk)`) that marks the prior version spent.
- `Account { program_owner: ProgramId, balance: u128, data: Data, nonce: Nonce }` (`account.rs`)
  is used identically in public and private contexts.
- The wallet CLI also references a **viewing key `vpk`** alongside `npk` for private accounts
  (`lez-build/wallet/src/cli/account.rs`: "Display keys (pk for public accounts, npk/vpk for
  private accounts)"). So the shielded keyset is roughly NSK (spend) + NPK (id) + VPK (view).

### 6c. The real LEZ program interaction — the `wallet` CLI (Rust, no module yet)

Source: `lez-build/wallet/src/{main.rs,cli/mod.rs,cli/account.rs,cli/programs/*}` and
`lez-build/bedrock_client/src/lib.rs`, `lez-build/examples/program_deployment/`.

The LEZ wallet is a **Rust CLI** (`WalletCore`) with subcommands (`wallet/src/cli/mod.rs`):
- `Account New {Public|Private}`, `Account Get/List/SyncPrivate/Label` — create/inspect shielded + public accounts.
- `DeployProgram { binary_filepath }` — deploy a compiled program (→ prize `program.deploy`).
- `Token`, `AMM`, `Ata`, `Pinata`, `AuthTransfer` — program-specific facades incl. **shielded
  transfers** (`wallet/src/program_facades/native_token_transfer/{shielded,private,public,deshielded}.rs`).
- `ChainInfo`, `CheckHealth`, `Config`, `RestoreKeys`.
- Setup: first run generates a BIP39 mnemonic and creates persistent storage; needs env
  `NSSA_WALLET_HOME_DIR`. (`wallet/src/main.rs`)

Wire to the chain: `bedrock_client::BedrockClient` posts a `SignedMantleTx` to a sequencer
node over HTTP (`post_transaction`, `get_lib_stream`, `get_block_by_id`). The wallet also uses
`sequencer_service_rpc::RpcClient` for reads. So **program.query = read account/state via the
sequencer RPC; program.call = build+sign+post a `SignedMantleTx`; program.deploy =
`ProgramDeploymentTransaction`** (imported in `wallet/src/cli/mod.rs` from `nssa`).

ZK proving for private txs uses **Risc0** (`RISC0_DEV_MODE=0` for real proofs — the prize
demands this in the demo). `examples/program_deployment/` shows deploying + running a program
(`run_hello_world*.rs`, incl. `..._private.rs`).

### 6d. The gap, stated plainly

There is **no Logos Core (Qt) module** exposing the LEZ shielded wallet or program calls.
To satisfy LP-0008's wallet/blockchain skills you must build a **`lez_wallet_module`** that
bridges Logos Core ↔ LEZ. Options:
1. Wrap the LEZ `wallet`/`nssa`/`bedrock_client` Rust crates as a `logos-rust-sdk` provider
   module (cleanest; Rust↔Rust), OR
2. Shell out from a C++ universal module to the `wallet` CLI / `logos-scaffold` localnet, OR
3. Reimplement the HTTP/RPC + tx-signing in C++ against the sequencer.
This bridge is the hardest, least-documented part of the whole prize. See BUILD_PLAN §"hard parts".

---

## 7. Storage layer — real API surface

Source: `logos-storage-module/src/storage_module_interface.h` (full read). Hand-written Qt
plugin (not universal). Wraps `libstorage` — a **Codex-style content-addressed** store (libp2p,
CIDs, manifests, erasure/quota). Methods (`LogosResult` unless noted):
- Lifecycle: `init(cfg_json)` (data-dir, listen-addrs, bootstrap-node SPR, storage-quota, api-port…),
  `start()` (async → `storageStart`), `stop()`, `destroy()`, `version()`, `dataDir()`, `debug()`,
  `peerId()`, `spr()` (signed peer record for dialing), `updateLogLevel()`, `connect(peerId, addrs)`.
- Upload: `uploadUrl(QUrl, chunkSize)` → sessionId, events `storageUploadProgress` /
  `storageUploadDone {cid}`. Advanced manual path: `uploadInit/uploadChunk/uploadFinalize/uploadCancel`.
- Download: `downloadToUrl(cid, QUrl, local, chunkSize)`, `downloadChunks(...)` (chunks via
  `storageDownloadProgress`), `downloadCancel`. `exists(cid)`, `fetch(cid)` (background),
  `remove(cid)`, `space()`, `manifests()` (list local), `downloadManifest(cid)`.

Mapping to prize skills:
- `storage.upload(path,label)` → `uploadUrl(file://path)`; the **label** is not a storage
  primitive — the agent keeps a local `cid→label` map (or stores it in a metadata manifest).
- `storage.download(address,path)` → `downloadToUrl(cid, file://path)`.
- `storage.list()` → `manifests()` (+ join with the agent's label map).
- **`storage.share(address, recipient)` has NO native call.** Storage is content-addressed:
  "sharing" = sending the CID (and any decryption key) to the recipient over messaging. The
  prize says upload "encrypts" — but `libstorage` here is plain content addressing; **the agent
  must do its own encryption before upload and share the key out-of-band over chat.** Gap.

---

## 8. Ground-truth compatibility caveats (from logos-ai-skills)

Verbatim-sourced from `logos-ai-skills/docs/builder-reality-matrix.md` ("From ground-truth
runtime testing"). These are real footguns:
- `PluginInterface` and `LogosProviderBase` are **not interchangeable**. Codegen targets
  `LogosProviderBase`; some runtimes use `PluginInterface`. (Mixing them = load failure.)
- **Public Basecamp releases (tested #80–#111) reject user-installed modules.** Local Nix
  builds with file-drop work. So the prize's "loadable assets for Basecamp" likely needs a
  **local Basecamp build**, not a released app.
- LGX packaging has a `-dev` variant naming bug and a `<name>_plugin.so` vs `<name>.so`
  mismatch needing a `postInstall` workaround.
- `Logos.Theme 1.0` (design system) is NOT in all portable builds.
- `ui_qml` pure-QML plugins work but are underdocumented.

---

## 9. A2A over Logos — the mapping

A2A spec (fetched from a2a-protocol.org/latest/specification, 2026-06-06):
- **Three layers**: (1) canonical data model (protobuf), (2) abstract operations
  (binding-independent), (3) protocol bindings (JSON-RPC / gRPC / HTTP-REST). New bindings can
  be added without changing the data model — **so a "Logos Messaging binding" is legitimate A2A.**
- **Agent Card**: JSON with `id`, `name`, `provider`, capability flags (`streaming`,
  `pushNotifications`, `extendedAgentCard`), `securitySchemes`/`security`, `agentInterfaces`
  (`url`, `tenant`), and a `signature` field. (Skills/IO schemas live in interfaces/extensions.)
- **Task lifecycle**: `submitted → working`, interruptible to `input-required` / `auth-required`,
  terminal `completed`/`failed`/`canceled`/`rejected`.
- **Abstract operations**: SendMessage, SendStreamingMessage, GetTask, ListTasks, CancelTask,
  SubscribeToTask, push-notification config ops, GetExtendedAgentCard.
- **A2A deliberately omits payment and transport auth.** That is the exact seam LEZ fills.

### How it lands on Logos (the design the prize asks for):
| A2A concept | Logos realization |
| --- | --- |
| Agent Card publication | Publish signed card JSON on a **delivery-module content topic** (the "discovery topic"). Sign with the agent's LEZ key. |
| Discovery | `subscribe(discovery_topic)` and collect cards (`agent.discover`). |
| Transport binding | A custom A2A binding where each A2A message = a Logos message. **1:1 → chat-module conversation** (E2E); broadcast/discovery → delivery-module topic. |
| SendMessage / Task init | Send a JSON-RPC-shaped A2A request as a chat message to the peer's messaging address; peer replies with a `Task` object over the same conversation. |
| Streaming updates / SubscribeToTask | Map to chat push events / a per-task delivery topic. |
| Payment (A2A gap) | On task acceptance, `wallet.send`/`program.call` transfers the card's declared **LEZ price** to the provider before/at `completed`. This is the LEZ shielded transfer from §6c. |
| Auth (A2A gap) | The agent's messaging address is derived from its LEZ identity (§6b), so the sender is cryptographically the account holder — identity == key. |

**Agent messaging address derivation:** the prize says the Messaging address is derived from
the LEZ identity. In practice the chat-module identity (`getId`/`createIntroBundle`) is its own
keypair today; binding it deterministically to the NSK/NPK is **an integration you must build**
(e.g. seed `liblogoschat` identity from the LEZ key, or publish a card that maps NPK↔intro-bundle).
This linkage is **not provided** by any current module. Gap.

---

## 10. Documented vs gap/unknown — the honest ledger

### Well documented and real (safe to rely on)
- Module anatomy, metadata.json, universal pattern, codegen — `logos-developer-guide.md` + example modules. SOLID.
- Build/package/load/run chain (nix → lm → lgpm → logoscore) — dev-guide §1,4,5,6. SOLID.
- LogosAPI IPC, async calls, LogosResult, dependency interfaces — dev-guide §8. SOLID.
- Delivery (pub/sub) + chat (E2E 1:1) message APIs — module headers, fully doc-commented. SOLID.
- Storage CID upload/download/manifests — `storage_module_interface.h`. SOLID.
- LEZ shielded key model (NSK/NPK/VPK, commitments, nullifiers) — `nssa/core` source. SOLID (as source, not as a packaged API).
- LEZ wallet CLI surface (account/deploy/transfer/program facades) — `lez-build/wallet`. SOLID (as a CLI).

### Gaps the submission must build
1. **LEZ wallet/program Logos module** — does not exist; bridge Rust LEZ ↔ Logos Core (§6d). Hardest.
2. **Shielded address ↔ messaging address binding** — not provided (§9). Must derive deterministically.
3. **Group/topic messaging** — `chat_module` is 1:1 only; build groups on delivery topics + own group keys (§5).
4. **`storage.share` + encryption-before-upload** — no native share; do client-side encrypt + key-over-chat (§7).
5. **A2A binding over Logos Messaging** — must author the binding + Agent Card signing/discovery (§9).
6. **Single-CLI remote deployment** — no native "deploy module to remote node in one command".
   Closest building blocks: `logos-logoscore-py` `LogoscoreDockerDaemon` (daemon over TCP), `lgpm`
   install, and `logoscore -D`. You must wrap SSH/container provisioning yourself. Gap.
7. **Skill plugin system** — the prize wants third-party skills without touching the core module.
   `interface_dependencies` + `bind_<name>` (§4) is the right primitive but you must define the
   skill contract header and a registry. Designable, not pre-built.

### Unknowns (could not verify in this environment)
- `liblogoschat`/`liblogosdelivery` exact `configJson` schemas beyond the documented keys.
- Whether the released LEZ **testnet** (vs the local standalone sequencer in `lez-build`) exposes
  the same RPC + accepts `ProgramDeploymentTransaction`; the prize targets "LEZ testnet" but the
  local checkout is standalone-sequencer oriented. Needs a live testnet endpoint to confirm.
- Real Risc0 proving time/CU costs (`RISC0_DEV_MODE=0`) — not measured (no Risc0 toolchain run here).
- Whether `go-wallet-sdk` modules and the LEZ wallet can coexist in one daemon cleanly.

### Environment reality (this machine, 2026-06-06)
- Present: `rustc`/`cargo` 1.94, `node` 20, `python3` 3.9.
- **Absent: `nix`, `cmake`, `qmake`/Qt6, `go`.** The entire Qt/Logos-Core module build chain is
  **not runnable here** without installing Nix (or Qt6+CMake+Go), which is multi-GB. Therefore no
  module was compiled or loaded; the C++ scaffold in `scaffold/` is **unbuilt skeleton**, honestly
  flagged as such. LEZ Rust crates *could* build here in principle but require the
  `logos-blockchain-circuits` release + Risc0 (`rzup`) which are not installed.
