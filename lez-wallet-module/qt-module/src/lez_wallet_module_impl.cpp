// lez_wallet_module_impl.cpp
//
// Qt module shim: thin wrapper over the lez-wallet-core Rust FFI.
// All heavy logic lives in the Rust crate. This file:
//   1. Resolves the module's home dir via LogosModuleContext persistence path.
//   2. Calls the lez_wallet_* FFI function.
//   3. Translates {"error":"..."} envelope to StdLogosResult::error.
//   4. Frees the C string returned by the Rust side.

#include "lez_wallet_module_impl.h"
#include "../lez_wallet_ffi.h"
#include "logos_result.h"

#include <string>
#include <cstring>

namespace {

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

StdLogosResult ffi_result(char* raw) {
    if (raw == nullptr) {
        return {false, {}, "lez_wallet_core returned null"};
    }
    std::string s(raw);
    lez_wallet_free_string(raw);

    if (s.find("{\"error\"") != std::string::npos) {
        auto pos = s.find("\"error\": \"");
        if (pos == std::string::npos) pos = s.find("\"error\":\"");
        if (pos != std::string::npos) {
            pos = s.find('"', pos + 8) + 1;
            auto end = s.find('"', pos);
            auto msg = (end != std::string::npos) ? s.substr(pos, end - pos) : s;
            return {false, {}, msg};
        }
        return {false, {}, s};
    }
    return {true, s};
}

}  // namespace

StdLogosResult LezWalletModuleImpl::ensure_account(const std::string& passphrase) {
    char* raw = lez_wallet_ensure_account(agent_home_dir_impl(this).c_str(),
                                          passphrase.c_str());
    return ffi_result(raw);
}

StdLogosResult LezWalletModuleImpl::npk(const std::string& passphrase) {
    char* raw = lez_wallet_npk(agent_home_dir_impl(this).c_str(), passphrase.c_str());
    return ffi_result(raw);
}

StdLogosResult LezWalletModuleImpl::balance(const std::string& passphrase) {
    char* raw = lez_wallet_balance(agent_home_dir_impl(this).c_str(), passphrase.c_str());
    return ffi_result(raw);
}

StdLogosResult LezWalletModuleImpl::history(const std::string& passphrase, int64_t limit) {
    char* raw = lez_wallet_history(agent_home_dir_impl(this).c_str(),
                                   passphrase.c_str(), limit);
    return ffi_result(raw);
}

bool LezWalletModuleImpl::sync_private() {
    return lez_wallet_sync_private(agent_home_dir_impl(this).c_str());
}

StdLogosResult LezWalletModuleImpl::send(const std::string& passphrase,
                                         const std::string& recipient,
                                         const std::string& amount_decimal) {
    char* raw = lez_wallet_send(agent_home_dir_impl(this).c_str(),
                                passphrase.c_str(),
                                recipient.c_str(),
                                amount_decimal.c_str());
    return ffi_result(raw);
}

StdLogosResult LezWalletModuleImpl::program_query(const std::string& program_id,
                                                   const std::string& params_json) {
    char* raw = lez_wallet_program_query(agent_home_dir_impl(this).c_str(),
                                         program_id.c_str(),
                                         params_json.c_str());
    return ffi_result(raw);
}

StdLogosResult LezWalletModuleImpl::program_call(const std::string& passphrase,
                                                  const std::string& program_id,
                                                  const std::string& instruction,
                                                  const std::string& params_json) {
    char* raw = lez_wallet_program_call(agent_home_dir_impl(this).c_str(),
                                        passphrase.c_str(),
                                        program_id.c_str(),
                                        instruction.c_str(),
                                        params_json.c_str());
    return ffi_result(raw);
}

StdLogosResult LezWalletModuleImpl::program_deploy(const std::string& passphrase,
                                                    const std::string& binary_path) {
    char* raw = lez_wallet_program_deploy(agent_home_dir_impl(this).c_str(),
                                          passphrase.c_str(),
                                          binary_path.c_str());
    return ffi_result(raw);
}
