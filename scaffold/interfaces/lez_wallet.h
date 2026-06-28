#pragma once
// Contract for the NEW `lez_wallet_module` that LP-0008 must build.
//
// IMPORTANT: this module does NOT exist in the Logos repos today. The shielded
// LEZ wallet + program interaction lives only as a Rust CLI in
// logos-execution-zone/wallet (`lez-build/wallet`), talking to a sequencer over
// HTTP via bedrock_client. See LEARNING.md S6 ("the central gap"). This header is
// the proposed Logos Core surface for that bridge so the agent can bind it via
// `modules().bind_lez_wallet("lez_wallet_module")`.
//
// Key model (LEARNING.md S6b): NSK (NullifierSecretKey [u8;32], secret) ->
// NPK (NullifierPublicKey [u8;32], identity) -> private AccountId; VPK for viewing.
// Amounts are u128 in nssa; represented here as decimal strings to stay within the
// universal wire types (no native u128). Recipients are base58 account ids / NPKs.
//
// NOTE: All methods use std::string params only (no int64_t, no bool return)
// so the logos-cpp-generator correctly generates the Qt bound interface wrapper.
// history() passes limit as a decimal string; sync_private() returns "ok"/"error".

#include <string>

class ILezWallet {
public:
    // --- identity ---
    std::string ensure_account(const std::string& unused = "");
    std::string npk(const std::string& unused = "");
    std::string vpk(const std::string& unused = "");

    // --- balance / history ---
    std::string balance(const std::string& unused = "");
    std::string history(const std::string& limit_decimal);
    std::string sync_private(const std::string& unused = "");

    // --- transfers ---
    std::string send(const std::string& recipient, const std::string& amount_decimal);
    std::string send_to(const std::string& npk_hex, const std::string& vpk_hex, const std::string& amount_decimal);

    // --- programs (LEARNING.md S6c) ---
    std::string program_query(const std::string& program_id, const std::string& params_json);
    std::string program_call(const std::string& program_id, const std::string& instruction, const std::string& params_json);
    std::string program_deploy(const std::string& binary_path);

logos_events:
    void tx_settled(const std::string& tx_hash, int64_t timestamp);
    void tx_failed(const std::string& tx_hash, const std::string& error, int64_t timestamp);
};
