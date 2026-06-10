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

#include <string>
#include <cstdint>

class ILezWallet {
public:
    // --- identity ---
    // Create/return the agent's shielded private account; returns its AccountId (base58).
    std::string ensure_account();          // idempotent; inits keystore + mnemonic on first call
    std::string npk();                     // agent NullifierPublicKey (base58/hex)

    // --- balance / history ---
    std::string balance();                 // decimal-string token balance of the shielded account
    std::string history(int64_t limit);    // JSON array of recent transfers (post-sync)
    bool        sync_private();             // scan chain for this account's latest private state

    // --- transfers ---
    // Shielded transfer. Returns tx hash (hex) on success, error envelope otherwise.
    // The spending-threshold gate lives in the AGENT module, not here (ARCHITECTURE S5).
    std::string send(const std::string& recipient, const std::string& amount_decimal);

    // --- programs (LEARNING.md S6c) ---
    std::string program_query(const std::string& program_id, const std::string& params_json);
    std::string program_call(const std::string& program_id,
                             const std::string& instruction,
                             const std::string& params_json);   // builds+signs+posts SignedMantleTx
    std::string program_deploy(const std::string& binary_path); // ProgramDeploymentTransaction -> program id

logos_events:
    void tx_settled(const std::string& tx_hash, int64_t timestamp);
    void tx_failed(const std::string& tx_hash, const std::string& error, int64_t timestamp);
};
