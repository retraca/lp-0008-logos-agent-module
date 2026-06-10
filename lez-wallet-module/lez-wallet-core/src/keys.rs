// keys.rs: LEZ key derivation (standalone, no lez-build dependency)
//
// Reproduces the exact derivation from nssa/core/src/nullifier.rs using only sha2.
// These functions exist so the keystore and identity logic can be tested without
// touching the heavy nssa / risc0 crate tree.
//
// When building with `--features lez-bridge`, use the nssa crate types directly
// instead of these standalone re-implementations (they produce identical output).
//
// Known-answer test vectors are taken verbatim from nssa/core/src/nullifier.rs tests.

use sha2::{Digest, Sha256};

/// A 32-byte NullifierSecretKey (the root secret; never stored plaintext).
pub type NskBytes = [u8; 32];

/// A 32-byte NullifierPublicKey.
pub type NpkBytes = [u8; 32];

/// A 32-byte raw AccountId value.
pub type AccountIdBytes = [u8; 32];

/// Derive the NullifierPublicKey from an NSK.
///
/// Algorithm (verbatim from nssa/core/src/nullifier.rs `From<&NullifierSecretKey> for NullifierPublicKey`):
///   input = b"LEE/keys" || nsk[0..32] || [7u8] || [0u8; 23]
///   npk   = SHA-256(input)
pub fn derive_npk(nsk: &NskBytes) -> NpkBytes {
    const PREFIX: &[u8; 8] = b"LEE/keys";
    const SUFFIX_1: &[u8; 1] = &[7];
    const SUFFIX_2: &[u8; 23] = &[0; 23];

    let mut hasher = Sha256::new();
    hasher.update(PREFIX);
    hasher.update(nsk);
    hasher.update(SUFFIX_1);
    hasher.update(SUFFIX_2);

    hasher.finalize().into()
}

/// Derive the private AccountId from an NPK.
///
/// Algorithm (verbatim from nssa/core/src/nullifier.rs `From<&NullifierPublicKey> for AccountId`):
///   input = b"/LEE/v0.3/AccountId/Private/\x00\x00\x00\x00" || npk[0..32]
///   Note: the prefix is exactly 32 bytes (28 ASCII + 4 zero bytes).
///   account_id = SHA-256(input[0..64])
pub fn derive_account_id(npk: &NpkBytes) -> AccountIdBytes {
    // The prefix in nullifier.rs is b"/LEE/v0.3/AccountId/Private/\x00\x00\x00\x00"
    // which is 28 ASCII bytes + 4 null bytes = 32 bytes total.
    const PREFIX: &[u8; 32] = b"/LEE/v0.3/AccountId/Private/\x00\x00\x00\x00";

    let mut bytes = [0u8; 64];
    bytes[..32].copy_from_slice(PREFIX);
    bytes[32..].copy_from_slice(npk);

    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher.finalize().into()
}

/// Encode a 32-byte value as base58 (matching nssa AccountId Display).
pub fn to_base58(bytes: &[u8; 32]) -> String {
    use base58::ToBase58;
    bytes.to_base58()
}

/// Decode a base58 string to a 32-byte value.
pub fn from_base58(s: &str) -> Result<[u8; 32], KeyDerivationError> {
    use base58::FromBase58;
    let bytes = s.from_base58().map_err(|_| KeyDerivationError::InvalidBase58)?;
    if bytes.len() != 32 {
        return Err(KeyDerivationError::InvalidLength(bytes.len()));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

/// Encode a 32-byte value as lowercase hex.
pub fn to_hex(bytes: &[u8; 32]) -> String {
    bytes.iter().fold(String::with_capacity(64), |mut s, b| {
        s.push_str(&format!("{b:02x}"));
        s
    })
}

/// Decode a 64-char hex string to a 32-byte value.
pub fn from_hex(s: &str) -> Result<[u8; 32], KeyDerivationError> {
    if s.len() != 64 {
        return Err(KeyDerivationError::InvalidLength(s.len()));
    }
    let mut out = [0u8; 32];
    for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
        let hi = hex_nibble(chunk[0])?;
        let lo = hex_nibble(chunk[1])?;
        out[i] = (hi << 4) | lo;
    }
    Ok(out)
}

fn hex_nibble(b: u8) -> Result<u8, KeyDerivationError> {
    match b {
        b'0'..=b'9' => Ok(b - b'0'),
        b'a'..=b'f' => Ok(b - b'a' + 10),
        b'A'..=b'F' => Ok(b - b'A' + 10),
        _ => Err(KeyDerivationError::InvalidHex(b as char)),
    }
}

#[derive(Debug, thiserror::Error)]
pub enum KeyDerivationError {
    #[error("invalid base58 encoding")]
    InvalidBase58,
    #[error("invalid byte length: {0}")]
    InvalidLength(usize),
    #[error("invalid hex character: {0:?}")]
    InvalidHex(char),
}

// ---- Unit tests (no lez-build dependency) --------------------------------
// All expected values taken verbatim from nssa/core/src/nullifier.rs test suite.

#[cfg(test)]
mod tests {
    use super::*;
    // sha2 is used via the top-level `use sha2::{Digest, Sha256}` in parent module.

    // Known-answer vector from nullifier.rs `from_secret_key` test.
    const TEST_NSK: NskBytes = [
        57, 5, 64, 115, 153, 56, 184, 51, 207, 238, 99, 165, 147, 214, 213, 151, 30, 251, 30, 196,
        134, 22, 224, 211, 237, 120, 136, 225, 188, 220, 249, 28,
    ];

    const EXPECTED_NPK: NpkBytes = [
        78, 20, 20, 5, 177, 198, 233, 100, 175, 134, 174, 200, 24, 205, 68, 215, 130, 74, 35, 54,
        154, 184, 219, 42, 168, 106, 126, 147, 133, 244, 18, 218,
    ];

    // Known-answer vector from nullifier.rs `account_id_from_nullifier_public_key` test.
    const EXPECTED_ACCOUNT_ID: AccountIdBytes = [
        139, 72, 194, 222, 215, 187, 147, 56, 55, 35, 222, 205, 156, 12, 204, 227, 166, 44, 30,
        81, 186, 14, 167, 234, 28, 236, 32, 213, 125, 251, 193, 233,
    ];

    #[test]
    fn nsk_to_npk_matches_nssa_vector() {
        let npk = derive_npk(&TEST_NSK);
        assert_eq!(
            npk, EXPECTED_NPK,
            "NSK->NPK derivation must match nssa/core/src/nullifier.rs vector"
        );
    }

    #[test]
    fn npk_to_account_id_matches_nssa_vector() {
        let account_id = derive_account_id(&EXPECTED_NPK);
        assert_eq!(
            account_id, EXPECTED_ACCOUNT_ID,
            "NPK->AccountId derivation must match nssa/core/src/nullifier.rs vector"
        );
    }

    #[test]
    fn full_derivation_chain() {
        let npk = derive_npk(&TEST_NSK);
        let account_id = derive_account_id(&npk);
        assert_eq!(account_id, EXPECTED_ACCOUNT_ID);
    }

    #[test]
    fn base58_roundtrip() {
        let encoded = to_base58(&EXPECTED_ACCOUNT_ID);
        let decoded = from_base58(&encoded).expect("roundtrip should succeed");
        assert_eq!(decoded, EXPECTED_ACCOUNT_ID);
    }

    #[test]
    fn hex_roundtrip() {
        let encoded = to_hex(&EXPECTED_NPK);
        assert_eq!(encoded.len(), 64);
        let decoded = from_hex(&encoded).expect("roundtrip should succeed");
        assert_eq!(decoded, EXPECTED_NPK);
    }

    #[test]
    fn wrong_passphrase_base58_rejected() {
        let result = from_base58("not_valid_base58_!@#");
        assert!(matches!(result, Err(KeyDerivationError::InvalidBase58)));
    }

    #[test]
    fn zero_nsk_derivation_is_deterministic() {
        let nsk_a = [0u8; 32];
        let nsk_b = [0u8; 32];
        assert_eq!(derive_npk(&nsk_a), derive_npk(&nsk_b));
    }

    #[test]
    fn different_nsks_produce_different_npks() {
        let nsk_a = [1u8; 32];
        let nsk_b = [2u8; 32];
        assert_ne!(derive_npk(&nsk_a), derive_npk(&nsk_b));
    }
}
