#pragma once
// Third-party skill contract for the LP-0008 agent module.
//
// A skill is its own Logos `core` module exposing this contract. The agent binds
// it at runtime via `modules().bind_skill("<provider_module>")` (see Logos
// dependency-interfaces: LEARNING.md S4). New skills require NO change to the
// agent core module — this is the prize's "documented skill interface" requirement.
//
// This is a contract header for `logos-cpp-generator` (the "universal" pattern).
// It is NOT compiled standalone here; it is parsed by the builder at module build
// time to generate the bound wrapper. See scaffold/README.md for build status.

#include <string>

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
