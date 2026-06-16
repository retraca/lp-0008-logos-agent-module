use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::process;

use anyhow::{bail, Result};
use clap::{Parser, Subcommand};

// ---------------------------------------------------------------------------
// FFI declarations -- symbols exported by the linked lez-wallet-core cdylib.
// ---------------------------------------------------------------------------

extern "C" {
    fn lez_wallet_ensure_account(home_dir: *const c_char, passphrase: *const c_char) -> *mut c_char;
    fn lez_wallet_npk(home_dir: *const c_char, passphrase: *const c_char) -> *mut c_char;
    fn lez_wallet_balance(home_dir: *const c_char, passphrase: *const c_char) -> *mut c_char;
    fn lez_wallet_history(home_dir: *const c_char, passphrase: *const c_char, limit: i64) -> *mut c_char;
    fn lez_wallet_sync_private(home_dir: *const c_char) -> bool;
    fn lez_wallet_send(
        home_dir: *const c_char,
        passphrase: *const c_char,
        recipient: *const c_char,
        amount_decimal: *const c_char,
    ) -> *mut c_char;
    fn lez_wallet_program_query(
        home_dir: *const c_char,
        program_id: *const c_char,
        params_json: *const c_char,
    ) -> *mut c_char;
    fn lez_wallet_program_call(
        home_dir: *const c_char,
        passphrase: *const c_char,
        program_id: *const c_char,
        instruction: *const c_char,
        params_json: *const c_char,
    ) -> *mut c_char;
    fn lez_wallet_program_deploy(
        home_dir: *const c_char,
        passphrase: *const c_char,
        binary_path: *const c_char,
    ) -> *mut c_char;
    fn lez_wallet_free_string(s: *mut c_char);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn cs(s: &str) -> CString {
    CString::new(s).expect("argument contains interior nul byte")
}

// Takes ownership of the returned pointer, copies to String, frees it.
unsafe fn take(ptr: *mut c_char) -> String {
    let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    lez_wallet_free_string(ptr);
    s
}

// Prints the JSON result and exits 1 if it is an error envelope.
fn emit(json: &str) {
    println!("{json}");
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(json) {
        if v.get("error").is_some() {
            process::exit(1);
        }
    }
}

// ---------------------------------------------------------------------------
// CLI definitions
// ---------------------------------------------------------------------------

#[derive(Parser)]
#[command(name = "lez", about = "LEZ agent wallet CLI")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    EnsureAccount {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
    },
    Npk {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
    },
    Balance {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
    },
    Send {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
        #[arg(long)]
        to: String,
        #[arg(long)]
        amount: String,
    },
    Sync {
        #[arg(long)]
        home: String,
    },
    History {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
        #[arg(long, default_value = "20")]
        limit: i64,
    },
    #[command(subcommand)]
    Program(ProgramCmd),
}

#[derive(Subcommand)]
enum ProgramCmd {
    Deploy {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
        #[arg(long)]
        binary: String,
    },
    Call {
        #[arg(long)]
        home: String,
        #[arg(long)]
        passphrase: String,
        #[arg(long = "program-id")]
        program_id: String,
        #[arg(long)]
        instruction: String,
        #[arg(long)]
        params: String,
    },
    Query {
        #[arg(long)]
        home: String,
        #[arg(long = "program-id")]
        program_id: String,
        #[arg(long)]
        params: String,
    },
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Cmd::EnsureAccount { home, passphrase } => {
            let result = unsafe { take(lez_wallet_ensure_account(cs(&home).as_ptr(), cs(&passphrase).as_ptr())) };
            // ensure_account returns a bare AccountId string on success, not a JSON envelope.
            // Wrap it so callers always get uniform JSON.
            let json = if result.starts_with('{') {
                result
            } else {
                format!(r#"{{"ok": "{result}"}}"#)
            };
            emit(&json);
        }

        Cmd::Npk { home, passphrase } => {
            let result = unsafe { take(lez_wallet_npk(cs(&home).as_ptr(), cs(&passphrase).as_ptr())) };
            let json = if result.starts_with('{') {
                result
            } else {
                format!(r#"{{"ok": "{result}"}}"#)
            };
            emit(&json);
        }

        Cmd::Balance { home, passphrase } => {
            let result = unsafe { take(lez_wallet_balance(cs(&home).as_ptr(), cs(&passphrase).as_ptr())) };
            let json = if result.starts_with('{') {
                result
            } else {
                format!(r#"{{"ok": "{result}"}}"#)
            };
            emit(&json);
        }

        Cmd::Send { home, passphrase, to, amount } => {
            let result = unsafe {
                take(lez_wallet_send(
                    cs(&home).as_ptr(),
                    cs(&passphrase).as_ptr(),
                    cs(&to).as_ptr(),
                    cs(&amount).as_ptr(),
                ))
            };
            let json = if result.starts_with('{') {
                result
            } else {
                format!(r#"{{"ok": "{result}"}}"#)
            };
            emit(&json);
        }

        Cmd::Sync { home } => {
            let ok = unsafe { lez_wallet_sync_private(cs(&home).as_ptr()) };
            if ok {
                println!(r#"{{"ok": true}}"#);
            } else {
                println!(r#"{{"error": "sync failed"}}"#);
                process::exit(1);
            }
        }

        Cmd::History { home, passphrase, limit } => {
            let result = unsafe {
                take(lez_wallet_history(cs(&home).as_ptr(), cs(&passphrase).as_ptr(), limit))
            };
            emit(&result);
        }

        Cmd::Program(ProgramCmd::Deploy { home, passphrase, binary }) => {
            let result = unsafe {
                take(lez_wallet_program_deploy(
                    cs(&home).as_ptr(),
                    cs(&passphrase).as_ptr(),
                    cs(&binary).as_ptr(),
                ))
            };
            let json = if result.starts_with('{') {
                result
            } else {
                format!(r#"{{"ok": "{result}"}}"#)
            };
            emit(&json);
        }

        Cmd::Program(ProgramCmd::Call { home, passphrase, program_id, instruction, params }) => {
            let result = unsafe {
                take(lez_wallet_program_call(
                    cs(&home).as_ptr(),
                    cs(&passphrase).as_ptr(),
                    cs(&program_id).as_ptr(),
                    cs(&instruction).as_ptr(),
                    cs(&params).as_ptr(),
                ))
            };
            let json = if result.starts_with('{') {
                result
            } else {
                format!(r#"{{"ok": "{result}"}}"#)
            };
            emit(&json);
        }

        Cmd::Program(ProgramCmd::Query { home, program_id, params }) => {
            let result = unsafe {
                take(lez_wallet_program_query(
                    cs(&home).as_ptr(),
                    cs(&program_id).as_ptr(),
                    cs(&params).as_ptr(),
                ))
            };
            emit(&result);
        }
    }

    Ok(())
}
