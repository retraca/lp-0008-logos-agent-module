//! LP-0008 agent CLI.
//!
//! Build with the default feature set (no chain needed) for local keystore operations:
//!   cargo build --release
//!
//! Build with lez-bridge (requires the full lez-build workspace) for live chain operations:
//!   cargo build --release --features lez-bridge
//!
//! All outputs are JSON for easy shell pipeline consumption:
//!   {"ok": "<value>"}     — success
//!   {"error": "<msg>"}    — failure

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "lez", about = "LP-0008 agent wallet CLI")]
struct Cli {
    /// Sequencer URL (overrides wallet_config.json in --home)
    #[arg(long, global = true)]
    sequencer: Option<String>,

    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Create or reopen a shielded LEZ account; returns account ID as JSON.
    EnsureAccount {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
    },
    /// Return the agent's NullifierPublicKey (64-char hex).
    Npk {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
    },
    /// Return the agent's current shielded token balance.
    Balance {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
    },
    /// Sync private chain state (scans for incoming shielded transfers).
    Sync {
        #[arg(long)]
        home: PathBuf,
    },
    /// Return recent transaction history.
    History {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
        #[arg(long, default_value = "20")]
        limit: i64,
    },
    /// Send a shielded transfer.
    Send {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount: String,
    },
    /// LEZ program operations.
    #[command(subcommand)]
    Program(ProgramCmd),
}

#[derive(Subcommand)]
enum ProgramCmd {
    /// Deploy a compiled LEZ program binary; returns program ID as JSON.
    Deploy {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
        #[arg(long)]
        binary: PathBuf,
    },
    /// Call a LEZ program instruction.
    Call {
        #[arg(long)]
        home: PathBuf,
        #[arg(long)]
        passphrase: String,
        #[arg(long)]
        program_id: String,
        #[arg(long)]
        instruction: String,
        #[arg(long, default_value = "{}")]
        params: String,
    },
    /// Query a LEZ program's state (read-only, no signature needed).
    Query {
        #[arg(long)]
        program_id: String,
        #[arg(long, default_value = "{}")]
        params: String,
    },
}

#[cfg(feature = "lez-bridge")]
fn ok(v: &str) -> String {
    format!("{{\"ok\": {}}}", serde_json::to_string(v).unwrap())
}

#[cfg(feature = "lez-bridge")]
fn err_json(msg: &str) -> String {
    format!("{{\"error\": {}}}", serde_json::to_string(msg).unwrap())
}

#[cfg(feature = "lez-bridge")]
#[tokio::main]
async fn main() {
    use lez_wallet_core::provider;

    let cli = Cli::parse();

    // If --sequencer is set, write wallet_config.json into the home dir before any operation.
    let write_sequencer_config = |home: &PathBuf, seq: &Option<String>| {
        if let Some(ref url) = seq {
            let cfg_path = home.join("wallet_config.json");
            let cfg = serde_json::json!({ "sequencer_addr": url });
            let _ = std::fs::create_dir_all(home);
            let _ = std::fs::write(&cfg_path, cfg.to_string());
        }
    };

    let result = match &cli.cmd {
        Cmd::EnsureAccount { home, passphrase } => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::ensure_account(home, passphrase).await {
                Ok(id) => ok(&id),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Npk { home, passphrase } => {
            match provider::get_npk(home, passphrase).await {
                Ok(npk) => ok(&npk),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Balance { home, passphrase } => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::get_balance(home, passphrase).await {
                Ok(bal) => ok(&bal),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Sync { home } => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::sync_private(home).await {
                Ok(_) => ok("synced"),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::History { home, passphrase, limit } => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::get_history(home, passphrase, *limit).await {
                Ok(hist) => ok(&hist),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Send { home, passphrase, recipient, amount } => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::send_shielded(home, passphrase, recipient, amount).await {
                Ok(tx) => ok(&tx),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Program(ProgramCmd::Deploy { home, passphrase, binary }) => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::program_deploy(home, passphrase, binary).await {
                Ok(id) => ok(&id),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Program(ProgramCmd::Call { home, passphrase, program_id, instruction, params }) => {
            write_sequencer_config(home, &cli.sequencer);
            match provider::program_call(home, passphrase, program_id, instruction, params).await {
                Ok(res) => ok(&res),
                Err(e) => err_json(&e.to_string()),
            }
        }
        Cmd::Program(ProgramCmd::Query { program_id, params }) => {
            let home = PathBuf::from(".");
            write_sequencer_config(&home, &cli.sequencer);
            match provider::program_query(&home, program_id, params).await {
                Ok(res) => ok(&res),
                Err(e) => err_json(&e.to_string()),
            }
        }
    };

    println!("{result}");
}

// Without lez-bridge, the CLI still parses args so the binary compiles cleanly,
// but returns an informative error rather than silently doing nothing.
#[cfg(not(feature = "lez-bridge"))]
#[tokio::main]
async fn main() {
    let _cli = Cli::parse();
    eprintln!("This binary was built without --features lez-bridge.");
    eprintln!("Rebuild with: cargo build --release --features lez-bridge");
    eprintln!("(requires the full lez-build workspace; see docs/DEPLOYMENT.md §4)");
    std::process::exit(1);
}
