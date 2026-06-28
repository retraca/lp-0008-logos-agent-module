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
#include "logos_lp_client.h"   // raw event subscribe (bypasses lossy generated onMessageReceived)

#include <nlohmann/json.hpp>
#include <memory>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <thread>
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

// F8: process-global discovery state. The lp_subscribe handler (registered in
// agent_discover) and meta_status can run on different AgentModuleImpl instances
// in the same host process, so the discovered peers must live outside impl_ to be
// visible across them. Isolation model: Logos Core runs ONE agent_module per host
// process (logos_host_qt --name agent_module), so this global is scoped to a single
// agent identity — it is not shared across tenants. (If a future host multiplexes
// several agents in one process, this must move to per-identity state.) The map is
// bounded at insert time (see kMaxDiscoveredPeers) to prevent discovery-flood DoS.
static std::unordered_map<std::string, nlohmann::json> g_discovered_peers;
static std::mutex g_peers_mu;

// Minimal RFC 4648 base64 decoder. The delivery messageReceived payload arrives
// wrapped as {"_bytes":"<base64 of the card JSON>"}; decode it to recover the card.
inline std::string agent_b64_decode(const std::string& in) {
    static const std::string T =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out; int val = 0, bits = -8;
    for (unsigned char c : in) {
        if (c == '=') break;
        auto p = T.find(c);
        if (p == std::string::npos) continue;
        val = (val << 6) + static_cast<int>(p); bits += 6;
        if (bits >= 0) { out.push_back(static_cast<char>((val >> bits) & 0xFF)); bits -= 8; }
    }
    return out;
}

// Module version, mirrored from metadata.json.
constexpr const char* kVersion = "0.0.1";

// File names written into the module data directory.
constexpr const char* kConfigFile   = "config.json";
constexpr const char* kSpendFile    = "spend_state.json";
constexpr const char* kPendingFile  = "pending_proposals.json";
constexpr const char* kCidMapFile   = "cid_labels.json";

// A2A discovery content topic (overridable via meta_configure "discovery_topic").
// MUST be a valid Waku autosharding content topic: /<app>/<version-NUMBER>/<name>/<enc>.
// The version segment has to be numeric or Waku rejects the publish with
// "generation should be a numeric value" (see F8_DISCOVERY_FIX.md).
constexpr const char* kDefaultDiscoveryTopic = "/logos/1/agent-discovery/proto";

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
    // Config values can arrive JSON-quoted (e.g. the spending limits are stored as "50").
    // Strip a single pair of surrounding double-quotes before parsing so the threshold
    // gate sees a real number instead of failing to parse and blocking every spend.
    std::string t = s;
    if (t.size() >= 2 && t.front() == '"' && t.back() == '"') {
        t = t.substr(1, t.size() - 2);
    }
    if (t.empty()) return -1.0;
    try {
        return std::stod(t);
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

    // --- discovered peer agents (in-memory; keyed by peer npk) ---
    // Populated by the delivery_module "messageReceived" handler when peer
    // Agent Cards arrive on the discovery topic (F8: the agent ingests other
    // agents' cards instead of only publishing its own).
    std::unordered_map<std::string, json> discovered_peers;
    bool discovery_handler_registered = false;
    // The peer-card handler runs on the delivery event-dispatch thread, while
    // agent_discover reads discovered_peers on the RPC thread. Guard both with
    // this mutex (concurrent map access is otherwise an uncatchable crash).
    std::mutex peers_mu;
    // Raw delivery event subscription: the generated onMessageReceived coerces
    // the byte payload to an empty JSON object, so we subscribe to the raw
    // "messageReceived" event via LpClient and decode the payload ourselves.
    // Both must outlive the subscription (LpSubscription unsubscribes on destroy).
    std::unique_ptr<logos::LpClient> disc_client;
    logos::LpSubscription disc_sub;

    // --- storage upload completion (F9 storage round-trip) ---
    // uploadUrl() returns a sessionId; the CID arrives later via the
    // storage_module "storageUploadDone" event. We subscribe to that event,
    // remap the pending label to the resolved CID, and record sessionId->CID so
    // storage_upload can return the real content address synchronously.
    std::unique_ptr<logos::LpClient> store_client;
    logos::LpSubscription store_sub;
    bool storage_handler_registered = false;
    std::unordered_map<std::string, std::string> session_cid; // sessionId -> CID
    std::mutex storage_mu;

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

    // Fire the approval_required event (subscribers / the generated Qt wrapper
    // route this to the owner channel).
    approval_required(proposal_id, proposal.dump());

    // Reliability (R2): the spend is held and is NOT executed without approval,
    // whether or not the owner can be reached. Try to notify the owner over the
    // Logos Messaging owner channel, retrying a few times, and record whether the
    // owner was reached on the proposal so a failure-to-notify is reported (it is
    // visible in pending_proposals / meta_status). The held spend never executes here.
    constexpr int kMaxNotifyAttempts = 3;
    bool notified = false;
    int  attempts = 0;
    for (; attempts < kMaxNotifyAttempts && !notified; ++attempts) {
        notified = send_owner_message("approval_required: " + proposal.dump());
    }
    proposal["notified"]        = notified;
    proposal["notify_attempts"] = attempts;
    // status stays "pending_approval" so the owner can still approve it once
    // reachable; the notify outcome is reported via the "notified" field.

    impl_->pending_proposals[proposal_id] = proposal;
    impl_->save_pending();

    return json{
        {"status",      "pending_approval"},
        {"proposal_id", proposal_id},
        {"notified",    notified},
        {"proposal",    proposal}
    }.dump();
}

// Send a plaintext (hex-encoded) message to the owner via the chat_module
// owner channel. Returns true only if the message reached the owner channel, so
// callers can detect an unreachable owner (the approval_required event is fired
// separately, independent of this best-effort delivery).
bool AgentModuleImpl::send_owner_message(const std::string& text) {
    if (owner_address_.empty()) return false;
    try {
        std::string owner_convo_id = impl_->cfg("owner_convo_id");
        std::string hex_content    = hex_encode(text);
        if (owner_convo_id.empty()) {
            return modules().chat_module.newPrivateConversation(
                owner_address_,
                hex_content);
        }
        modules().chat_module.sendMessage(
            owner_convo_id,
            hex_content);
        return true;
    } catch (...) {
        return false; // owner unreachable; the event was already emitted
    }
}


// ---------------------------------------------------------------------------
// Storage skills
// ---------------------------------------------------------------------------

// Register the storage_module "storageUploadDone" subscription once. The event
// carries (success, sessionId, cid); we record sessionId->CID and remap the
// pending label to the resolved content address. Runs on the storage event
// thread, so it shares impl_->storage_mu with the upload poll below.
void AgentModuleImpl::ensure_storage_subscription() {
    if (impl_->storage_handler_registered) return;
    try {
        impl_->store_client = std::make_unique<logos::LpClient>("storage_module", "agent_module");
        impl_->store_sub = impl_->store_client->subscribe("storageUploadDone",
            [this](nlohmann::json a) {
                try {
                    if (!a.is_array() || a.size() < 3) return;
                    bool ok_up        = a[0].is_boolean() ? a[0].get<bool>() : false;
                    std::string sid   = a[1].is_string()  ? a[1].get<std::string>() : "";
                    std::string cid   = a[2].is_string()  ? a[2].get<std::string>() : "";
                    if (!ok_up || sid.empty() || cid.empty()) return;
                    std::lock_guard<std::mutex> lk(impl_->storage_mu);
                    impl_->session_cid[sid] = cid;
                    auto it = impl_->cid_labels.find("__pending__" + sid);
                    if (it != impl_->cid_labels.end()) {
                        impl_->cid_labels[cid] = it->second; // CID -> label
                        impl_->cid_labels.erase(it);
                        impl_->save_cid_map();
                    }
                } catch (...) { /* ignore malformed events */ }
            });
        impl_->storage_handler_registered = true;
    } catch (...) { /* subscription unavailable; upload still returns the sessionId */ }
}

std::string AgentModuleImpl::storage_upload(const std::string& path, const std::string& label) {
    ensure_loaded();
    try {
        // Subscribe to storageUploadDone before uploading so we catch the CID.
        ensure_storage_subscription();

        std::string session_id = make_id("upload");

        // Route the upload through the platform storage_module (Logos Storage / Codex).
        if (isContextReady()) {
            try {
                StdLogosResult res = modules().storage_module.uploadUrl(
                    std::string("file://") + path,
                    int64_t(65536) // storage requires a positive chunk size
                );
                if (res.success) {
                    std::string sid = res.value.is_string() ? res.value.get<std::string>() : "";
                    if (!sid.empty()) session_id = sid;
                }
            } catch (...) { /* best effort */ }
        }

        // Record the label against the pending session; the storageUploadDone
        // handler remaps it to the CID when the upload completes.
        {
            std::lock_guard<std::mutex> lk(impl_->storage_mu);
            impl_->cid_labels["__pending__" + session_id] = label;
        }
        impl_->save_cid_map();

        // Wait (bounded) for the storageUploadDone event to deliver the CID, so
        // the skill can return the real content address. The event fires on the
        // storage event thread, so polling here does not deadlock.
        // Bounded poll kept well under the inter-module RPC timeout (~20s); a
        // small file completes in well under a second.
        std::string cid;
        for (int i = 0; i < 24 && cid.empty(); ++i) {
            {
                std::lock_guard<std::mutex> lk(impl_->storage_mu);
                auto it = impl_->session_cid.find(session_id);
                if (it != impl_->session_cid.end()) cid = it->second;
            }
            if (cid.empty()) std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }

        if (!cid.empty()) {
            return ok({{"status", "stored"}, {"cid", cid}, {"label", label}, {"path", path}});
        }
        // Upload accepted but the CID has not arrived yet; the label is pending
        // and storage_list will show the CID once storageUploadDone fires.
        return ok({{"status", "upload_started"}, {"session_id", session_id},
                   {"label", label}, {"path", path},
                   {"note", "cid will appear in storage_list when the upload completes"}});
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
                StdLogosResult res = modules().storage_module.downloadToUrl(
                    address,
                    std::string("file://") + path,
                    true,
                    int64_t(65536)
                );
                if (res.success) {
                    status_str = "download_ok";
                } else {
                    status_str = "download_error: " + res.error;
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
                StdLogosResult res = modules().storage_module.manifests();
                if (res.success) {
                    platform_entries = res.value.is_string()
                        ? safe_parse(res.value.get<std::string>())
                        : res.value;
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

        // Deliver the share payload to the recipient over the agent's 1:1 chat
        // conversation, reusing the working messaging_send path (which opens/reuses
        // the conversation and hex-encodes the body).
        std::string send_res = messaging_send(recipient, share_payload.dump());
        json sj = safe_parse(send_res);
        if (sj.is_object() && sj.contains("error")) {
            skill_failed("storage_share", sj.value("error", std::string("share delivery failed")));
            return send_res; // passthrough error envelope
        }

        json result = {
            {"status",    "share_sent"},
            {"cid",       address},
            {"recipient", recipient},
            {"delivery",  sj}
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
            modules().chat_module.newPrivateConversation(
                recipient,
                hex_content);
        } else {
            modules().chat_module.sendMessage(
                convo_id,
                hex_content);
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

        modules().delivery_module.subscribe(group_id);

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

        modules().delivery_module.subscribe(topic);

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
                    member,
                    hex_invite);
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
            approval_required(proposal_id, proposal.dump());
            // Reliability (R2): the over-threshold spend is held and NOT executed,
            // whether or not the owner can be reached. Retry the owner notification
            // and record whether it was delivered so a failure-to-notify is reported.
            constexpr int kMaxNotifyAttempts = 3;
            bool notified = false; int attempts = 0;
            for (; attempts < kMaxNotifyAttempts && !notified; ++attempts) {
                notified = send_owner_message("approval_required: " + proposal.dump());
            }
            proposal["notified"]        = notified;
            proposal["notify_attempts"] = attempts;
            impl_->pending_proposals[proposal_id] = proposal;
            impl_->save_pending();
            return json{{"status","pending_approval"},{"proposal_id",proposal_id},{"notified",notified},{"proposal",proposal}}.dump();
        }

        BIND_LEZ_WALLET(wallet)
        // Synchronous send through the wallet module. The sync binding is the one that
        // actually delivers over the module RPC (the async variant never fires); under
        // real proving the call can exceed the inter-module RPC window, but the wallet
        // still settles the transfer and the new balance shows on the next sync.
        std::string tx_hash = wallet.send_to(npk, vpk, amount);
        json res_j = safe_parse(tx_hash);
        if (res_j.is_object() && res_j.contains("error")) {
            skill_failed("wallet_send_to", res_j["error"].get<std::string>());
            return tx_hash; // passthrough error envelope
        }
        record_spend(parse_amount(amount));
        task_update("send_to_" + tx_hash, json{{"status","completed"},{"tx_hash",tx_hash},{"npk",npk},{"amount",amount}}.dump());
        return ok({{"tx_hash", tx_hash}, {"recipient_npk", npk}, {"amount", amount}});
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
        std::string hist = wallet.history("50");
        json j = safe_parse(hist);
        if (j.is_object() && j.contains("error")) {
            skill_failed("wallet_history", j["error"].get<std::string>());
            return hist; // passthrough error envelope
        }
        return ok({{"history", j}});
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
        std::string res = wallet.program_query(program_id, params);
        json j = safe_parse(res);
        if (j.is_object() && j.contains("error")) {
            skill_failed("program_query", j["error"].get<std::string>());
            return res; // passthrough error envelope
        }
        return ok(j.is_object() ? j : json{{"result", j}});
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
        std::string res = wallet.program_call(program_id, instruction, params);
        json j = safe_parse(res);
        if (j.is_object() && j.contains("error")) {
            skill_failed("program_call", j["error"].get<std::string>());
            return res; // passthrough error envelope
        }
        if (parse_amount(amt) > 0.0) record_spend(parse_amount(amt));
        return ok(j.is_object() ? j : json{{"result", j}});
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
        std::string res = wallet.program_deploy(binary_path);
        json j = safe_parse(res);
        if (j.is_object() && j.contains("error")) {
            skill_failed("program_deploy", j["error"].get<std::string>());
            return res; // passthrough error envelope
        }
        return ok(j.is_object() ? j : json{{"result", j}}); // j should contain {"program_id": ...}
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
        std::string vpk_val = impl_->cfg("agent_vpk");
        if (npk_val.empty() || vpk_val.empty()) {
            try {
                BIND_LEZ_WALLET(wallet)
                if (npk_val.empty()) npk_val = wallet.npk();
                if (vpk_val.empty()) vpk_val = wallet.vpk();
                if (!npk_val.empty()) impl_->config["agent_npk"] = npk_val;
                if (!vpk_val.empty()) impl_->config["agent_vpk"] = vpk_val;
                impl_->save_config();
            } catch (...) { if (npk_val.empty()) npk_val = "npk_unavailable"; }
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
                {"vpk",        vpk_val},
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

        // F8: register a one-time handler that ingests peer Agent Cards arriving
        // on the discovery topic, so this agent actually discovers OTHER agents.
        // We subscribe to the RAW "messageReceived" event via LpClient: the
        // generated onMessageReceived coerces the byte payload to an empty object,
        // so we decode _a = [hash, contentTopic, payload, ts] ourselves. The
        // payload arrives as the published card bytes (a JSON-array of byte values
        // or a string); reconstruct the string and parse the card.
        if (!impl_->discovery_handler_registered) {
            std::string my_topic = effective_topic;
            // Subscribe the delivery NODE to the Waku content topic so it relays +
            // emits messageReceived for peer cards.
            modules().delivery_module.subscribe(effective_topic);
            // Register the event handler via LpClient, NOT modules().delivery_module
            // .onMessageReceived: the generated proxy acquires a QtRO replica, connects
            // eventResponse, then RELEASES the replica when the call returns (verified
            // via qt.remoteobjects logs: AddObject -> Connect 7 -> RemoveObject within
            // ms), so the subscription dies before any peer card arrives. LpClient's
            // lp_subscribe is the persistent SDK event mechanism (mirrors rust-sdk's
            // EventSubscription); the returned LpSubscription, stored in impl_->disc_sub,
            // keeps the subscription alive for the agent's lifetime. The payload is a
            // JSON array [hash, contentTopic, payload, ts].
            impl_->disc_client = std::make_unique<logos::LpClient>("delivery_module", "agent_module");
            impl_->disc_sub = impl_->disc_client->subscribe("messageReceived",
                [this, my_topic](nlohmann::json a) {
                    try {
                        if (!a.is_array() || a.size() < 3) return;
                        std::string contentTopic = a[1].is_string() ? a[1].get<std::string>() : "";
                        if (contentTopic != my_topic) return;
                        const auto& payload = a[2];
                        std::string payload_str;
                        if (payload.is_object() && payload.contains("_bytes") && payload["_bytes"].is_string()) payload_str = agent_b64_decode(payload["_bytes"].get<std::string>());
                        else if (payload.is_string()) payload_str = payload.get<std::string>();
                        else if (payload.is_array()) { for (auto& b : payload) if (b.is_number_integer()) payload_str.push_back(static_cast<char>(b.get<int>())); }
                        else payload_str = payload.dump();
                        json card = safe_parse(payload_str);
                        if (card.is_string()) card = safe_parse(card.get<std::string>());
                        if (!card.is_object()) return;
                        std::string peer_npk;
                        if (card.contains("x-lez-identity") && card["x-lez-identity"].is_object())
                            peer_npk = card["x-lez-identity"].value("npk", "");
                        if (peer_npk.empty()) return;
                        if (peer_npk == impl_->cfg("agent_npk", "")) return;  // skip our own card
                        {
                            std::lock_guard<std::mutex> lk(g_peers_mu);
                            // Bound the map: a hostile peer can flood the discovery topic with
                            // distinct npks. Cap total entries so discovery can't be turned into
                            // an unbounded-memory DoS; known peers are still refreshed when full.
                            constexpr size_t kMaxDiscoveredPeers = 512;
                            if (g_discovered_peers.size() >= kMaxDiscoveredPeers &&
                                g_discovered_peers.find(peer_npk) == g_discovered_peers.end()) return;
                            g_discovered_peers[peer_npk] = {
                                {"name",   card.value("name", "")},
                                {"npk",    peer_npk},
                                {"skills", card.value("skills", json::array())}
                            };
                        }
                    } catch (...) { /* ignore malformed peer messages */ }
                });
            impl_->discovery_handler_registered = true;
        }

        // Publish our own Agent Card to the topic so peers can discover us.
        // Send as a JSON STRING: the generated delivery send() turns a string
        // LogosMap into the wire payload bytes (an object LogosMap serialises to
        // 0 bytes). NOTE: the matching generated onMessageReceived binding maps
        // the received bytes to a LogosMap and only forwards JSON objects, so a
        // peer reading via that event gets an empty payload — a generated-binding
        // limitation (see F8_DISCOVERY_FIX.md); the card data itself does travel.
        std::string my_card_raw = agent_card();
        json my_card_j = safe_parse(my_card_raw);
        if (my_card_j.contains("result") && my_card_j["result"].is_object()) {
            std::string card_str = my_card_j["result"].dump();
            modules().delivery_module.send(effective_topic, nlohmann::json(card_str));
        }

        // Store the topic so we can unsubscribe later.
        impl_->config["last_discover_topic"] = effective_topic;
        impl_->save_config();

        // Return the peers discovered so far (cards ingested by the handler).
        json peers = json::array();
        {
            std::lock_guard<std::mutex> lk(g_peers_mu);
            for (auto& kv : g_discovered_peers) peers.push_back(kv.second);
        }

        return ok({
            {"status",           "subscribed_and_published"},
            {"topic",            effective_topic},
            {"card_published",   true},
            {"discovered_peers", peers},
            {"peer_count",       peers.size()}
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
            modules().chat_module.newPrivateConversation(
                agent_address,
                hex_payload);
        } else {
            modules().chat_module.sendMessage(
                convo_id,
                hex_payload);
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
                if (pr.is_object() && pr.contains("result") && pr["result"].is_object() && pr["result"].contains("tx_hash")) {
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
        modules().delivery_module.subscribe(task_topic);

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
                convo_id,
                hex_payload);
        }

        // Unsubscribe from the task topic.
        std::string sub_key   = "task_sub_" + task_id;
        std::string task_topic = impl_->cfg(sub_key);
        if (!task_topic.empty()) {
            modules().delivery_module.unsubscribe(task_topic);
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

        // Discovered peers (F8) — exposed here too so callers can read them
        // without re-invoking agent_discover (whose subscribe can block).
        json discovered = json::array();
        {
            std::lock_guard<std::mutex> lk(g_peers_mu);
            for (auto& kv : g_discovered_peers) discovered.push_back(kv.second);
        }

        json status = {
            {"version",           kVersion},
            {"balance",           balance_str},
            {"period_spent",      impl_->period_spent},
            {"active_tasks",      active_tasks},
            {"pending_approvals", pending_approvals},
            {"skill_providers",   impl_->skill_providers},
            {"discovered_peers",  discovered},
            {"peer_count",        discovered.size()},
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
// The `logos_events:` methods (approval_required, task_update, skill_failed) are
// declared in the header and CALLED throughout this file. Their emitter bodies
// are generated by the logos_module() builder in agent_module_events_cdylib.cpp,
// so they are intentionally NOT defined here — defining them again causes a
// multiple-definition link error (collides with the generated cdylib glue).
