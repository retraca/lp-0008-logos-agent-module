# Skill Interface Specification

Third parties can add new capabilities to the LP-0008 agent without modifying or recompiling the core agent module. This document describes the contract, registration mechanism, and step-by-step process for writing and deploying a new skill.

---

## Design principle

A skill is a separate Logos `core` module that exposes the `ISkill` contract. The agent binds it at runtime via `modules().bind_skill("<provider_module_name>")`. There is no fork, no recompile, and no restart of the core agent module when a new skill provider is added.

This follows the Logos dependency-interface pattern: contract headers are parsed by `logos-cpp-generator` at build time to produce bound wrappers. The agent holds a reference to each provider's `ISkill` binding and calls through it. If a provider module is absent at load time, the agent logs a warning and continues — the missing skill simply does not appear in `meta.skills()`.

---

## The ISkill interface

The full contract is in `scaffold/interfaces/skill.h` (reproduced below). Do not modify this header; copy it into your skill project as a read-only reference.

```cpp
class ISkill {
public:
    // Stable skill identifier, e.g. "translate", "ocr", "code_review".
    std::string skill_name();

    // JSON describing params + input/output schemas, surfaced in meta.skills()
    // and the A2A Agent Card. Shape (proposed):
    //   {"name":"translate","params":{"text":"string","to":"string"},
    //    "returns":{"text":"string"},"lez_price":"0"}
    std::string skill_schema();

    // Execute the skill. params_json matches skill_schema().params.
    // Returns a result JSON (or an error envelope). Must not throw across the
    // module boundary; failures are returned as values so a failing skill never
    // crashes the agent (prize Reliability: skill failure isolation).
    std::string invoke(const std::string& params_json);

logos_events:
    // Streaming progress for long-running skills; maps to A2A task status updates
    // and is forwarded to the requester over Logos Messaging.
    void progress(const std::string& task_id, const std::string& status_json);
};
```

### Method descriptions

**`skill_name()`**

Returns a stable, dot-notation identifier such as `"translate"` or `"ocr.extract_text"`. This name is used as the dispatch key when the owner or a peer agent calls the skill, and it appears verbatim in the Agent Card's capability list. Pick a name that will not collide with the 20 built-in skill names (listed in ARCHITECTURE.md §7).

**`skill_schema()`**

Returns a JSON string describing the skill's input parameters and output shape. The agent calls this once at bind time to populate `meta.skills()` and to include the skill in the A2A Agent Card. Minimum valid shape:

```json
{
  "name": "translate",
  "params": {
    "text": "string",
    "to": "string"
  },
  "returns": {
    "text": "string"
  },
  "lez_price": "0"
}
```

Set `"lez_price"` to a non-zero decimal string if your skill charges LEZ per invocation. The agent will enforce payment via `wallet.send` before forwarding the result to the caller.

**`invoke(params_json)`**

Executes the skill synchronously (or kicks off async work and returns a task ID for progress tracking). The input is a JSON object whose keys match `skill_schema().params`. The return value must be one of:

- Success: `{"result": <any JSON value>}`
- Failure: `{"error": {"code": "ERR_CODE", "message": "human-readable description"}}`

This method must never throw or abort across the module boundary. All errors are values. The agent wraps every `invoke()` call in a catch-all; an uncaught exception is treated as a fatal skill error and returned as `{"error": {"code": "SKILL_PANIC", "message": "..."}}`, but relying on this is bad practice.

**`progress(task_id, status_json)` (event)**

Emitted by the skill module for long-running work. `status_json` should follow A2A task status shape:

```json
{
  "state": "working",
  "message": {"role": "agent", "parts": [{"text": "Translating..."}]}
}
```

The agent receives this event and forwards it to the original requester over Logos Messaging, enabling real-time streaming updates to the owner or a peer agent that called `agent.subscribe`.

---

## Registration

The agent maintains a `skill_providers` config key: a JSON array of provider module names. Set it via `meta.configure`:

```bash
logoscore -c "agent_module.meta_configure(\"skill_providers\", \"[\\\"translate_module\\\",\\\"ocr_module\\\"]\")"
```

On startup (and whenever `skill_providers` changes), the agent iterates the list, calls `modules().bind_skill(name)` for each entry, and calls `skill_schema()` to register the skill. Skills that bind successfully appear in `meta.skills()` output and in the A2A Agent Card published to the discovery topic.

If the Logos Core module system supports hot-loading (loading a new `.so` into a running `logoscore` daemon), a new skill provider can be registered without restarting the daemon. Otherwise, restart `logoscore` with the new module added to the `-m` flag list before calling `meta.configure`.

---

## Step-by-step: adding a third-party skill

**a. Copy the contract header**

```bash
cp scaffold/interfaces/skill.h my_skill_module/interfaces/skill.h
```

Treat this file as read-only. It is the stable ABI. Do not modify it.

**b. Create a new Logos `core` module**

Follow the same module scaffold pattern as `scaffold/` (see SUBMISSION.md build instructions). Your `metadata.json` should declare `"interface": "universal"` and list `ISkill` as a provided contract.

**c. Implement the three methods**

```cpp
// my_skill_module_impl.cpp
std::string MySkillModuleImpl::skill_name() {
    return "translate";
}

std::string MySkillModuleImpl::skill_schema() {
    return R"({"name":"translate","params":{"text":"string","to":"string"},
               "returns":{"text":"string"},"lez_price":"0"})";
}

std::string MySkillModuleImpl::invoke(const std::string& params_json) {
    try {
        auto params = nlohmann::json::parse(params_json);
        std::string text = params.at("text");
        std::string to   = params.at("to");
        // ... do the work ...
        return nlohmann::json{{"result", nlohmann::json{{"text", translated}}}}.dump();
    } catch (const std::exception& e) {
        return nlohmann::json{{"error", {{"code","TRANSLATE_ERROR"},{"message",e.what()}}}}.dump();
    }
}
```

Emit `progress` events for long-running work:

```cpp
// inside invoke(), before returning:
emit_progress(task_id, R"({"state":"working","message":{"role":"agent","parts":[{"text":"Translating..."}]}})");
```

**d. Build**

```bash
cd my_skill_module
nix develop /path/to/lez-wallet-module/qt-module   # reuse the same dev shell
cmake -S . -B build -GNinja -Wno-dev
ninja -C build
# Output: build/libmy_skill_module_plugin.so
```

**e. Load alongside the agent module**

```bash
logoscore -D \
  -m lez-wallet-module/qt-module/build/liblez_wallet_module_plugin.so \
  -m lp-0008-ai-module/scaffold/build/libagent_module_plugin.so \
  -m my_skill_module/build/libmy_skill_module_plugin.so
```

**f. Register the provider**

```bash
logoscore -c "agent_module.meta_configure(\"skill_providers\", \"[\\\"my_skill_module\\\"]\")"
```

**g. Verify**

```bash
logoscore -c "agent_module.meta_skills()"
```

Your skill should appear in the output alongside the 20 built-in skills. The Agent Card returned by `agent.card` will also include your skill's schema and `lez_price`.

---

## Error handling contract

Every `invoke()` implementation must follow this contract without exception:

| Condition | Return |
|---|---|
| Success | `{"result": <value>}` |
| Expected failure (bad params, timeout, etc.) | `{"error": {"code": "ERR_CODE", "message": "..."}}` |
| Unexpected exception | Catch it; return `{"error": {"code": "SKILL_PANIC", "message": "<what>"}}` |
| Never | throw, abort, or call `exit()` |

The agent module wraps every `invoke()` call in a try-catch as a last resort, but skill authors must not rely on it. A skill that throws across the module boundary on some inputs is a reliability bug.

---

## Built-in skills vs third-party skills

The 20 default skills (the full `storage.*`, `messaging.*`, `wallet.*`, `program.*`, `agent.*`, and `meta.*` surface) are implemented inside `agent_module_impl.cpp` and call the backend modules directly. They are always available; they do not appear in the `skill_providers` config list.

Third-party skills extend this surface. They cannot override or shadow a built-in skill name. If a provider returns a `skill_name()` that collides with a built-in, the agent logs a warning and ignores the provider.

The `meta.skills()` output groups built-ins separately from third-party providers so callers can see which category each skill belongs to.
