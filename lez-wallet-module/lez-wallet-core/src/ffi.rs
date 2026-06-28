// ffi.rs: C-callable FFI layer (requires --features lez-bridge)
//
// Each function:
//   - Takes const char* string arguments.
//   - Returns a *mut c_char (heap-allocated). Caller must free via lez_wallet_free_string.
//   - On success: returns the result as a JSON string or a plain string value.
//   - On error: returns a JSON error envelope: {"error": "message text"}.
//
// The Qt module shim (lez_wallet_module_impl.cpp) calls these and detects the error
// envelope by checking for the "error" key in the returned JSON.
//
// Thread model: each call creates a new single-threaded Tokio runtime (cheap for
// infrequent wallet operations). If call frequency becomes an issue, use a persistent
// runtime in a thread-local or a lazy_static.
//
// cbindgen (cargo install cbindgen) generates lez_wallet_ffi.h from this file.
// Run: cbindgen --crate lez-wallet-core --output qt-module/lez_wallet_ffi.h

use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    path::Path,
};

use crate::provider;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert a C string pointer to a &str. Returns None if null or invalid UTF-8.
unsafe fn cstr_to_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

/// Allocate a C string from a Rust &str. The caller owns the memory.
fn to_cstring(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_else(|_| CString::new("<encoding error>").unwrap()).into_raw()
}

/// Return an error envelope JSON.
fn error_result(msg: &str) -> *mut c_char {
    let escaped = msg.replace('\\', "\\\\").replace('"', "\\\"");
    to_cstring(&format!(r#"{{"error": "{escaped}"}}"#))
}

/// Run an async future on a new single-threaded Tokio runtime.
fn block_on<F: std::future::Future>(f: F) -> F::Output {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("failed to build Tokio runtime")
        .block_on(f)
}

// ---------------------------------------------------------------------------
// Exported C functions
// ---------------------------------------------------------------------------

/// Initialize or reopen the agent's shielded LEZ account.
///
/// Returns the AccountId (base58) on success, or `{"error": "..."}` on failure.
///
/// # Safety
/// `home_dir` and `passphrase` must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_ensure_account(
    home_dir: *const c_char,
    passphrase: *const c_char,
) -> *mut c_char {
    let (Some(home), Some(pass)) = (unsafe { cstr_to_str(home_dir) }, unsafe { cstr_to_str(passphrase) }) else {
        return error_result("null argument");
    };
    match block_on(provider::ensure_account(Path::new(home), pass)) {
        Ok(account_id) => to_cstring(&account_id),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Return the agent's NullifierPublicKey as a 64-char hex string.
///
/// # Safety
/// `home_dir` and `passphrase` must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_npk(
    home_dir: *const c_char,
    passphrase: *const c_char,
) -> *mut c_char {
    let (Some(home), Some(pass)) = (unsafe { cstr_to_str(home_dir) }, unsafe { cstr_to_str(passphrase) }) else {
        return error_result("null argument");
    };
    match block_on(provider::get_npk(Path::new(home), pass)) {
        Ok(npk_hex) => to_cstring(&npk_hex),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Return the agent's ViewingPublicKey as a hex string.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_vpk(
    home_dir: *const c_char,
    passphrase: *const c_char,
) -> *mut c_char {
    let (Some(home), Some(pass)) = (unsafe { cstr_to_str(home_dir) }, unsafe { cstr_to_str(passphrase) }) else {
        return error_result("null argument");
    };
    match block_on(provider::get_vpk(Path::new(home), pass)) {
        Ok(vpk_hex) => to_cstring(&vpk_hex),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Return the agent's shielded token balance as a decimal string.
///
/// # Safety
/// `home_dir` and `passphrase` must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_balance(
    home_dir: *const c_char,
    passphrase: *const c_char,
) -> *mut c_char {
    let (Some(home), Some(pass)) = (unsafe { cstr_to_str(home_dir) }, unsafe { cstr_to_str(passphrase) }) else {
        return error_result("null argument");
    };
    match block_on(provider::get_balance(Path::new(home), pass)) {
        Ok(balance) => to_cstring(&balance),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Return recent private transfer history as a JSON array.
///
/// # Safety
/// `home_dir` and `passphrase` must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_history(
    home_dir: *const c_char,
    passphrase: *const c_char,
    limit: i64,
) -> *mut c_char {
    let (Some(home), Some(pass)) = (unsafe { cstr_to_str(home_dir) }, unsafe { cstr_to_str(passphrase) }) else {
        return error_result("null argument");
    };
    match block_on(provider::get_history(Path::new(home), pass, limit)) {
        Ok(json) => to_cstring(&json),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Sync private account state to the latest chain block.
///
/// Returns `true` on success, `false` on failure.
///
/// # Safety
/// `home_dir` must be a valid null-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_sync_private(home_dir: *const c_char) -> bool {
    let Some(home) = (unsafe { cstr_to_str(home_dir) }) else {
        return false;
    };
    block_on(provider::sync_private(Path::new(home))).unwrap_or(false)
}

/// Send a shielded transfer to `recipient` (base58 AccountId or hex NPK).
///
/// Returns the tx hash as a hex string, or `{"error": "..."}` on failure.
///
/// # Safety
/// All pointer arguments must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_send(
    home_dir: *const c_char,
    passphrase: *const c_char,
    recipient: *const c_char,
    amount_decimal: *const c_char,
) -> *mut c_char {
    let args = [
        unsafe { cstr_to_str(home_dir) },
        unsafe { cstr_to_str(passphrase) },
        unsafe { cstr_to_str(recipient) },
        unsafe { cstr_to_str(amount_decimal) },
    ];
    let [Some(home), Some(pass), Some(rec), Some(amt)] = args else {
        return error_result("null argument");
    };
    match block_on(provider::send_shielded(Path::new(home), pass, rec, amt)) {
        Ok(tx_hash) => to_cstring(&tx_hash),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Send a shielded transfer to a FOREIGN account by NPK + VPK.
///
/// npk_hex: 64-char hex NullifierPublicKey of the recipient.
/// vpk_hex: 66-char hex (compressed secp256k1) ViewingPublicKey of the recipient.
/// amount_decimal: decimal string amount.
///
/// Returns the tx hash as a hex string, or `{"error": "..."}` on failure.
/// The recipient MUST be a fresh account (never received) for the tx to settle.
///
/// # Safety
/// All pointer arguments must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_send_to(
    home_dir: *const c_char,
    npk_hex: *const c_char,
    vpk_hex: *const c_char,
    amount_decimal: *const c_char,
) -> *mut c_char {
    let args = [
        unsafe { cstr_to_str(home_dir) },
        unsafe { cstr_to_str(npk_hex) },
        unsafe { cstr_to_str(vpk_hex) },
        unsafe { cstr_to_str(amount_decimal) },
    ];
    let [Some(home), Some(npk), Some(vpk), Some(amt)] = args else {
        return error_result("null argument");
    };
    match block_on(provider::send_to_foreign(Path::new(home), npk, vpk, amt)) {
        Ok(tx_hash) => to_cstring(&tx_hash),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Query program state (read-only).
///
/// Returns a JSON string or `{"error": "..."}`.
///
/// # Safety
/// All pointer arguments must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_program_query(
    home_dir: *const c_char,
    program_id: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    let args = [
        unsafe { cstr_to_str(home_dir) },
        unsafe { cstr_to_str(program_id) },
        unsafe { cstr_to_str(params_json) },
    ];
    let [Some(home), Some(pid), Some(params)] = args else {
        return error_result("null argument");
    };
    match block_on(provider::program_query(Path::new(home), pid, params)) {
        Ok(json) => to_cstring(&json),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Call a LEZ program (build + sign + post SignedMantleTx).
///
/// Returns the tx hash as hex or `{"error": "..."}`.
///
/// # Safety
/// All pointer arguments must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_program_call(
    home_dir: *const c_char,
    passphrase: *const c_char,
    program_id: *const c_char,
    instruction: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    let args = [
        unsafe { cstr_to_str(home_dir) },
        unsafe { cstr_to_str(passphrase) },
        unsafe { cstr_to_str(program_id) },
        unsafe { cstr_to_str(instruction) },
        unsafe { cstr_to_str(params_json) },
    ];
    let [Some(home), Some(pass), Some(pid), Some(instr), Some(params)] = args else {
        return error_result("null argument");
    };
    match block_on(provider::program_call(Path::new(home), pass, pid, instr, params)) {
        Ok(tx_hash) => to_cstring(&tx_hash),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Deploy a compiled LEZ program binary.
///
/// Returns the new program ID (base58) or `{"error": "..."}`.
///
/// # Safety
/// All pointer arguments must be valid null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_program_deploy(
    home_dir: *const c_char,
    passphrase: *const c_char,
    binary_path: *const c_char,
) -> *mut c_char {
    let args = [
        unsafe { cstr_to_str(home_dir) },
        unsafe { cstr_to_str(passphrase) },
        unsafe { cstr_to_str(binary_path) },
    ];
    let [Some(home), Some(pass), Some(bin)] = args else {
        return error_result("null argument");
    };
    match block_on(provider::program_deploy(Path::new(home), pass, bin)) {
        Ok(program_id) => to_cstring(&program_id),
        Err(e) => error_result(&e.to_string()),
    }
}

/// Free a string returned by any lez_wallet_* function.
///
/// Must be called exactly once per returned pointer.
///
/// # Safety
/// `s` must be a pointer previously returned by a lez_wallet_* function and not yet freed.
#[no_mangle]
pub unsafe extern "C" fn lez_wallet_free_string(s: *mut c_char) {
    if !s.is_null() {
        // Reconstruct the CString and drop it, which frees the memory.
        unsafe { drop(CString::from_raw(s)) };
    }
}
