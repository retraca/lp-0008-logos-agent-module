#pragma once
// lez_wallet_module_impl.h
//
// Universal Logos Core module (pattern 2b from LEARNING.md §2b).
// "interface": "universal" in metadata.json means logos-cpp-generator reads this header
// and auto-generates the Qt plugin wrapper, ILezWallet contract interface, and inter-module
// glue. You do NOT write Q_OBJECT, Q_PLUGIN_METADATA, Q_INVOKABLE, or initLogos here.
//
// Wire types used: std::string, int64_t, bool, LogosResult.
// No Qt headers in this file (the generator adds them in the generated wrapper).
//
// Methods map 1:1 to the ILezWallet contract in scaffold/interfaces/lez_wallet.h.
// The agent module binds this at runtime:
//   modules().bind_lez_wallet("lez_wallet_module")
//
// BLOCKED: this file cannot be compiled without the Logos Core SDK headers
// (logos_module_context.h, logos_result.h) which come from `nix develop`.
// See BUILD.md for the build path.

#include <cstdint>
#include <string>

// SDK headers (available inside `nix develop` via LOGOS_CPP_SDK_ROOT/include)
#include "logos_module_context.h"
#include "interface.h"
#include "logos_types.h"
#include "logos_result.h"

class LezWalletModuleImpl : public LogosModuleContext {
public:
    // --- Identity ---

    // Create or reopen the agent's shielded private account.
    // On first call: generates a BIP39 mnemonic (printed to stderr), creates key storage,
    // encrypts NSK under `passphrase`, persists keystore.json to the module data dir.
    // On subsequent calls: verifies the passphrase and returns the existing AccountId.
    // Returns the AccountId as a base58 string inside LogosResult.
    StdLogosResult ensure_account(const std::string& passphrase);

    // Return the agent's NullifierPublicKey as a 64-char hex string.
    StdLogosResult npk(const std::string& passphrase);

    // --- Balance and history ---

    // Return the agent's current shielded token balance as a decimal string.
    StdLogosResult balance(const std::string& passphrase);

    // Return recent private transfer history as a JSON array.
    // `limit` <= 0 means all available entries.
    StdLogosResult history(const std::string& passphrase, int64_t limit);

    // Scan the chain for this account's latest private state.
    // Should be called before balance() or history() to ensure local state is current.
    bool sync_private();

    // --- Transfers ---

    // Shielded transfer.
    // `recipient`: base58 AccountId (known/owned account) or 64-char hex NPK (foreign).
    // `amount_decimal`: token amount as a decimal string (avoids u128 wire type limits).
    // Returns tx hash hex on success.
    // NOTE: the spending-threshold gate lives in the agent module, not here.
    StdLogosResult send(const std::string& passphrase,
                        const std::string& recipient,
                        const std::string& amount_decimal);

    // --- Programs ---

    // Read state from a LEZ program (sequencer RPC, no signature required).
    // `program_id`: base58 AccountId of the program.
    // `params_json`: JSON object passed as query parameters.
    StdLogosResult program_query(const std::string& program_id,
                                 const std::string& params_json);

    // Submit a transaction to a LEZ program (builds + signs + posts SignedMantleTx).
    // `instruction`: instruction discriminant string (program-specific, e.g. "transfer").
    // `params_json`: JSON object with instruction parameters.
    // Returns tx hash hex.
    // NOTE: subject to spending-threshold gate in the agent module.
    StdLogosResult program_call(const std::string& passphrase,
                                const std::string& program_id,
                                const std::string& instruction,
                                const std::string& params_json);

    // Deploy a compiled LEZ program binary to the network.
    // `binary_path`: local filesystem path to the compiled RISC-V program binary.
    // Returns the new program ID as a base58 string.
    StdLogosResult program_deploy(const std::string& passphrase,
                                  const std::string& binary_path);

// Events (emitted by this module; subscribers receive them via the Logos event bus).
logos_events:
    // Emitted when a submitted transaction is finalized on chain.
    void tx_settled(const std::string& tx_hash, int64_t timestamp);

    // Emitted when a submitted transaction fails after exhausting retries.
    void tx_failed(const std::string& tx_hash, const std::string& error, int64_t timestamp);
};
