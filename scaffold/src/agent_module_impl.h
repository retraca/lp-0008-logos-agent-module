#pragma once
// LP-0008 agent module - "universal" (pure-C++) Logos Core module.
// Pre-built arm64 bundle: scaffold/libagent_module_plugin.so (3.7 MB)
//
// Every public method below becomes a Q_INVOKABLE wire method via
// `logos-cpp-generator --from-header` at build time. Wire types only: void/bool/
// int64_t/uint64_t/double/std::string/std::vector<...>/Logos types (LEARNING.md S2b).
//
// Inter-module calls go through LogosModuleContext: modules().chat_module.*,
// modules().storage_module.*, modules().delivery_module.*, and the bound
// modules().bind_lez_wallet(...) / modules().bind_skill(...) (LEARNING.md S4).
//
// Methods return JSON strings (result or error envelope) so callers over
// `logoscore call` and A2A get a uniform, language-neutral surface.

#include <string>
#include <vector>
#include <memory>
#include <cstdint>
#include <logos_module_context.h>   // provided by logos-cpp-sdk at build time

class AgentModuleImpl : public LogosModuleContext {
public:
    AgentModuleImpl();
    ~AgentModuleImpl();

    // ===== Storage skills (-> storage_module; encrypt/label/share are agent-side) =====
    std::string storage_upload(const std::string& path, const std::string& label);
    std::string storage_download(const std::string& address, const std::string& path);
    std::string storage_list();
    std::string storage_share(const std::string& address, const std::string& recipient);

    // ===== Messaging skills (-> chat_module 1:1; groups via delivery_module topics) =====
    std::string messaging_send(const std::string& recipient, const std::string& message);
    std::string messaging_join(const std::string& group_id);
    std::string messaging_create_group(const std::vector<std::string>& members);

    // ===== Blockchain skills (-> bound lez_wallet; spending-threshold gate here) =====
    std::string wallet_balance();
    std::string wallet_send(const std::string& recipient, const std::string& amount);     // gated
    std::string wallet_history();
    std::string program_query(const std::string& program_id, const std::string& params);
    std::string program_call(const std::string& program_id,
                             const std::string& instruction, const std::string& params);   // gated
    std::string program_deploy(const std::string& binary_path);                            // may be gated

    // ===== Agent coordination (A2A over Logos Messaging) =====
    std::string agent_card();
    std::string agent_discover(const std::string& topic);
    std::string agent_task(const std::string& agent_address,
                           const std::string& skill, const std::string& params);            // pays LEZ price
    std::string agent_subscribe(const std::string& agent_address, const std::string& task_id);
    std::string agent_cancel(const std::string& agent_address, const std::string& task_id);

    // ===== Meta =====
    std::string meta_skills();
    std::string meta_status();
    std::string meta_configure(const std::string& key, const std::string& value);

    // ===== Owner approval (above-threshold flow; ARCHITECTURE.md S5) =====
    // Owner replies to an approval request over the E2E owner channel.
    std::string approve_pending(const std::string& proposal_id);
    std::string reject_pending(const std::string& proposal_id);

logos_events:
    // Emitted to the owner channel / subscribers (typed events; LEARNING.md S2b).
    void approval_required(const std::string& proposal_id, const std::string& proposal_json);
    void task_update(const std::string& task_id, const std::string& status_json);
    void skill_failed(const std::string& skill, const std::string& error);

private:
    // spending-threshold state (set via meta_configure; persisted with task state)
    std::string owner_address_;
    std::string per_tx_limit_;
    std::string per_period_limit_;
    int64_t     period_seconds_ = 0;

    // PIMPL: all runtime state (pending proposals, cid map, spend counter, config)
    // lives in Impl to keep this header free of STL container types that logos-cpp-generator
    // does not understand.
    struct Impl;
    std::unique_ptr<Impl> impl_;

    // returns true if (amount<=per_tx) && (period_spent+amount<=per_period); else queues approval
    bool within_threshold(const std::string& amount_decimal);

    // Internal helpers (not exposed as wire methods).
    void        ensure_loaded();
    void        sync_config_fields();
    void        record_spend(double amount);
    void        send_owner_message(const std::string& text);
    std::string create_pending_proposal(const std::string& action,
                                        const std::string& recipient,
                                        const std::string& amount,
                                        const std::string& reason,
                                        const std::string& task_id);
};
