#pragma once
// lez_wallet_module_impl.h
//
// Universal Logos Core module (pattern 2b from LEARNING.md §2b).
// "interface": "universal" in metadata.json means logos-cpp-generator reads this header
// and auto-generates the Qt plugin wrapper, ILezWallet contract interface, and inter-module
// glue. You do NOT write Q_OBJECT, Q_PLUGIN_METADATA, Q_INVOKABLE, or initLogos here.
//
// Wire types used: std::string, int64_t, bool.
// Returns are JSON strings (success: {"result":...} or error: {"error":"..."}).
// No Qt headers in this file (the generator adds them in the generated wrapper).
//
// PASSPHRASE POLICY: the qt-module manages the passphrase INTERNALLY (fixed const "agent").
// All wire methods are passphrase-free to match the ILezWallet contract exactly.
// This satisfies Blocker 1 (LEARNING.md WIRING PHASE).
//
// GENERATOR RULE: every wire method must be declared on ONE LINE to be parsed by
// logos-cpp-generator. Methods with >=2 params get the generated binding; 1-param and
// 0-param methods are also included.

#include <cstdint>
#include <string>

// SDK headers (available inside `nix develop` via LOGOS_CPP_SDK_ROOT/include)
#include "logos_module_context.h"

class LezWalletModuleImpl : public LogosModuleContext {
public:
    // --- Identity (passphrase-free; module manages passphrase internally) ---
    std::string ensure_account();
    std::string npk();
    std::string vpk();

    // --- Balance and history ---
    std::string balance();
    std::string history(int64_t limit);
    bool sync_private();

    // --- Transfers (passphrase-free) ---
    std::string send(const std::string& recipient, const std::string& amount_decimal);
    std::string send_to(const std::string& npk_hex, const std::string& vpk_hex, const std::string& amount_decimal);

    // --- Programs (passphrase-free) ---
    std::string program_query(const std::string& program_id, const std::string& params_json);
    std::string program_call(const std::string& program_id, const std::string& instruction, const std::string& params_json);
    std::string program_deploy(const std::string& binary_path);

// Events (emitted by this module; subscribers receive them via the Logos event bus).
logos_events:
    // Emitted when a submitted transaction is finalized on chain.
    void tx_settled(const std::string& tx_hash, int64_t timestamp);

    // Emitted when a submitted transaction fails after exhausting retries.
    void tx_failed(const std::string& tx_hash, const std::string& error, int64_t timestamp);
};
