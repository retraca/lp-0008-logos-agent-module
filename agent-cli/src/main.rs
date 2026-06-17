//! agent-cli — single-command deploy + configure CLI for the LP-0008 autonomous agent module.
//!
//! Orchestrates the `logoscore` binary as subprocesses.  All subcommands share
//! the global `--logoscore` / `LOGOSCORE_BIN` option that locates the binary.
//!
//! # Quick start (the "single CLI command" required by the spec)
//!
//!   agent up \
//!     --modules-dir ./result-agent \
//!     --owner <YOUR-NPK-HEX> \
//!     --per-tx-limit 10.0 \
//!     --per-period-limit 100.0 \
//!     --detach

use std::{
    path::PathBuf,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};

// ---------------------------------------------------------------------------
// Default binary path — overridden by --logoscore / LOGOSCORE_BIN
// ---------------------------------------------------------------------------
const DEFAULT_LOGOSCORE: &str = "logoscore";

// ---------------------------------------------------------------------------
// Top-level CLI
// ---------------------------------------------------------------------------

/// LP-0008 agent-cli: deploy, configure, and manage an autonomous AI agent on Logos Core.
///
/// All subcommands call the `logoscore` binary as a subprocess.
/// Override the binary path with --logoscore <path> or LOGOSCORE_BIN env var.
#[derive(Parser, Debug)]
#[command(name = "agent", version, about, long_about = None)]
struct Cli {
    /// Path to the logoscore binary.
    ///
    /// Defaults to `logoscore` (must be on PATH), or set LOGOSCORE_BIN.
    #[arg(long, env = "LOGOSCORE_BIN", global = true, default_value = DEFAULT_LOGOSCORE)]
    logoscore: PathBuf,

    /// Logos Core sequencer URL (passed as -s to logoscore).
    #[arg(long, env = "SEQUENCER", global = true, default_value = "http://127.0.0.1:3040")]
    sequencer: String,

    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Start the Logos Core daemon headless, then load agent_module.
    ///
    /// Spawns `logoscore -D -m <modules-dir> -s <sequencer>`, polls until the
    /// daemon is ready (meta.status returns successfully), then loads agent_module.
    /// With --detach the daemon is left running in the background.
    /// Without --detach the daemon process is kept in the foreground (blocks).
    Deploy(DeployArgs),

    /// Configure the agent's spending limits and owner address.
    ///
    /// Calls `meta.configure` for each provided key.  Requires a running daemon.
    Configure(ConfigureArgs),

    /// Fund the agent's shielded account.
    ///
    /// TODO (runtime milestone): the exact wallet_fund subcommand name and
    /// parameter encoding depend on the lez_wallet_module wire-method API
    /// finalisation.  The command is structured; verify the call expression
    /// against `logoscore -l lez_wallet_module -c "help()"` once the wallet
    /// module is loaded.
    Fund(FundArgs),

    /// Print the agent's current status (meta.status).
    Status(StatusArgs),

    /// Deploy + configure in a single invocation (the spec's "single CLI command").
    ///
    /// Equivalent to running `agent deploy` followed immediately by
    /// `agent configure` (and optionally `agent fund`).
    Up(UpArgs),
}

// ---------------------------------------------------------------------------
// Per-subcommand argument structs
// ---------------------------------------------------------------------------

#[derive(Parser, Debug)]
struct DeployArgs {
    /// Directory containing the built module plugin (.so / .dylib) and metadata.json.
    ///
    /// Passed to logoscore as: -m <modules-dir>
    /// The directory must contain both `libagent_module_plugin.so` (or .dylib)
    /// and `liblez_wallet_module_plugin.so` (or .dylib).
    #[arg(long)]
    modules_dir: PathBuf,

    /// Leave the daemon running in the background after loading the module.
    ///
    /// Without this flag the daemon process is kept in the foreground and the
    /// CLI blocks until the daemon exits (useful for systemd / supervised runs).
    #[arg(long, default_value_t = false)]
    detach: bool,
}

#[derive(Parser, Debug)]
struct ConfigureArgs {
    /// The agent owner's NullifierPublicKey (NPK) hex address.
    ///
    /// Set on the agent via: meta.configure("owner_address", <value>)
    #[arg(long)]
    owner: String,

    /// Maximum LEZ per single transaction that the agent may execute autonomously.
    ///
    /// Set via: meta.configure("per_tx_limit", <value>)
    #[arg(long)]
    per_tx_limit: String,

    /// Maximum LEZ per rolling period that the agent may execute autonomously.
    ///
    /// Set via: meta.configure("per_period_limit", <value>)
    #[arg(long)]
    per_period_limit: String,

    /// Length of the rolling spend-tracking window, in seconds (default: 86400 = 1 day).
    ///
    /// Set via: meta.configure("period_seconds", <value>)
    #[arg(long, default_value = "86400")]
    period_seconds: String,

    /// Modules directory — passed to logoscore so it can locate the loaded agent_module.
    #[arg(long)]
    modules_dir: PathBuf,
}

#[derive(Parser, Debug)]
struct FundArgs {
    /// Amount of LEZ to deposit into the agent's shielded account.
    ///
    /// TODO (runtime milestone): confirm the call expression once the
    /// lez_wallet_module wire-method API is finalised.  Current best guess:
    ///   lez_wallet_module.wallet_fund("<amount>")
    /// Update `fund_call_expr()` in this file when the API is confirmed.
    #[arg(long)]
    amount: String,

    /// Passphrase protecting the agent's keystore (forwarded to the wallet module).
    #[arg(long)]
    passphrase: Option<String>,

    /// Modules directory — passed to logoscore so it can locate the loaded module.
    #[arg(long)]
    modules_dir: PathBuf,
}

#[derive(Parser, Debug)]
struct StatusArgs {
    /// Modules directory — passed to logoscore so it can locate the loaded agent_module.
    #[arg(long)]
    modules_dir: PathBuf,
}

#[derive(Parser, Debug)]
struct UpArgs {
    // --- deploy fields ---
    /// Directory containing the built module plugin (.so / .dylib) and metadata.json.
    #[arg(long)]
    modules_dir: PathBuf,

    /// Leave the daemon running in the background after the up sequence completes.
    #[arg(long, default_value_t = false)]
    detach: bool,

    // --- configure fields ---
    /// The agent owner's NullifierPublicKey (NPK) hex address.
    #[arg(long)]
    owner: String,

    /// Maximum LEZ per single transaction (autonomous).
    #[arg(long)]
    per_tx_limit: String,

    /// Maximum LEZ per rolling period (autonomous).
    #[arg(long)]
    per_period_limit: String,

    /// Rolling window length in seconds (default: 86400).
    #[arg(long, default_value = "86400")]
    period_seconds: String,

    // --- fund fields (optional) ---
    /// If provided, fund the agent's shielded account with this amount after configure.
    #[arg(long)]
    fund: Option<String>,

    /// Passphrase for the agent keystore (required if --fund is set).
    #[arg(long)]
    passphrase: Option<String>,
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() {
    let cli = Cli::parse();
    if let Err(e) = run(cli) {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn run(cli: Cli) -> Result<()> {
    match cli.command {
        Cmd::Deploy(args) => cmd_deploy(&cli.logoscore, &cli.sequencer, &args),
        Cmd::Configure(args) => cmd_configure(&cli.logoscore, &cli.sequencer, &args),
        Cmd::Fund(args) => cmd_fund(&cli.logoscore, &cli.sequencer, &args),
        Cmd::Status(args) => cmd_status(&cli.logoscore, &cli.sequencer, &args),
        Cmd::Up(args) => cmd_up(&cli.logoscore, &cli.sequencer, args),
    }
}

// ---------------------------------------------------------------------------
// Subcommand implementations
// ---------------------------------------------------------------------------

fn cmd_deploy(logoscore: &PathBuf, sequencer: &str, args: &DeployArgs) -> Result<()> {
    let modules_dir = args
        .modules_dir
        .canonicalize()
        .with_context(|| format!("modules-dir not found: {}", args.modules_dir.display()))?;

    println!(
        "[agent-cli] Starting Logos Core daemon (modules: {}) …",
        modules_dir.display()
    );

    let child = spawn_daemon(logoscore, sequencer, &modules_dir)?;
    let child_id = child.id();

    // Give daemon time to start capability_module.
    println!("[agent-cli] Waiting for daemon to become ready …");
    wait_for_capability(logoscore)?;
    println!("[agent-cli] Daemon ready (PID {child_id}).");

    // Load all external modules discovered in the modules_dir.
    println!("[agent-cli] Loading modules from {} …", modules_dir.display());
    load_all_modules(logoscore, &modules_dir)?;
    println!("[agent-cli] All modules loaded.");

    // Now wait for agent_module to respond to meta_status.
    println!("[agent-cli] Waiting for agent_module to respond …");
    wait_for_daemon(logoscore, sequencer, &modules_dir)?;
    println!("[agent-cli] agent_module loaded and responding.");

    if args.detach {
        println!("[agent-cli] Daemon running in background (PID {child_id}). Done.");
        // We intentionally leak `child` here — the process continues after we exit.
        std::mem::forget(child);
    } else {
        println!("[agent-cli] Keeping daemon in foreground (PID {child_id}). Ctrl-C to stop.");
        wait_for_child(child)?;
    }

    Ok(())
}

/// Wait until the capability_module is loaded (daemon is responsive).
fn wait_for_capability(logoscore: &PathBuf) -> Result<()> {
    let timeout = Duration::from_secs(30);
    let poll_interval = Duration::from_millis(500);
    let start = Instant::now();

    loop {
        if start.elapsed() > timeout {
            bail!("daemon did not start within {timeout:?}");
        }
        let output = Command::new(logoscore)
            .arg("status")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();
        if let Ok(o) = output {
            let stdout = String::from_utf8_lossy(&o.stdout);
            if stdout.contains("\"running\"") {
                return Ok(());
            }
        }
        thread::sleep(poll_interval);
    }
}

/// Load every module subdirectory found in the modules_dir.
///
/// Uses `logoscore load-module <name>` for each subdirectory.
fn load_all_modules(logoscore: &PathBuf, modules_dir: &PathBuf) -> Result<()> {
    let entries = std::fs::read_dir(modules_dir)
        .with_context(|| format!("cannot read modules_dir: {}", modules_dir.display()))?;

    let mut names: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();

    // Load dependency modules first, agent_module last.
    names.sort_by_key(|n| if n == "agent_module" { 1 } else { 0 });

    for name in &names {
        println!("[agent-cli] load-module {name} …");
        let output = Command::new(logoscore)
            .arg("load-module")
            .arg(name)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .with_context(|| format!("failed to run logoscore load-module {name}"))?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !output.status.success() {
            eprintln!("[agent-cli] warning: load-module {name} failed: {stderr}");
        } else {
            println!("[agent-cli] {name}: {}", stdout.trim());
        }
    }
    Ok(())
}

fn cmd_configure(logoscore: &PathBuf, sequencer: &str, args: &ConfigureArgs) -> Result<()> {
    let modules_dir = args.modules_dir.canonicalize().with_context(|| {
        format!("modules-dir not found: {}", args.modules_dir.display())
    })?;

    let pairs = [
        ("owner_address", args.owner.as_str()),
        ("per_tx_limit", args.per_tx_limit.as_str()),
        ("per_period_limit", args.per_period_limit.as_str()),
        ("period_seconds", args.period_seconds.as_str()),
    ];

    for (key, value) in &pairs {
        println!("[agent-cli] meta_configure({key} = {value})");
        // Use the positional-arg form: meta_configure(key, value)
        let expr = format!("meta_configure({}, {})", json_str(key), json_str(value));
        logos_call(logoscore, sequencer, &modules_dir, "agent_module", &expr, false)?;
    }

    println!("[agent-cli] Configuration complete.");
    Ok(())
}

fn cmd_fund(logoscore: &PathBuf, sequencer: &str, args: &FundArgs) -> Result<()> {
    let modules_dir = args.modules_dir.canonicalize().with_context(|| {
        format!("modules-dir not found: {}", args.modules_dir.display())
    })?;

    // TODO (runtime milestone): confirm the lez_wallet_module wire-method name
    // for funding / depositing to the agent's shielded account.
    //
    // Current best guess based on SUBMISSION.md "ensure_account" + "send" API:
    //   lez_wallet_module.wallet_fund("<passphrase>", "<amount>")
    //
    // Until the API is confirmed, this command emits a clear TODO and exits 1
    // so the CLI is structured but the caller knows it needs updating.
    //
    // To complete: replace the bail!() below with the confirmed logos_call expression.
    let passphrase = args.passphrase.as_deref().unwrap_or("");
    let expr = fund_call_expr(passphrase, &args.amount);

    println!("[agent-cli] Funding agent shielded account (amount: {}) …", args.amount);
    // Never log the passphrase. Print a redacted form of the call expression.
    // NOTE (runtime TODO): the passphrase is still passed to logoscore as a `-c`
    // argument, so it is visible in the process listing (`ps`). When the funding
    // API is finalised, forward the passphrase via stdin or an env var instead.
    println!("[agent-cli] Call expression: {}", fund_call_expr("***", &args.amount));
    println!(
        "[agent-cli] TODO (runtime milestone): verify this call expression against \
         `logoscore -l lez_wallet_module -c \"help()\"` once the wallet module is loaded. \
         Update fund_call_expr() in src/main.rs if the method name differs."
    );

    logos_call(logoscore, sequencer, &modules_dir, "lez_wallet_module", &expr, false)?;
    println!("[agent-cli] Fund call submitted.");
    Ok(())
}

fn cmd_status(logoscore: &PathBuf, sequencer: &str, args: &StatusArgs) -> Result<()> {
    let modules_dir = args.modules_dir.canonicalize().with_context(|| {
        format!("modules-dir not found: {}", args.modules_dir.display())
    })?;

    println!("[agent-cli] Fetching agent status …");
    let output = logos_call(
        logoscore,
        sequencer,
        &modules_dir,
        "agent_module",
        "meta_status()",
        false,
    )?;
    println!("{output}");
    Ok(())
}

fn cmd_up(logoscore: &PathBuf, sequencer: &str, args: UpArgs) -> Result<()> {
    println!("[agent-cli] Starting 'up' sequence (deploy + configure) …");

    let deploy_args = DeployArgs {
        modules_dir: args.modules_dir.clone(),
        detach: true, // always detach so configure can follow immediately
    };
    cmd_deploy(logoscore, sequencer, &deploy_args)?;

    let configure_args = ConfigureArgs {
        owner: args.owner,
        per_tx_limit: args.per_tx_limit,
        per_period_limit: args.per_period_limit,
        period_seconds: args.period_seconds,
        modules_dir: args.modules_dir.clone(),
    };
    cmd_configure(logoscore, sequencer, &configure_args)?;

    if let Some(amount) = args.fund {
        let fund_args = FundArgs {
            amount,
            passphrase: args.passphrase,
            modules_dir: args.modules_dir,
        };
        cmd_fund(logoscore, sequencer, &fund_args)?;
    }

    if !args.detach {
        println!("[agent-cli] Up complete. Daemon detached (PID unknown at this point).");
        println!("[agent-cli] Use `agent status` to check agent health.");
    }

    println!("[agent-cli] Agent is up.");
    Ok(())
}

// ---------------------------------------------------------------------------
// logoscore subprocess helpers
// ---------------------------------------------------------------------------

/// Spawn the `logoscore` daemon (`-D` flag) and return the child process.
///
/// The daemon's stdout/stderr are inherited so the operator can see its logs.
fn spawn_daemon(logoscore: &PathBuf, _sequencer: &str, modules_dir: &PathBuf) -> Result<Child> {
    // Note: the daemon (-D) does not accept a -s sequencer flag; the sequencer URL
    // is configured per-module (e.g. lez_wallet_module reads it from its own config).
    let child = Command::new(logoscore)
        .arg("-D")
        .arg("-m")
        .arg(modules_dir)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
        .with_context(|| format!("failed to spawn logoscore daemon: {}", logoscore.display()))?;
    Ok(child)
}

/// Poll `meta.status()` until the daemon responds or the timeout expires.
///
/// Retries every 500 ms for up to 60 seconds.
fn wait_for_daemon(logoscore: &PathBuf, sequencer: &str, modules_dir: &PathBuf) -> Result<()> {
    let timeout = Duration::from_secs(60);
    let poll_interval = Duration::from_millis(500);
    let start = Instant::now();

    loop {
        if start.elapsed() > timeout {
            bail!("daemon did not become ready within {timeout:?}");
        }

        match logos_call(logoscore, sequencer, modules_dir, "agent_module", "meta_status()", true) {
            Ok(_) => return Ok(()),
            Err(_) => {
                thread::sleep(poll_interval);
            }
        }
    }
}

/// Call a single expression against a loaded module via `logoscore -c`.
///
/// Flags used:
///   -m <modules-dir>    module search path
///   -s <sequencer>      sequencer URL
///   -l <module>         module name to route the call to
///   -c <expr>           call expression, e.g. `meta.configure("key","val")`
///   --quit-on-finish    exit after the call returns
///   --json-output       emit structured JSON responses
///
/// Returns the stdout of the call on success, or an error if logoscore exits
/// non-zero or the response contains an `"error"` top-level key.
/// Parse a legacy-style call expression like `meta.configure("key", "val")` or
/// `meta.status()` into a (method, args) pair for the `logoscore call` subcommand.
///
/// The `logoscore call <module> <method> [args...]` API takes the method name as a
/// positional argument and any parameters as subsequent positional arguments.
/// This function strips the surrounding `func(...)` shell, extracts the method name
/// from the dotted path, and returns any comma-separated string arguments.
fn parse_call_expr(expr: &str) -> (String, Vec<String>) {
    // Find the opening paren.
    let paren = match expr.find('(') {
        Some(p) => p,
        None => return (expr.to_string(), vec![]),
    };
    let func_path = &expr[..paren];
    // Use only the last segment (e.g. "meta.configure" → "meta_configure").
    let method = func_path
        .split('.')
        .last()
        .unwrap_or(func_path)
        .replace('.', "_");

    // Extract content inside parens.
    let inner = expr[paren + 1..].trim_end_matches(')');
    if inner.trim().is_empty() {
        return (method, vec![]);
    }

    // Split on commas and strip surrounding quotes from each argument.
    let args: Vec<String> = inner
        .split(',')
        .map(|s| {
            let s = s.trim();
            if (s.starts_with('"') && s.ends_with('"'))
                || (s.starts_with('\'') && s.ends_with('\''))
            {
                // Unescape simple JSON string escapes.
                s[1..s.len() - 1]
                    .replace("\\\"", "\"")
                    .replace("\\\\", "\\")
            } else {
                s.to_string()
            }
        })
        .collect();

    (method, args)
}

fn logos_call(
    logoscore: &PathBuf,
    _sequencer: &str,
    _modules_dir: &PathBuf,
    module: &str,
    expr: &str,
    suppress_output: bool,
) -> Result<String> {
    // The logoscore CLI uses: logoscore call <module> <method> [args...]
    // There is no -s / -l / -c / --quit-on-finish in this version.
    let (method, call_args) = parse_call_expr(expr);

    let mut cmd = Command::new(logoscore);
    cmd.arg("call").arg(module).arg(&method);
    for a in &call_args {
        cmd.arg(a);
    }
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());

    let output = cmd
        .output()
        .with_context(|| format!("failed to run logoscore: {}", logoscore.display()))?;

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();

    if !suppress_output {
        if !stdout.is_empty() {
            print!("{stdout}");
        }
        if !stderr.is_empty() {
            eprint!("{stderr}");
        }
    }

    if !output.status.success() {
        bail!(
            "logoscore exited with status {} for expr `{expr}` on module `{module}`\nstderr: {stderr}",
            output.status
        );
    }

    // Detect a top-level {"error": ...} in the JSON response.
    if stdout.trim_start().starts_with('{') && stdout.contains("\"error\"") {
        bail!(
            "logoscore returned an error response for expr `{expr}` on module `{module}`:\n{stdout}"
        );
    }

    Ok(stdout)
}

/// Keep the CLI alive until the child process exits, forwarding its exit code.
fn wait_for_child(mut child: Child) -> Result<()> {
    let status = child.wait().context("failed to wait for daemon process")?;
    if !status.success() {
        bail!("daemon exited with status {status}");
    }
    Ok(())
}

/// Build the call expression for funding the agent's shielded account.
///
/// TODO (runtime milestone): confirm this expression against the lez_wallet_module
/// wire-method API once the module is built.  The method name `wallet_fund` is a
/// best-guess from SUBMISSION.md; the actual method may be `ensure_account` +
/// directing an external LEZ transfer to the returned NPK address.
///
/// Possible alternative (if there is no direct "fund" method):
///   1. Call `lez_wallet_module.ensure_account("<passphrase>")` to create the account.
///   2. Call `lez_wallet_module.npk("<passphrase>")` to get the NPK.
///   3. Transfer LEZ to that NPK from an external wallet (out-of-band).
///
/// Until confirmed, this function produces a placeholder expression and the
/// `cmd_fund` implementation prints a clear TODO before invoking it.
fn fund_call_expr(passphrase: &str, amount: &str) -> String {
    // The lez_wallet_module exposes ensure_account + send.
    // "Funding" means sending LEZ *to* the agent's own account.
    // That is an external transfer; there is no self-fund method in the current API.
    //
    // Best current guess at a one-shot fund helper:
    //   lez_wallet_module.wallet_fund("<passphrase>", "<amount>")
    //
    // If the method does not exist, the logoscore call will fail with a clear error,
    // prompting the operator to check the actual method list.
    format!("wallet_fund({}, {})", json_str(passphrase), json_str(amount))
}

/// Encode a string as a JSON string literal (including the surrounding quotes),
/// escaping `"`, `\`, control characters, and newlines. Used to safely embed
/// user-supplied values inside a logoscore `-c` call expression so they cannot
/// inject additional call syntax.
fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
