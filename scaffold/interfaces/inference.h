#pragma once
// Pluggable inference contract for the LP-0008 agent module.
//
// The prize scope requires the module to "support pluggable inference (local or
// API-based), but the choice of model is left to the deployer" — so the agent core
// depends on THIS interface, never on a concrete model. A deployer plugs in their
// own inference backend without touching the agent core module, exactly like a
// third-party skill (see skill.h).
//
// The adapter's ONLY job is to decide *which skill to invoke with which params*
// given the owner's request and the available skills. It never touches wallet keys,
// the chain, or the network directly — every effect flows back through the agent's
// gated skill dispatch (spending threshold, owner approval, A2A). This keeps the
// security model intact regardless of which model a deployer chooses.
//
// Reference implementations a deployer can bind:
//   - local:  llama.cpp / Ollama over a subprocess or localhost HTTP (no data leaves the node)
//   - API:    an OpenAI-compatible HTTP endpoint (deployer supplies the key via meta.configure)
//   - mock:   a deterministic rule-based planner for tests / offline demos
//
// Like skill.h, this is a contract header parsed by `logos-cpp-generator` at module
// build time; the concrete adapter is a separate module bound at runtime via
// meta.configure("inference_adapter", "<provider_module>").

#include <string>

class IInferenceAdapter {
public:
    // Stable adapter identifier, e.g. "ollama-local", "openai-http", "mock".
    std::string adapter_name();

    // Plan the next action. Inputs:
    //   request_json  — the owner's natural-language / structured request
    //   skills_json   — the agent's available skills + schemas (from meta.skills())
    // Returns an action envelope naming a skill and its params, e.g.
    //   {"skill":"wallet_send","params":{"to":"npk…","amount":"5"},"reason":"…"}
    // or {"skill":"none","reason":"clarify: …"} to ask the owner. The agent then
    // runs that skill through its gated dispatch — the adapter never executes it.
    std::string plan(const std::string& request_json, const std::string& skills_json);

logos_events:
    // Optional streaming of the model's reasoning tokens for observability; forwarded
    // to the owner over the owner channel, never to a third party.
    void thinking(const std::string& task_id, const std::string& token);
};
