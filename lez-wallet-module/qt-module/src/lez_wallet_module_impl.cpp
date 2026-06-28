// lez_wallet_module_impl.cpp
//
// Qt module shim: thin wrapper over the lez-wallet-core Rust FFI.
// All heavy logic lives in the Rust crate. This file:
//   1. Resolves the module's home dir via LogosModuleContext persistence path.
//   2. Uses a fixed internal passphrase ("agent") — passphrase managed here, not by callers.
//   3. Calls the lez_wallet_* FFI function.
//   4. Returns JSON string: raw FFI result on success, {"error":"..."} envelope on failure.
//   5. Frees the C string returned by the Rust side.

#include "lez_wallet_module_impl.h"
#include "../lez_wallet_ffi.h"

#include <string>
#include <cstring>

namespace {

// Fixed internal passphrase. The module creates/re-opens the keystore with this
// passphrase; callers do not supply it (passphrase-free wire surface).
static constexpr const char* kInternalPassphrase = "agent";

std::string agent_home_dir_impl(const LezWalletModuleImpl* self) {
    // Prefer the framework-provisioned persistence path when available.
    if (self->isContextReady() && !self->instancePersistencePath().empty()) {
        return self->instancePersistencePath();
    }
    // Fallback for testing outside a full Logos Core host.
    const char* env = std::getenv("LEZ_WALLET_HOME");
    if (env && std::strlen(env) > 0) {
        return env;
    }
    return "/tmp/lez_wallet_agent";
}

// Convert a raw Rust FFI result to std::string; frees the C string.
std::string ffi_str(char* raw) {
    if (raw == nullptr) {
        return "{\"error\":\"lez_wallet_core returned null\"}";
    }
    std::string s(raw);
    lez_wallet_free_string(raw);
    return s;
}

}  // namespace

// --- Identity ---

std::string LezWalletModuleImpl::ensure_account() {
    char* raw = lez_wallet_ensure_account(agent_home_dir_impl(this).c_str(), kInternalPassphrase);
    return ffi_str(raw);
}

std::string LezWalletModuleImpl::npk() {
    char* raw = lez_wallet_npk(agent_home_dir_impl(this).c_str(), kInternalPassphrase);
    return ffi_str(raw);
}

std::string LezWalletModuleImpl::vpk() {
    char* raw = lez_wallet_vpk(agent_home_dir_impl(this).c_str(), kInternalPassphrase);
    return ffi_str(raw);
}

// --- Balance and history ---

std::string LezWalletModuleImpl::balance() {
    char* raw = lez_wallet_balance(agent_home_dir_impl(this).c_str(), kInternalPassphrase);
    return ffi_str(raw);
}

std::string LezWalletModuleImpl::history(int64_t limit) {
    char* raw = lez_wallet_history(agent_home_dir_impl(this).c_str(), kInternalPassphrase, limit);
    return ffi_str(raw);
}

bool LezWalletModuleImpl::sync_private() {
    return lez_wallet_sync_private(agent_home_dir_impl(this).c_str());
}

// --- Transfers ---

std::string LezWalletModuleImpl::send(const std::string& recipient,
                                      const std::string& amount_decimal) {
    char* raw = lez_wallet_send(agent_home_dir_impl(this).c_str(),
                                kInternalPassphrase,
                                recipient.c_str(),
                                amount_decimal.c_str());
    return ffi_str(raw);
}

// send_to: agent-to-agent shielded transfer to a FOREIGN account by NPK + VPK.
// Calls the new lez_wallet_send_to FFI which routes to provider::send_to_foreign.
// The recipient MUST be a fresh account (never received) for the tx to settle on-chain.
std::string LezWalletModuleImpl::send_to(const std::string& npk_hex,
                                          const std::string& vpk_hex,
                                          const std::string& amount_decimal) {
    char* raw = lez_wallet_send_to(agent_home_dir_impl(this).c_str(),
                                    npk_hex.c_str(),
                                    vpk_hex.c_str(),
                                    amount_decimal.c_str());
    return ffi_str(raw);
}

// --- Programs ---

std::string LezWalletModuleImpl::program_query(const std::string& program_id,
                                               const std::string& params_json) {
    char* raw = lez_wallet_program_query(agent_home_dir_impl(this).c_str(),
                                         program_id.c_str(),
                                         params_json.c_str());
    return ffi_str(raw);
}

std::string LezWalletModuleImpl::program_call(const std::string& program_id,
                                              const std::string& instruction,
                                              const std::string& params_json) {
    char* raw = lez_wallet_program_call(agent_home_dir_impl(this).c_str(),
                                        kInternalPassphrase,
                                        program_id.c_str(),
                                        instruction.c_str(),
                                        params_json.c_str());
    return ffi_str(raw);
}

std::string LezWalletModuleImpl::program_deploy(const std::string& binary_path) {
    char* raw = lez_wallet_program_deploy(agent_home_dir_impl(this).c_str(),
                                          kInternalPassphrase,
                                          binary_path.c_str());
    return ffi_str(raw);
}

// Events (tx_settled / tx_failed) are emitted by the generated dispatch layer
// from the logos_events declarations in the header; no impl-side definition needed.

