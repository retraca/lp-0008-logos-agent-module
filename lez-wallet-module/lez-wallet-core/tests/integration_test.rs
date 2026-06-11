// Integration tests for lez-wallet-core provider.
// These tests require a running local LEZ chain:
//   cd lez-build && DOCKER_DEFAULT_PLATFORM=linux/amd64 docker-compose up -d
//
// Run with:
//   cargo test --features lez-bridge --test integration_test -- --include-ignored

#![cfg(feature = "lez-bridge")]

use std::path::PathBuf;
use tempfile::tempdir;
use lez_wallet_core::provider;

fn agent_home() -> (tempfile::TempDir, PathBuf) {
    let dir = tempdir().expect("tempdir");
    let path = dir.path().to_path_buf();
    (dir, path)
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_ensure_account_creates_keystore() {
    let (_dir, home) = agent_home();
    let account_id = provider::ensure_account(&home, "testpass123").await.expect("ensure_account");
    assert!(!account_id.is_empty(), "account_id should be non-empty");
    // keystore file must exist after creation
    assert!(home.join("keystore.json").exists(), "keystore must be persisted");
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_ensure_account_idempotent() {
    let (_dir, home) = agent_home();
    let id1 = provider::ensure_account(&home, "testpass123").await.expect("first call");
    let id2 = provider::ensure_account(&home, "testpass123").await.expect("second call");
    assert_eq!(id1, id2, "same passphrase must return same account");
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_npk_round_trip() {
    let (_dir, home) = agent_home();
    provider::ensure_account(&home, "testpass").await.expect("setup");
    let npk = provider::get_npk(&home, "testpass").await.expect("npk");
    assert_eq!(npk.len(), 64, "NPK should be 64 hex chars");
    assert!(npk.chars().all(|c| c.is_ascii_hexdigit()), "NPK must be hex");
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_balance_returns_decimal() {
    let (_dir, home) = agent_home();
    provider::ensure_account(&home, "testpass").await.expect("setup");
    let balance = provider::get_balance(&home, "testpass").await.expect("balance");
    // balance is a decimal string; should parse as f64
    balance.parse::<f64>().expect("balance must be a decimal number");
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_sync_private() {
    let (_dir, home) = agent_home();
    provider::ensure_account(&home, "testpass").await.expect("setup");
    let ok = provider::sync_private(&home).await.expect("sync");
    assert!(ok, "sync_private should return true when chain is reachable");
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_history_empty_initially() {
    let (_dir, home) = agent_home();
    provider::ensure_account(&home, "testpass").await.expect("setup");
    let history = provider::get_history(&home, "testpass", 10).await.expect("history");
    // history is a JSON array; must be parseable
    let v: serde_json::Value = serde_json::from_str(&history).expect("history must be JSON");
    assert!(v.is_array(), "history must be a JSON array");
}

#[tokio::test]
#[ignore = "requires local lez-build chain on 127.0.0.1:3040"]
async fn test_wrong_passphrase_is_rejected() {
    let (_dir, home) = agent_home();
    provider::ensure_account(&home, "correct-pass").await.expect("setup");
    let result = provider::get_npk(&home, "wrong-pass").await;
    assert!(result.is_err(), "wrong passphrase must be rejected");
}
