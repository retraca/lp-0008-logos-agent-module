#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize or reopen the agent's shielded LEZ account.
 *
 * Returns the AccountId (base58) on success, or `{"error": "..."}` on failure.
 *
 * # Safety
 * `home_dir` and `passphrase` must be valid null-terminated C strings.
 */
char *lez_wallet_ensure_account(const char *home_dir, const char *passphrase);

/**
 * Return the agent's NullifierPublicKey as a 64-char hex string.
 *
 * # Safety
 * `home_dir` and `passphrase` must be valid null-terminated C strings.
 */
char *lez_wallet_npk(const char *home_dir, const char *passphrase);

/**
 * Return the agent's shielded token balance as a decimal string.
 *
 * # Safety
 * `home_dir` and `passphrase` must be valid null-terminated C strings.
 */
char *lez_wallet_balance(const char *home_dir, const char *passphrase);

/**
 * Return recent private transfer history as a JSON array.
 *
 * # Safety
 * `home_dir` and `passphrase` must be valid null-terminated C strings.
 */
char *lez_wallet_history(const char *home_dir, const char *passphrase, int64_t limit);

/**
 * Sync private account state to the latest chain block.
 *
 * Returns `true` on success, `false` on failure.
 *
 * # Safety
 * `home_dir` must be a valid null-terminated C string.
 */
bool lez_wallet_sync_private(const char *home_dir);

/**
 * Send a shielded transfer to `recipient` (base58 AccountId or hex NPK).
 *
 * Returns the tx hash as a hex string, or `{"error": "..."}` on failure.
 *
 * # Safety
 * All pointer arguments must be valid null-terminated C strings.
 */
char *lez_wallet_send(const char *home_dir,
                      const char *passphrase,
                      const char *recipient,
                      const char *amount_decimal);

/**
 * Send a shielded transfer to a FOREIGN account by NPK + VPK.
 *
 * npk_hex: 64-char hex NullifierPublicKey of the recipient.
 * vpk_hex: 66-char hex (compressed secp256k1) ViewingPublicKey of the recipient.
 * amount_decimal: decimal string amount.
 *
 * Returns the tx hash as a hex string, or `{"error": "..."}` on failure.
 * The recipient MUST be a fresh account (never received) for the tx to settle.
 *
 * # Safety
 * All pointer arguments must be valid null-terminated C strings.
 */
char *lez_wallet_send_to(const char *home_dir,
                         const char *npk_hex,
                         const char *vpk_hex,
                         const char *amount_decimal);

/**
 * Query program state (read-only).
 *
 * Returns a JSON string or `{"error": "..."}`.
 *
 * # Safety
 * All pointer arguments must be valid null-terminated C strings.
 */
char *lez_wallet_program_query(const char *home_dir,
                               const char *program_id,
                               const char *params_json);

/**
 * Call a LEZ program (build + sign + post SignedMantleTx).
 *
 * Returns the tx hash as hex or `{"error": "..."}`.
 *
 * # Safety
 * All pointer arguments must be valid null-terminated C strings.
 */
char *lez_wallet_program_call(const char *home_dir,
                              const char *passphrase,
                              const char *program_id,
                              const char *instruction,
                              const char *params_json);

/**
 * Deploy a compiled LEZ program binary.
 *
 * Returns the new program ID (base58) or `{"error": "..."}`.
 *
 * # Safety
 * All pointer arguments must be valid null-terminated C strings.
 */
char *lez_wallet_program_deploy(const char *home_dir,
                                const char *passphrase,
                                const char *binary_path);

/**
 * Free a string returned by any lez_wallet_* function.
 *
 * Must be called exactly once per returned pointer.
 *
 * # Safety
 * `s` must be a pointer previously returned by a lez_wallet_* function and not yet freed.
 */
void lez_wallet_free_string(char *s);

#ifdef __cplusplus
}
#endif
