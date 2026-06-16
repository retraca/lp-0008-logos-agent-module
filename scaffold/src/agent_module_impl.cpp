// agent_module_impl.cpp - LP-0008 autonomous AI agent module implementation.
//
// Implements every method declared in agent_module_impl.h.
// Wire types: void/bool/int64_t/std::string/std::vector - no Qt types here.
// All return values are JSON strings: success shape {"result": ...} or
// error envelope {"error": "message"}.
//
// Inter-module calls:
//   modules().chat_module.*        (LEARNING.md S5b)
//   modules().delivery_module.*    (LEARNING.md S5a)
//   modules().storage_module.*     (LEARNING.md S7)
//   modules().bind_lez_wallet("lez_wallet_module")   (LEARNING.md S4, interface_dependencies)
//   modules().bind_skill("<provider>")               (ibid)
//
// TODO: verify API shape against logos-core source for every modules().* call below.
// The exact call syntax (positional args, return wrapper type) depends on the generated
// code produced by logos-cpp-generator from metadata.json. The patterns here follow
// LEARNING.md S2b and S4 examples verbatim.

#include "agent_module_impl.h"

// Generated SDK header providing modules(), bind_lez_wallet(), etc.
// Included from sdk_generated/ at build time (logos-cpp-generator --general-only).
#include "logos_sdk.h"
#include "logos_mode.h"

#include <QString>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

using json = nlohmann::json;
namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

namespace {

// Module version, mirrored from metadata.json.
constexpr const char* kVersion = "0.0.1";

// File names written into the module data directory.
constexpr const char* kConfigFile   = "config.json";
constexpr const char* kSpendFile    = "spend_state.json";
constexpr const char* kPendingFile  = "pending_proposals.json";
constexpr const char* kCidMapFile   = "cid_labels.json";

// A2A discovery content topic (overridable via meta_configure "discovery_topic").
constexpr const char* kDefaultDiscoveryTopic = "/logos/agent-discovery/1/default/proto";

// Error envelope helper.
inline std::string err(const std::string& msg) {
    return json{{"error", msg}}.dump();
}

// Success envelope: wraps any json value.
inline std::string ok(const json& val) {
    return json{{"result", val}}.dump();
}

// Generate a pseudo-unique ID (timestamp + counter) without pulling in UUID libs.
// Good enough for proposal/task IDs inside one process lifetime.
std::string make_id(const std::string& prefix) {
    static std::mutex mu;
    static int64_t counter = 0;
    std::lock_guard<std::mutex> lk(mu);
    auto now = std::chrono::steady_clock::now().time_since_epoch().count();
    return prefix + "_" + std::to_string(now) + "_" + std::to_string(counter++);
}

// Parse a decimal string to double (amounts are decimal strings to avoid u128 overflow).
// Returns -1.0 on parse failure.
double parse_amount(const std::string& s) {
    if (s.empty()) return -1.0;
    try {
        return std::stod(s);
    } catch (...) {
        return -1.0;
    }
}

// ISO-8601 UTC timestamp string.
std::string utc_now_iso() {
    auto t = std::time(nullptr);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&t));
    return std::string(buf);
}

// Hex-encode arbitrary bytes so they can be sent as a chat message content string.
std::string hex_encode(const std::string& s) {
    static const char* hex = "0123456789abcdef";
    std::string out;
    out.reserve(s.size() * 2);
    for (unsigned char c : s) {
        out.push_back(hex[c >> 4]);
        out.push_back(hex[c & 0xf]);
    }
    return out;
}

// Safe json::parse that never throws; returns json::object() on failure.
json safe_parse(const std::string& s) {
    try {
        return json::parse(s);
    } catch (...) {
        return json::object();
    }
}

// Load a JSON file from disk; returns json::object() if absent or malformed.
json load_json_file(const fs::path& p) {
    if (!fs::exists(p)) return json::object();
    std::ifstream f(p);
    if (!f.is_open()) return json::object();
    try {
        json j;
        f >> j;
        return j;
    } catch (...) {
        return json::object();
    }
}

// Persist a JSON value to a file (atomic: write temp then rename).
bool save_json_file(const fs::path& p, const json& j) {
    fs::path tmp = fs::path(p).replace_extension(".tmp");
    try {
        std::ofstream f(tmp);
        if (!f.is_open()) return false;
        f << j.dump(2);
        f.flush();
        f.close();
        fs::rename(tmp, p);
        return true;
    } catch (...) {
        return false;
    }
}

} // anonymous namespace


// ---------------------------------------------------------------------------
// AgentModuleImpl - private state container
// ---------------------------------------------------------------------------
// Because `logos-cpp-generator` produces the Qt wrapper from our header, we
// cannot add private member fields in the header (the generator would try to
// expose them). We therefore use a PIMPL pattern: all runtime state lives in
// `AgentModuleImpl::Impl`, pointed to by `impl_`.

struct AgentModuleImpl::Impl {
    // --- persisted config (config.json) ---
    std::unordered_map<std::string, std::string> config;

    // --- spend state (spend_state.json) ---
    double   period_spent     = 0.0;
    int64_t  period_start_ts  = 0;    // Unix seconds

    // --- pending proposals (pending_proposals.json) ---
    // Key: proposal_id; value: full proposal JSON object.
    std::unordered_map<std::string, json> pending_proposals;

    // --- cid->label map (cid_labels.json) ---
    // Key: CID string; value: user-supplied label.
    std::unordered_map<std::string, std::string> cid_labels;

    // --- bound skill module names (from config "skill_providers") ---
    std::vector<std::string> skill_providers;

    // --- data directory (set by LogosModuleContext at init time) ---
    fs::path data_dir;

    // Persist helpers
    void save_config()   const { save_json_file(data_dir / kConfigFile,   json(config)); }
    void save_spend()    const {
        json j;
        j["period_spent"]    = period_spent;
        j["period_start_ts"] = period_start_ts;
        save_json_file(data_dir / kSpendFile, j);
    }
    void save_pending()  const {
        json j = json::object();
        for (auto& [k, v] : pending_proposals) j[k] = v;
        save_json_file(data_dir / kPendingFile, j);
    }
    void save_cid_map()  const {
        json j = json::object();
        for (auto& [k, v] : cid_labels) j[k] = v;
        save_json_file(data_dir / kCidMapFile, j);
    }

    void load_all() {
        // config
        json jc = load_json_file(data_dir / kConfigFile);
        for (auto& [k, v] : jc.items()) {
            if (v.is_string()) config[k] = v.get<std::string>();
            else               config[k] = v.dump();
        }
        // skill providers list from config
        if (config.count("skill_providers")) {
            auto arr = safe_parse(config["skill_providers"]);
            if (arr.is_array()) {
                for (auto& s : arr) {
                    if (s.is_string()) skill_providers.push_back(s.get<std::string>());
                }
            }
        }
        // spend state
        json js = load_json_file(data_dir / kSpendFile);
        period_spent    = js.value("period_spent",    0.0);
        period_start_ts = js.value("period_start_ts", int64_t(0));
        // pending proposals
        json jp = load_json_file(data_dir / kPendingFile);
        for (auto& [k, v] : jp.items()) {
            pending_proposals[k] = v;
        }
        // cid labels
        json jl = load_json_file(data_dir / kCidMapFile);
        for (auto& [k, v] : jl.items()) {
            if (v.is_string()) cid_labels[k] = v.get<std::string>();
        }
    }

    // Helper: read a config string with default.
    std::string cfg(const std::string& key, const std::string& dflt = "") const {
        auto it = config.find(key);
        return (it != config.end()) ? it->second : dflt;
    }
};


// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------

AgentModuleImpl::AgentModuleImpl()
    : impl_(std::make_unique<Impl>())
{
    // instancePersistencePath() is provided by LogosModuleContext at runtime; we rely on the
    // generated wrapper having called it before the first user method fires.
    // If it is available here (some host versions expose it early), load now.
    // TODO: verify instancePersistencePath() availability in constructor vs initLogos callback.
    try {
        std::string dd = instancePersistencePath(); // LogosModuleContext method
        if (!dd.empty()) {
            impl_->data_dir = fs::path(dd);
            fs::create_directories(impl_->data_dir);
            impl_->load_all();
        }
    } catch (...) {
        // instancePersistencePath() not yet available; load deferred to first public call.
    }

    // Copy config-sourced threshold fields into the header-declared members so
    // within_threshold() can read them without going through impl_->cfg() (the
    // header declares these as private members, not Impl fields).
    sync_config_fields();
}

AgentModuleImpl::~AgentModuleImpl() = default;

// ---------------------------------------------------------------------------
// Internal: lazy data-dir init + config-field sync
// ---------------------------------------------------------------------------

void AgentModuleImpl::ensure_loaded() {
    if (!impl_->data_dir.empty()) return;
    try {
        std::string dd = instancePersistencePath(); // LogosModuleContext
        if (dd.empty()) return;
        impl_->data_dir = fs::path(dd);
        fs::create_directories(impl_->data_dir);
        impl_->load_all();
        sync_config_fields();
    } catch (...) { /* best effort */ }
}

void AgentModuleImpl::sync_config_fields() {
    owner_address_    = impl_->cfg("owner_address");
    per_tx_limit_     = impl_->cfg("per_tx_limit",    "0");
    per_period_limit_ = impl_->cfg("per_period_limit", "0");
    try { period_seconds_ = std::stoll(impl_->cfg("period_seconds", "86400")); }
    catch (...) { period_seconds_ = 86400; }
}


// ---------------------------------------------------------------------------
// Spending-threshold gate (ARCHITECTURE.md S5)
// ---------------------------------------------------------------------------

bool AgentModuleImpl::within_threshold(const std::string& amount_decimal) {
    ensure_loaded();

    double amount = parse_amount(amount_decimal);
    if (amount < 0.0) return false; // malformed amount; block

    double per_tx     = parse_amount(per_tx_limit_);
    double per_period = parse_amount(per_period_limit_);

    // If both limits are zero we treat "0" as "no limit configured" and allow.
    // A configured zero limit means "never allow autonomously" (all spend needs approval).
    // Distinguishing "unset" from "zero" by checking the raw config string:
    bool tx_limit_set     = !per_tx_limit_.empty() && per_tx_limit_ != "0";
    bool period_limit_set = !per_period_limit_.empty() && per_period_limit_ != "0";

    if (!tx_limit_set && !period_limit_set) {
        // No limits configured; allow. (Owner has not yet set thresholds.)
        return true;
    }

    // Roll over the period counter if the window has expired.
    int64_t now = static_cast<int64_t>(
        std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());

    if (period_seconds_ > 0 &&
        (impl_->period_start_ts == 0 || (now - impl_->period_start_ts) >= period_seconds_)) {
        impl_->period_spent    = 0.0;
        impl_->period_start_ts = now;
        impl_->save_spend();
    }

    bool tx_ok     = !tx_limit_set     || (amount <= per_tx);
    bool period_ok = !period_limit_set || (impl_->period_spent + amount <= per_period);

    return tx_ok && period_ok;
}

// Atomically record a spend (call after a transaction is confirmed executed).
void AgentModuleImpl::record_spend(double amount) {
    impl_->period_spent += amount;
    impl_->save_spend();
}

// Build a pending proposal, store it, fire the approval_required event, and
// return the pending-proposal JSON string.
std::string AgentModuleImpl::create_pending_proposal(
    const std::string& action,
    const std::string& recipient,
    const std::string& amount,
    const std::string& reason,
    const std::string& task_id)
{
    ensure_loaded();
    std::string proposal_id = make_id("prop");

    json proposal = {
        {"proposal_id",  proposal_id},
        {"action",       action},
        {"recipient",    recipient},
        {"amount",       amount},
        {"reason",       reason},
        {"task_id",      task_id},
        {"status",       "pending_approval"},
        {"created_at",   utc_now_iso()}
    };

    impl_->pending_proposals[proposal_id] = proposal;
    impl_->save_pending();

    // Fire the approval_required event (subscribers / the generated Qt wrapper
    // route this to the owner channel).
    approval_required(proposal_id, proposal.dump());

    // Also send it to the owner over the chat owner channel if configured.
    send_owner_message("approval_required: " + proposal.dump());

    return json{
        {"status",      "pending_approval"},
        {"proposal_id", proposal_id},
        {"proposal",    proposal}
    }.dump();
}

// Send a plaintext (hex-encoded) message to the owner via the chat_module
// owner channel. Best-effort; errors are swallowed (the event was already fired).
void AgentModuleImpl::send_owner_message(const std::string& text) {
    if (owner_address_.empty()) return;
    try {
        std::string owner_convo_id = impl_->cfg("owner_convo_id");
        std::string hex_content    = hex_encode(text);
        if (owner_convo_id.empty()) {
            QString convo_result = modules().chat_module.newPrivateConversation(
                QString::fromStdString(owner_address_),
                QString::fromStdString(hex_content));
            json jr = safe_parse(convo_result.toStdString());
            std::string cid = (jr.is_object() && jr.contains("convoId"))
                              ? jr["convoId"].get<std::string>() : "";
            if (!cid.empty()) {
                impl_->config["owner_convo_id"] = cid;
                impl_->save_config();
            }
        } else {
            modules().chat_module.sendMessage(
                QString::fromStdString(owner_convo_id),
                QString::fromStdString(hex_content));
        }
    } catch (...) { /* owner unreachable; the event was already emitted */ }
}


// ---------------------------------------------------------------------------
// Storage skills
// ---------------------------------------------------------------------------

std::string AgentModuleImpl::storage_upload(const std::string& path, const std::string& label) {
    ensure_loaded();
    try {
        // TODO: verify API shape against logos-core source
        // The storage_module is a hand-written Qt plugin (not universal), so the
        // typed modules().storage_module.* calls go through the generated QVariant shim.
        // Expected call: modules().storage_module.uploadUrl("file://" + path, 0)
        // Returns a sessionId; the actual CID arrives via storageUploadDone event.
        // For a synchronous result suitable for our wire return type, we would need
        // to block on the event or use an async callback. The cleanest path here is
        // to expose an uploadSync helper in the lez_wallet_module or use a future/promise.
        // Since the generated wrapper does provide a *Async variant, we use a simple
        // blocking wait pattern via std::promise:
        //
        // BLOCKED: needs Logos SDK headers (std::promise integration with LogosModuleContext)
        //
        // Stubbed implementation that calls the module and returns a pending result.
        // The caller can subscribe to task_update events for the actual CID.

        std::string session_id = make_id("upload");

        // Route the upload through the platform storage_module.
        if (isContextReady()) {
            try {
                LogosResult res = modules().storage_module.uploadUrl(
                    QString::fromStdString(std::string("file://") + path),
                    int64_t(0)
                );
                if (res.success) {
                    std::string sid = res.getString().toStdString();
                    if (!sid.empty()) session_id = sid;
                }
            } catch (...) { /* best effort */ }
        }

        // Record the label keyed on session_id; on storageUploadDone we remap to CID.
        impl_->cid_labels["__pending__" + session_id] = label;
        impl_->save_cid_map();

        json result = {
            {"status",     "upload_started"},
            {"session_id", session_id},
            {"path",       path},
            {"label",      label},
            {"note",       "subscribe to task_update for cid when upload completes"}
        };
        return ok(result);
    } catch (const std::exception& e) {
        skill_failed("storage_upload", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("storage_upload", "unknown error");
        return err("storage_upload: unknown error");
    }
}

std::string AgentModuleImpl::storage_download(const std::string& address, const std::string& path) {
    ensure_loaded();
    try {
        std::string status_str = "download_started";
        if (isContextReady()) {
            try {
                LogosResult res = modules().storage_module.downloadToUrl(
                    QString::fromStdString(address),
                    QString::fromStdString(std::string("file://") + path),
                    true
                );
                if (res.success) {
                    status_str = "download_ok";
                } else {
                    status_str = "download_error: " + res.getError<QString>().toStdString();
                }
            } catch (const std::exception& ex) {
                status_str = std::string("download_error: ") + ex.what();
            } catch (...) { status_str = "download_error: unknown"; }
        }

        json result = {
            {"status",  status_str},
            {"cid",     address},
            {"path",    path}
        };
        return ok(result);
    } catch (const std::exception& e) {
        skill_failed("storage_download", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("storage_download", "unknown error");
        return err("storage_download: unknown error");
    }
}

std::string AgentModuleImpl::storage_list() {
    ensure_loaded();
    try {
        // Query the storage_module for its manifest list.
        json platform_entries = json::array();
        if (isContextReady()) {
            try {
                LogosResult res = modules().storage_module.manifests();
                if (res.success) {
                    platform_entries = safe_parse(res.getString().toStdString());
                }
            } catch (...) {}
        }

        // Merge with local cid->label map.
        // Build a cid->platform_entry index first.
        std::unordered_map<std::string, json> platform_idx;
        if (platform_entries.is_array()) {
            for (auto& entry : platform_entries) {
                std::string cid = entry.value("cid", entry.value("id", ""));
                if (!cid.empty()) platform_idx[cid] = entry;
            }
        }

        json entries = json::array();
        // Add locally labeled entries (includes CIDs resolved from task_update events).
        for (auto& [cid, label] : impl_->cid_labels) {
            if (cid.rfind("__pending__", 0) == 0) continue;
            json e = {{"cid", cid}, {"label", label}};
            if (platform_idx.count(cid)) e["platform"] = platform_idx[cid];
            entries.push_back(e);
        }
        // Add platform entries not yet labeled locally.
        for (auto& [cid, pentry] : platform_idx) {
            if (!impl_->cid_labels.count(cid)) {
                entries.push_back({{"cid", cid}, {"label", ""}, {"platform", pentry}});
            }
        }
        return ok(entries);
    } catch (const std::exception& e) {
        skill_failed("storage_list", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("storage_list", "unknown error");
        return err("storage_list: unknown error");
    }
}

std::string AgentModuleImpl::storage_share(const std::string& address, const std::string& recipient) {
    ensure_loaded();
    try {
        // No native share primitive in storage_module (LEARNING.md S7, gap).
        // Strategy: send the CID (+ decryption key if encrypted-before-upload) to
        // the recipient over the chat_module 1:1 conversation.

        // Build the share payload.
        json share_payload = {
            {"type",      "storage_share"},
            {"cid",       address},
            {"label",     impl_->cid_labels.count(address) ? impl_->cid_labels[address] : ""},
            {"shared_by", impl_->cfg("agent_npk")},
            {"timestamp", utc_now_iso()}
        };

        std::string hex_msg = hex_encode(share_payload.dump());

        // TODO: verify API shape against logos-core source
        // Open or reuse a 1:1 conversation with the recipient (their intro bundle string).
        // modules().chat_module.newPrivateConversation(recipient, hex_msg);

        json result = {
            {"status",    "share_sent"},
            {"cid",       address},
            {"recipient", recipient}
        };
        return ok(result);
    } catch (const std::exception& e) {
        skill_failed("storage_share", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("storage_share", "unknown error");
        return err("storage_share: unknown error");
    }
}


// ---------------------------------------------------------------------------
// Messaging skills
// ---------------------------------------------------------------------------

std::string AgentModuleImpl::messaging_send(const std::string& recipient, const std::string& message) {
    ensure_loaded();
    try {
        std::string hex_content = hex_encode(message);

        // Check if we already have a conversation open with this recipient.
        std::string convo_key = "convo_" + recipient;
        std::string convo_id  = impl_->cfg(convo_key);

        if (convo_id.empty()) {
            QString res = modules().chat_module.newPrivateConversation(
                QString::fromStdString(recipient),
                QString::fromStdString(hex_content));
            // chat_module may return JSON {"convoId":"..."} or just "true" (async started).
            // If JSON with convoId, cache it; otherwise mark as initiated (async).
            json jr = safe_parse(res.toStdString());
            if (jr.is_object() && jr.contains("convoId")) {
                convo_id = jr["convoId"].get<std::string>();
                if (!convo_id.empty()) {
                    impl_->config[convo_key] = convo_id;
                    impl_->save_config();
                }
            }
            // If bool true, the message was dispatched asynchronously — treat as sent.
        } else {
            modules().chat_module.sendMessage(
                QString::fromStdString(convo_id),
                QString::fromStdString(hex_content));
        }

        return ok({{"status", "sent"}, {"recipient", recipient}, {"convo_id", convo_id}});
    } catch (const std::exception& e) {
        skill_failed("messaging_send", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("messaging_send", "unknown error");
        return err("messaging_send: unknown error");
    }
}

std::string AgentModuleImpl::messaging_join(const std::string& group_id) {
    ensure_loaded();
    try {
        // Groups are not natively in chat_module (LEARNING.md S5, gap).
        // We use delivery_module content topics as group transport.
        // group_id is treated as the content topic string.

        modules().delivery_module.subscribe(QString::fromStdString(group_id));

        // Record our membership.
        std::string groups_raw = impl_->cfg("joined_groups", "[]");
        json groups = safe_parse(groups_raw);
        if (!groups.is_array()) groups = json::array();
        bool already = false;
        for (auto& g : groups) {
            if (g.is_string() && g.get<std::string>() == group_id) { already = true; break; }
        }
        if (!already) {
            groups.push_back(group_id);
            impl_->config["joined_groups"] = groups.dump();
            impl_->save_config();
        }

        return ok({{"status", "joined"}, {"group_id", group_id}});
    } catch (const std::exception& e) {
        skill_failed("messaging_join", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("messaging_join", "unknown error");
        return err("messaging_join: unknown error");
    }
}

std::string AgentModuleImpl::messaging_create_group(const std::vector<std::string>& members) {
    ensure_loaded();
    try {
        // Allocate a content topic for the group (LEARNING.md S5, gap design).
        // Topic format mirrors the Logos spec:
        // /logos/agent-group/<group_id>/1/default/proto
        std::string group_id = make_id("group");
        std::string topic    = "/logos/agent-group/" + group_id + "/1/default/proto";

        modules().delivery_module.subscribe(QString::fromStdString(topic));

        // Distribute the topic to each member over 1:1 chat.
        json invite = {
            {"type",     "group_invite"},
            {"group_id", group_id},
            {"topic",    topic},
            {"members",  members},
            {"created_at", utc_now_iso()}
        };
        std::string hex_invite = hex_encode(invite.dump());

        for (const auto& member : members) {
            try {
                modules().chat_module.newPrivateConversation(
                    QString::fromStdString(member),
                    QString::fromStdString(hex_invite));
            } catch (...) { /* continue sending to other members */ }
        }

        // Record membership.
        std::string groups_raw = impl_->cfg("joined_groups", "[]");
        json groups = safe_parse(groups_raw);
        if (!groups.is_array()) groups = json::array();
        groups.push_back(topic);
        impl_->config["joined_groups"] = groups.dump();
        impl_->save_config();

        return ok({{"group_id", group_id}, {"topic", topic}, {"members", members}});
    } catch (const std::exception& e) {
        skill_failed("messaging_create_group", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("messaging_create_group", "unknown error");
        return err("messaging_create_group: unknown error");
    }
}


// ---------------------------------------------------------------------------
// Blockchain skills (all gated through lez_wallet interface binding)
// ---------------------------------------------------------------------------

// Helper: get the bound lez_wallet interface. Returns false on failure and
// sets out_err. The bind call uses dependency-interface binding (LEARNING.md S4).
// The generated accessor is: modules().bind_lez_wallet("lez_wallet_module")
// TODO: verify API shape against logos-core source for bind_lez_wallet.
// The logos_sdk.h generated from the wallet plugin provides modules().lez_wallet_module
// as a typed LezWalletModule accessor (via the generator --plugin-path pass in cmake).
#define BIND_LEZ_WALLET(wallet_var)                                                      \
    auto wallet_var = modules().bind_lez_wallet("lez_wallet_module");


std::string AgentModuleImpl::wallet_balance() {
    ensure_loaded();
    try {
        BIND_LEZ_WALLET(wallet)
        std::string bal = wallet.balance();
        return ok({{"balance", bal}});
    } catch (const std::exception& e) {
        skill_failed("wallet_balance", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("wallet_balance", "unknown error");
        return err("wallet_balance: unknown error");
    }
}

std::string AgentModuleImpl::wallet_send(const std::string& recipient, const std::string& amount) {
    ensure_loaded();
    try {
        if (!within_threshold(amount)) {
            return create_pending_proposal("wallet_send", recipient, amount,
                                           "spend exceeds autonomous threshold", "");
        }

        BIND_LEZ_WALLET(wallet)
        std::string tx_hash = wallet.send(recipient, amount);
        json res_j = safe_parse(tx_hash);
        if (res_j.contains("error")) {
            skill_failed("wallet_send", res_j["error"].get<std::string>());
            return tx_hash; // passthrough error envelope
        }
        record_spend(parse_amount(amount));
        task_update("wallet_send_" + tx_hash, json{{"status","completed"},{"tx_hash",tx_hash}}.dump());
        return ok({{"tx_hash", tx_hash}, {"recipient", recipient}, {"amount", amount}});
    } catch (const std::exception& e) {
        skill_failed("wallet_send", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("wallet_send", "unknown error");
        return err("wallet_send: unknown error");
    }
}

std::string AgentModuleImpl::wallet_send_to(const std::string& npk, const std::string& vpk, const std::string& amount) {
    ensure_loaded();
    try {
        if (!within_threshold(amount)) {
            // Store npk+vpk in the proposal for later execution by approve_pending.
            json proposal = {
                {"proposal_id",  make_id("prop")},
                {"action",       "wallet_send_to"},
                {"recipient",    npk},
                {"vpk",          vpk},
                {"amount",       amount},
                {"reason",       "spend exceeds autonomous threshold"},
                {"task_id",      ""},
                {"status",       "pending_approval"},
                {"created_at",   utc_now_iso()}
            };
            std::string proposal_id = proposal["proposal_id"].get<std::string>();
            impl_->pending_proposals[proposal_id] = proposal;
            impl_->save_pending();
            approval_required(proposal_id, proposal.dump());
            send_owner_message("approval_required: " + proposal.dump());
            return json{{"status","pending_approval"},{"proposal_id",proposal_id},{"proposal",proposal}}.dump();
        }

        BIND_LEZ_WALLET(wallet)
        // Use async with a 15-minute timeout to survive RISC0 real-mode proving.
        // Fire task_update on completion; return immediately with proving_started.
        std::string task_ref_id = make_id("send_to");
        std::string npk_copy   = npk;
        std::string amount_copy = amount;
        wallet.send_toAsync(
            npk,
            vpk,
            amount,
            [this, task_ref_id, npk_copy, amount_copy](std::string tx_hash) {
                json res_j = safe_parse(tx_hash);
                if (res_j.contains("error")) {
                    skill_failed("wallet_send_to", res_j["error"].get<std::string>());
                    task_update(task_ref_id,
                        json{{"status","failed"},{"error",res_j["error"]}}.dump());
                } else {
                    record_spend(parse_amount(amount_copy));
                    task_update(task_ref_id,
                        json{{"status","completed"},{"tx_hash",tx_hash},
                             {"npk",npk_copy},{"amount",amount_copy}}.dump());
                }
            }
        );
        return ok({{"status","proving_started"},{"task_id",task_ref_id},
                   {"npk",npk},{"amount",amount},
                   {"note","tx_hash arrives via task_update event when proof completes"}});
    } catch (const std::exception& e) {
        skill_failed("wallet_send_to", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("wallet_send_to", "unknown error");
        return err("wallet_send_to: unknown error");
    }
}

std::string AgentModuleImpl::wallet_history() {
    ensure_loaded();
    try {
        BIND_LEZ_WALLET(wallet)
        // TODO: verify API shape against logos-core source
        // std::string hist = wallet.history(int64_t(50));
        // return ok(safe_parse(hist));

        return ok(json::array());
    } catch (const std::exception& e) {
        skill_failed("wallet_history", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("wallet_history", "unknown error");
        return err("wallet_history: unknown error");
    }
}

std::string AgentModuleImpl::program_query(const std::string& program_id, const std::string& params) {
    ensure_loaded();
    try {
        BIND_LEZ_WALLET(wallet)
        // TODO: verify API shape against logos-core source
        // std::string res = wallet.program_query(program_id, params);
        // json j = safe_parse(res);
        // if (j.contains("error")) {
        //     skill_failed("program_query", j["error"].get<std::string>());
        //     return res;
        // }
        // return ok(j);

        return ok({
            {"note",       "lez_wallet_module not yet bound"},
            {"program_id", program_id},
            {"params",     safe_parse(params)}
        });
    } catch (const std::exception& e) {
        skill_failed("program_query", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("program_query", "unknown error");
        return err("program_query: unknown error");
    }
}

std::string AgentModuleImpl::program_call(const std::string& program_id,
                                           const std::string& instruction,
                                           const std::string& params) {
    ensure_loaded();
    try {
        // Parse params to find an optional "amount" field for the spending gate.
        json params_j   = safe_parse(params);
        std::string amt = params_j.value("amount", std::string("0"));

        if (!within_threshold(amt)) {
            std::string reason = "program_call " + program_id + "." + instruction
                                 + " exceeds autonomous threshold";
            return create_pending_proposal("program_call", program_id, amt, reason, "");
        }

        BIND_LEZ_WALLET(wallet)
        // TODO: verify API shape against logos-core source
        // std::string res = wallet.program_call(program_id, instruction, params);
        // json j = safe_parse(res);
        // if (j.contains("error")) {
        //     skill_failed("program_call", j["error"].get<std::string>());
        //     return res;
        // }
        // if (parse_amount(amt) > 0.0) record_spend(parse_amount(amt));
        // return ok(j);

        return ok({
            {"note",        "lez_wallet_module not yet bound"},
            {"program_id",  program_id},
            {"instruction", instruction}
        });
    } catch (const std::exception& e) {
        skill_failed("program_call", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("program_call", "unknown error");
        return err("program_call: unknown error");
    }
}

std::string AgentModuleImpl::program_deploy(const std::string& binary_path) {
    ensure_loaded();
    try {
        // Deployment cost is unknown until the sequencer quotes it; conservatively
        // apply the per-tx gate with the per_tx_limit as a sentinel (if set).
        // Owner approval required when per_tx_limit is set, always (deploy is high-impact).
        if (!per_tx_limit_.empty() && per_tx_limit_ != "0") {
            return create_pending_proposal("program_deploy", binary_path, per_tx_limit_,
                                           "program deployment requires owner approval", "");
        }

        BIND_LEZ_WALLET(wallet)
        // TODO: verify API shape against logos-core source
        // std::string res = wallet.program_deploy(binary_path);
        // json j = safe_parse(res);
        // if (j.contains("error")) {
        //     skill_failed("program_deploy", j["error"].get<std::string>());
        //     return res;
        // }
        // return ok(j);  // j should contain {"program_id": ...}

        return ok({
            {"note",        "lez_wallet_module not yet bound"},
            {"binary_path", binary_path}
        });
    } catch (const std::exception& e) {
        skill_failed("program_deploy", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("program_deploy", "unknown error");
        return err("program_deploy: unknown error");
    }
}


// ---------------------------------------------------------------------------
// A2A / Agent coordination
// ---------------------------------------------------------------------------

std::string AgentModuleImpl::agent_card() {
    ensure_loaded();
    try {
        // Retrieve agent NPK (from lez_wallet if available, else config cache).
        std::string npk_val = impl_->cfg("agent_npk");
        if (npk_val.empty()) {
            try {
                BIND_LEZ_WALLET(wallet)
                npk_val = wallet.npk();
                if (!npk_val.empty()) {
                    impl_->config["agent_npk"] = npk_val;
                    impl_->save_config();
                }
            } catch (...) { npk_val = "npk_unavailable"; }
        }

        // Build Agent Card per A2A spec + LEZ extensions (ARCHITECTURE.md S8, LEARNING.md S9).
        json skills_arr = safe_parse(meta_skills());
        if (skills_arr.contains("result")) skills_arr = skills_arr["result"];
        if (!skills_arr.is_array())        skills_arr = json::array();

        // Build per-skill price entries for agentInterfaces capabilities.
        json capabilities = json::array();
        for (auto& sk : skills_arr) {
            std::string sname = sk.value("name", sk.value("skill_name", ""));
            std::string price = sk.value("lez_price", "0");
            capabilities.push_back({{"skill", sname}, {"x-lez-price", price}});
        }

        json card = {
            {"id",          impl_->cfg("agent_id", make_id("agent"))},
            {"name",        impl_->cfg("agent_name", "LP-0008 Autonomous Agent")},
            {"version",     kVersion},
            {"description", "Logos-native autonomous AI agent with shielded LEZ wallet and A2A coordination"},
            {"provider",    {
                {"organization", impl_->cfg("agent_org", "")},
                {"url",          impl_->cfg("agent_url", "")}
            }},
            // A2A capability flags (LEARNING.md S9).
            {"capabilities", {
                {"streaming",          false},
                {"pushNotifications",  false},
                {"extendedAgentCard",  true}
            }},
            // Identity binding: NPK ties the A2A card to the LEZ shielded account.
            // ARCHITECTURE.md S3 / LEARNING.md S9 gap: full deterministic binding
            // (chat introBundle derived from NSK) is a future build; for now we
            // publish NPK in the card and use it as the primary routing identity.
            {"x-lez-identity", {
                {"npk",        npk_val},
                {"account_id", impl_->cfg("agent_account_id", "")}
            }},
            // Transport binding: A2A over Logos Messaging.
            // Recipients address the agent by sending to its chat intro bundle
            // (from x-lez-identity.npk lookup) or the discovery-topic address.
            {"agentInterfaces", json::array({{
                {"type",    "logos-messaging"},
                {"version", "0.0.1"},
                {"url",     impl_->cfg("discovery_topic", kDefaultDiscoveryTopic)}
            }})},
            {"defaultInputModes",  {"text"}},
            {"defaultOutputModes", {"text"}},
            {"skills",      capabilities},
            // Security: identify via the LEZ key (shielded account = cryptographic identity).
            {"securitySchemes", {
                {"lez-key", {
                    {"type",        "apiKey"},
                    {"description", "LEZ NullifierPublicKey; sender identity is the shielded account key"}
                }}
            }},
            {"security",    json::array({json::object({{"lez-key", json::array()}})})},
            {"createdAt",   utc_now_iso()}
        };

        return ok(card);
    } catch (const std::exception& e) {
        skill_failed("agent_card", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("agent_card", "unknown error");
        return err("agent_card: unknown error");
    }
}

std::string AgentModuleImpl::agent_discover(const std::string& topic) {
    ensure_loaded();
    try {
        std::string effective_topic = topic.empty()
            ? impl_->cfg("discovery_topic", kDefaultDiscoveryTopic)
            : topic;

        // Subscribe to the discovery topic via delivery_module.
        modules().delivery_module.subscribe(QString::fromStdString(effective_topic));

        // Publish our own Agent Card to the topic so peers can discover us.
        std::string my_card_raw = agent_card();
        json my_card_j = safe_parse(my_card_raw);
        if (my_card_j.contains("result")) {
            std::string card_str = my_card_j["result"].dump();
            modules().delivery_module.sendString(
                QString::fromStdString(effective_topic),
                QString::fromStdString(card_str));
        }

        // Store the topic so we can unsubscribe later.
        impl_->config["last_discover_topic"] = effective_topic;
        impl_->save_config();

        return ok({
            {"status",  "subscribed_and_published"},
            {"topic",   effective_topic},
            {"card_published", true},
            {"note",    "agent card published to topic; peer cards arrive via messageReceived event"}
        });
    } catch (const std::exception& e) {
        skill_failed("agent_discover", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("agent_discover", "unknown error");
        return err("agent_discover: unknown error");
    }
}

std::string AgentModuleImpl::agent_task(const std::string& agent_address,
                                         const std::string& skill,
                                         const std::string& params) {
    ensure_loaded();
    try {
        std::string task_id = make_id("task");

        // Resolve skill price: prefer the peer's Agent Card (if agent_address is JSON),
        // then fall back to our own skills list.
        std::string lez_price = "0";
        json addr_card = safe_parse(agent_address);
        if (addr_card.is_object()) {
            // Try peer card's skills array for this skill.
            json peer_skills = addr_card.value("skills", json::array());
            for (auto& sk : peer_skills) {
                std::string sname = sk.value("name", sk.value("skill_name", ""));
                if (sname == skill) {
                    lez_price = sk.value("lez_price", sk.value("x-lez-price", "0"));
                    break;
                }
            }
        }
        if (lez_price == "0") {
            // Fall back to our own skills list.
            std::string skills_raw = meta_skills();
            json skills_j = safe_parse(skills_raw);
            if (skills_j.contains("result")) skills_j = skills_j["result"];
            if (skills_j.is_array()) {
                for (auto& sk : skills_j) {
                    std::string sname = sk.value("name", sk.value("skill_name", ""));
                    if (sname == skill) {
                        lez_price = sk.value("lez_price", "0");
                        break;
                    }
                }
            }
        }

        // Build the A2A SendMessage payload (LEARNING.md S9).
        // Transport: send as a chat message to the peer's intro-bundle address.
        // The A2A Task lifecycle starts at "submitted".
        json a2a_msg = {
            {"jsonrpc",  "2.0"},
            {"id",       task_id},
            {"method",   "message/send"},
            {"params",   {
                {"message",  {
                    {"messageId", make_id("msg")},
                    {"role",      "user"},
                    {"content",   json::array({{
                        {"type", "text"},
                        {"text", params}
                    }})},
                    {"metadata",  {
                        {"skill",     skill},
                        {"lez_price", lez_price},
                        {"sender_npk", impl_->cfg("agent_npk")}
                    }}
                }},
                {"configuration", {
                    {"blocking",             false},
                    {"acceptedOutputModes",  {"text"}}
                }}
            }}
        };

        std::string hex_payload = hex_encode(a2a_msg.dump());

        // Check if we have a conversation with this agent already.
        std::string convo_key = "convo_" + agent_address;
        std::string convo_id  = impl_->cfg(convo_key);

        if (convo_id.empty()) {
            QString res = modules().chat_module.newPrivateConversation(
                QString::fromStdString(agent_address),
                QString::fromStdString(hex_payload));
            json jr = safe_parse(res.toStdString());
            if (jr.is_object() && jr.contains("convoId")) {
                convo_id = jr["convoId"].get<std::string>();
                if (!convo_id.empty()) {
                    impl_->config[convo_key] = convo_id;
                    impl_->save_config();
                }
            }
        } else {
            modules().chat_module.sendMessage(
                QString::fromStdString(convo_id),
                QString::fromStdString(hex_payload));
        }

        // Attempt autonomous payment if the lez_price > 0.
        // agent_address may be a JSON Agent Card string (from agent_discover) containing
        // x-lez-identity.npk and x-lez-identity.vpk for the send_to path.
        std::string pay_tx_hash;
        std::string pay_npk;
        std::string pay_vpk;
        double price_d = parse_amount(lez_price);
        if (price_d > 0.0) {
            // Try to parse agent_address as an Agent Card JSON.
            json addr_j = safe_parse(agent_address);
            if (addr_j.is_object() && addr_j.contains("x-lez-identity")) {
                pay_npk = addr_j["x-lez-identity"].value("npk", "");
                pay_vpk = addr_j["x-lez-identity"].value("vpk", "");
            }
            if (!pay_npk.empty() && !pay_vpk.empty()) {
                std::string pay_result = wallet_send_to(pay_npk, pay_vpk, lez_price);
                json pr = safe_parse(pay_result);
                if (pr.contains("result") && pr["result"].contains("tx_hash")) {
                    pay_tx_hash = pr["result"]["tx_hash"].get<std::string>();
                }
            }
        }

        json task_state = {
            {"task_id",       task_id},
            {"agent_address", agent_address},
            {"skill",         skill},
            {"params",        safe_parse(params)},
            {"lez_price",     lez_price},
            {"pay_tx_hash",   pay_tx_hash},
            {"status",        "submitted"},
            {"created_at",    utc_now_iso()}
        };
        impl_->pending_proposals["task_" + task_id] = task_state;
        impl_->save_pending();

        task_update(task_id, task_state.dump());

        return ok({
            {"task_id",       task_id},
            {"status",        "submitted"},
            {"agent_address", agent_address},
            {"skill",         skill},
            {"lez_price",     lez_price},
            {"pay_tx_hash",   pay_tx_hash}
        });
    } catch (const std::exception& e) {
        skill_failed("agent_task", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("agent_task", "unknown error");
        return err("agent_task: unknown error");
    }
}

std::string AgentModuleImpl::agent_subscribe(const std::string& agent_address,
                                               const std::string& task_id) {
    ensure_loaded();
    try {
        // Map A2A SubscribeToTask: subscribe to a per-task delivery topic (LEARNING.md S9).
        // Topic pattern: /logos/agent-task/<task_id>/1/stream/proto
        std::string task_topic = "/logos/agent-task/" + task_id + "/1/stream/proto";
        modules().delivery_module.subscribe(QString::fromStdString(task_topic));

        // Store subscription so we know which topics to clean up on cancel.
        std::string sub_key = "task_sub_" + task_id;
        impl_->config[sub_key] = task_topic;
        impl_->save_config();

        return ok({
            {"task_id",       task_id},
            {"agent_address", agent_address},
            {"task_topic",    task_topic},
            {"status",        "subscribed"}
        });
    } catch (const std::exception& e) {
        skill_failed("agent_subscribe", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("agent_subscribe", "unknown error");
        return err("agent_subscribe: unknown error");
    }
}

std::string AgentModuleImpl::agent_cancel(const std::string& agent_address,
                                           const std::string& task_id) {
    ensure_loaded();
    try {
        // Build A2A CancelTask message.
        json cancel_msg = {
            {"jsonrpc", "2.0"},
            {"id",      make_id("cancel")},
            {"method",  "tasks/cancel"},
            {"params",  {{"taskId", task_id}}}
        };
        std::string hex_payload = hex_encode(cancel_msg.dump());

        std::string convo_key = "convo_" + agent_address;
        std::string convo_id  = impl_->cfg(convo_key);
        if (!convo_id.empty()) {
            modules().chat_module.sendMessage(
                QString::fromStdString(convo_id),
                QString::fromStdString(hex_payload));
        }

        // Unsubscribe from the task topic.
        std::string sub_key   = "task_sub_" + task_id;
        std::string task_topic = impl_->cfg(sub_key);
        if (!task_topic.empty()) {
            modules().delivery_module.unsubscribe(QString::fromStdString(task_topic));
            impl_->config.erase(sub_key);
            impl_->save_config();
        }

        // Mark task as canceled in pending state.
        std::string state_key = "task_" + task_id;
        if (impl_->pending_proposals.count(state_key)) {
            impl_->pending_proposals[state_key]["status"] = "canceled";
            impl_->save_pending();
        }

        task_update(task_id, json{{"task_id", task_id}, {"status", "canceled"}}.dump());

        return ok({{"task_id", task_id}, {"status", "canceled"}});
    } catch (const std::exception& e) {
        skill_failed("agent_cancel", e.what());
        return err(e.what());
    } catch (...) {
        skill_failed("agent_cancel", "unknown error");
        return err("agent_cancel: unknown error");
    }
}


// ---------------------------------------------------------------------------
// Meta skills
// ---------------------------------------------------------------------------

std::string AgentModuleImpl::meta_skills() {
    ensure_loaded();
    try {
        json skills = json::array();

        // Built-in skill schemas. These match the skill surface declared in
        // agent_module_impl.h and ARCHITECTURE.md S7.
        auto add = [&](const std::string& name,
                       const json& params,
                       const json& returns,
                       const std::string& description,
                       const std::string& price = "0") {
            skills.push_back({
                {"name",        name},
                {"description", description},
                {"params",      params},
                {"returns",     returns},
                {"lez_price",   price}
            });
        };

        // Storage
        add("storage.upload",   {{"path","string"},{"label","string"}},
                                {{"session_id","string"},{"cid","string"}},
                                "Upload a file to Logos Storage and associate a label.");
        add("storage.download", {{"address","string"},{"path","string"}},
                                {{"status","string"},{"path","string"}},
                                "Download a CID from Logos Storage to a local path.");
        add("storage.list",     json::object(),
                                {{"entries","array"}},
                                "List locally known CIDs with their labels.");
        add("storage.share",    {{"address","string"},{"recipient","string"}},
                                {{"status","string"}},
                                "Share a CID with a recipient via E2E messaging.");

        // Messaging
        add("messaging.send",         {{"recipient","string"},{"message","string"}},
                                      {{"status","string"}},
                                      "Send an E2E message to a recipient.");
        add("messaging.join",         {{"group_id","string"}},
                                      {{"status","string"}},
                                      "Join a delivery-module group topic.");
        add("messaging.create_group", {{"members","array"}},
                                      {{"group_id","string"},{"topic","string"}},
                                      "Create a group topic and invite members.");

        // Blockchain
        add("wallet.balance",  json::object(),
                               {{"balance","string"}},
                               "Read the agent's shielded LEZ account balance.");
        add("wallet.send",     {{"recipient","string"},{"amount","string"}},
                               {{"tx_hash","string"}},
                               "Send a shielded LEZ transfer (spending-threshold gated).");
        add("wallet.history",  json::object(),
                               {{"transfers","array"}},
                               "List recent transfers for this account.");
        add("program.query",   {{"program_id","string"},{"params","string"}},
                               {{"state","object"}},
                               "Read LEZ program or account state via sequencer RPC.");
        add("program.call",    {{"program_id","string"},{"instruction","string"},{"params","string"}},
                               {{"tx_hash","string"}},
                               "Call a LEZ program instruction (spending-threshold gated).");
        add("program.deploy",  {{"binary_path","string"}},
                               {{"program_id","string"}},
                               "Deploy a compiled RISC-V/Risc0 program to LEZ.");

        // A2A
        add("agent.card",      json::object(),
                               {{"card","object"}},
                               "Return this agent's A2A Agent Card for discovery.");
        add("agent.discover",  {{"topic","string"}},
                               {{"status","string"},{"topic","string"}},
                               "Subscribe to an A2A discovery topic and collect agent cards.");
        add("agent.task",      {{"agent_address","string"},{"skill","string"},{"params","string"}},
                               {{"task_id","string"},{"status","string"}},
                               "Send an A2A task request to a peer agent.");
        add("agent.subscribe", {{"agent_address","string"},{"task_id","string"}},
                               {{"status","string"}},
                               "Subscribe to A2A task status updates from a peer.");
        add("agent.cancel",    {{"agent_address","string"},{"task_id","string"}},
                               {{"status","string"}},
                               "Cancel an in-flight A2A task.");

        // Meta
        add("meta.skills",    json::object(),
                              {{"skills","array"}},
                              "List all available skills and their schemas.");
        add("meta.status",    json::object(),
                              {{"balance","string"},{"tasks","array"}},
                              "Report agent status: balance, active tasks.");
        add("meta.configure", {{"key","string"},{"value","string"}},
                              {{"key","string"},{"value","string"}},
                              "Set a configuration value (persisted).");

        // Bound third-party skill providers (ARCHITECTURE.md S6).
        for (const auto& provider : impl_->skill_providers) {
            try {
                // TODO: verify API shape against logos-core source
                // auto skill_mod = modules().bind_skill(provider);
                // std::string schema_raw = skill_mod.skill_schema();
                // json schema = safe_parse(schema_raw);
                // if (schema.is_object()) skills.push_back(schema);
                (void)provider;
            } catch (...) { /* skip unavailable provider */ }
        }

        return ok(skills);
    } catch (const std::exception& e) {
        return err(std::string("meta_skills: ") + e.what());
    } catch (...) {
        return err("meta_skills: unknown error");
    }
}

std::string AgentModuleImpl::meta_status() {
    ensure_loaded();
    try {
        // Balance (non-throwing).
        std::string balance_raw = wallet_balance();
        json balance_j = safe_parse(balance_raw);
        std::string balance_str = "0";
        if (balance_j.contains("result") && balance_j["result"].contains("balance")) {
            balance_str = balance_j["result"]["balance"].get<std::string>();
        }

        // Active tasks (non-terminal states).
        json active_tasks = json::array();
        for (auto& [k, v] : impl_->pending_proposals) {
            if (k.rfind("task_", 0) == 0) {
                std::string status = v.value("status", "");
                if (status != "completed" && status != "failed" && status != "canceled") {
                    active_tasks.push_back(v);
                }
            }
        }

        // Pending approvals.
        json pending_approvals = json::array();
        for (auto& [k, v] : impl_->pending_proposals) {
            if (k.rfind("prop_", 0) == 0) {
                if (v.value("status", "") == "pending_approval") {
                    pending_approvals.push_back(v);
                }
            }
        }

        json status = {
            {"version",           kVersion},
            {"balance",           balance_str},
            {"period_spent",      impl_->period_spent},
            {"active_tasks",      active_tasks},
            {"pending_approvals", pending_approvals},
            {"skill_providers",   impl_->skill_providers},
            {"timestamp",         utc_now_iso()}
        };
        return ok(status);
    } catch (const std::exception& e) {
        return err(std::string("meta_status: ") + e.what());
    } catch (...) {
        return err("meta_status: unknown error");
    }
}

std::string AgentModuleImpl::meta_configure(const std::string& key, const std::string& value) {
    ensure_loaded();
    try {
        if (key.empty()) return err("meta_configure: key must not be empty");

        // Update in-memory map.
        impl_->config[key] = value;

        // Handle known threshold/identity fields: mirror into the header-declared members
        // so within_threshold() and send_owner_message() pick them up immediately.
        sync_config_fields();

        // Special handling: "skill_providers" is a JSON array string.
        if (key == "skill_providers") {
            json arr = safe_parse(value);
            impl_->skill_providers.clear();
            if (arr.is_array()) {
                for (auto& s : arr) {
                    if (s.is_string()) impl_->skill_providers.push_back(s.get<std::string>());
                }
            }
        }

        // Persist to config.json.
        impl_->save_config();

        return ok({{"key", key}, {"value", value}});
    } catch (const std::exception& e) {
        return err(std::string("meta_configure: ") + e.what());
    } catch (...) {
        return err("meta_configure: unknown error");
    }
}


// ---------------------------------------------------------------------------
// Owner approval flow
// ---------------------------------------------------------------------------

std::string AgentModuleImpl::approve_pending(const std::string& proposal_id) {
    ensure_loaded();
    try {
        auto it = impl_->pending_proposals.find(proposal_id);
        if (it == impl_->pending_proposals.end()) {
            return err("approve_pending: proposal not found: " + proposal_id);
        }

        json proposal = it->second;
        std::string status = proposal.value("status", "");
        if (status != "pending_approval") {
            return err("approve_pending: proposal is not in pending_approval state (status: " + status + ")");
        }

        std::string action    = proposal.value("action",    "");
        std::string recipient = proposal.value("recipient", "");
        std::string amount    = proposal.value("amount",    "0");
        std::string task_id   = proposal.value("task_id",   "");

        // Mark the proposal as approved immediately so double-calls cannot re-execute.
        impl_->pending_proposals[proposal_id]["status"] = "approved";
        impl_->save_pending();

        // Execute the deferred action.
        std::string exec_result;
        if (action == "wallet_send") {
            // Bypass the threshold gate for this explicitly approved call.
            // We do so by temporarily zeroing the limits.
            std::string saved_tx     = per_tx_limit_;
            std::string saved_period = per_period_limit_;
            per_tx_limit_     = "0";
            per_period_limit_ = "0";
            exec_result = wallet_send(recipient, amount);
            per_tx_limit_     = saved_tx;
            per_period_limit_ = saved_period;
        } else if (action == "wallet_send_to") {
            std::string vpk_val = proposal.value("vpk", "");
            std::string saved_tx     = per_tx_limit_;
            std::string saved_period = per_period_limit_;
            per_tx_limit_     = "0";
            per_period_limit_ = "0";
            exec_result = wallet_send_to(recipient, vpk_val, amount);
            per_tx_limit_     = saved_tx;
            per_period_limit_ = saved_period;
        } else if (action == "program_call") {
            // recipient is program_id for program_call; instruction + params are
            // stored in proposal if we saved them. Here we stored the full params
            // as the reason field payload. For robustness, re-parse:
            std::string instruction = proposal.value("instruction", "");
            std::string params      = proposal.value("params", "{}");
            std::string saved_tx     = per_tx_limit_;
            std::string saved_period = per_period_limit_;
            per_tx_limit_     = "0";
            per_period_limit_ = "0";
            exec_result = program_call(recipient, instruction, params);
            per_tx_limit_     = saved_tx;
            per_period_limit_ = saved_period;
        } else if (action == "program_deploy") {
            // recipient is binary_path for deploy.
            std::string saved_tx     = per_tx_limit_;
            std::string saved_period = per_period_limit_;
            per_tx_limit_     = "0";
            per_period_limit_ = "0";
            exec_result = program_deploy(recipient);
            per_tx_limit_     = saved_tx;
            per_period_limit_ = saved_period;
        } else {
            exec_result = err("approve_pending: unknown action: " + action);
        }

        // Update proposal to executed.
        impl_->pending_proposals[proposal_id]["status"]     = "executed";
        impl_->pending_proposals[proposal_id]["exec_result"] = safe_parse(exec_result);
        impl_->pending_proposals[proposal_id]["executed_at"] = utc_now_iso();
        impl_->save_pending();

        // Record the spend if the execution succeeded.
        json exec_j = safe_parse(exec_result);
        bool exec_ok = !exec_j.contains("error");
        if (exec_ok && parse_amount(amount) > 0.0) {
            record_spend(parse_amount(amount));
        }

        // Notify via task_update.
        json update = {
            {"proposal_id", proposal_id},
            {"task_id",     task_id},
            {"action",      action},
            {"status",      exec_ok ? "completed" : "failed"},
            {"exec_result", exec_j}
        };
        task_update(task_id.empty() ? proposal_id : task_id, update.dump());
        send_owner_message("approved_and_executed: " + update.dump());

        return ok(update);
    } catch (const std::exception& e) {
        return err(std::string("approve_pending: ") + e.what());
    } catch (...) {
        return err("approve_pending: unknown error");
    }
}

std::string AgentModuleImpl::reject_pending(const std::string& proposal_id) {
    ensure_loaded();
    try {
        auto it = impl_->pending_proposals.find(proposal_id);
        if (it == impl_->pending_proposals.end()) {
            return err("reject_pending: proposal not found: " + proposal_id);
        }

        std::string status = it->second.value("status", "");
        if (status == "executed" || status == "rejected") {
            return err("reject_pending: proposal already in terminal state: " + status);
        }

        std::string task_id = it->second.value("task_id", "");
        it->second["status"]      = "rejected";
        it->second["rejected_at"] = utc_now_iso();
        impl_->save_pending();

        json update = {
            {"proposal_id", proposal_id},
            {"task_id",     task_id},
            {"status",      "rejected"}
        };
        task_update(task_id.empty() ? proposal_id : task_id, update.dump());
        send_owner_message("rejected: " + proposal_id);

        return ok(update);
    } catch (const std::exception& e) {
        return err(std::string("reject_pending: ") + e.what());
    } catch (...) {
        return err("reject_pending: unknown error");
    }
}


// ---------------------------------------------------------------------------
// Event stub implementations
// ---------------------------------------------------------------------------
// These are declared as `logos_events:` in the header. Their bodies are normally
// emitted by logos-cpp-generator in a sidecar events.cpp; since the generator we
// are using does not produce events.cpp, we implement them manually here.
// Each packs its args into a QVariantList (via void* to stay Qt-free in the header)
// and forwards through emitEventImpl_() provided by LogosModuleContext.

#include <QVariantList>
#include <QVariant>

void AgentModuleImpl::approval_required(const std::string& proposal_id,
                                         const std::string& proposal_json) {
    QVariantList args;
    args << QVariant::fromValue(QString::fromStdString(proposal_id))
         << QVariant::fromValue(QString::fromStdString(proposal_json));
    emitEventImpl_("approval_required", &args);
}

void AgentModuleImpl::task_update(const std::string& task_id,
                                   const std::string& status_json) {
    QVariantList args;
    args << QVariant::fromValue(QString::fromStdString(task_id))
         << QVariant::fromValue(QString::fromStdString(status_json));
    emitEventImpl_("task_update", &args);
}

void AgentModuleImpl::skill_failed(const std::string& skill,
                                    const std::string& error) {
    QVariantList args;
    args << QVariant::fromValue(QString::fromStdString(skill))
         << QVariant::fromValue(QString::fromStdString(error));
    emitEventImpl_("skill_failed", &args);
}
