// keystore.rs: encrypted NSK-at-rest
//
// Design:
//   - AES-256-GCM authenticated encryption on the 32-byte NullifierSecretKey.
//   - Argon2id KDF derives the AES key from the owner's passphrase + a random salt.
//   - Stored on disk as a small JSON file (version, salt, nonce, ciphertext+tag).
//   - Wrong passphrase -> GCM authentication tag mismatch -> explicit KeystoreError::WrongPassphrase.
//   - No plaintext key ever touches disk.
//
// The NSK is zeroed in memory after use wherever this crate controls the buffer.

use std::{fs, path::Path};

use aes_gcm::{
    Aes256Gcm, Key, KeyInit, Nonce,
    aead::{Aead, OsRng},
    aead::rand_core::RngCore,
};
use argon2::Argon2;
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use serde::{Deserialize, Serialize};
use zeroize::Zeroize;

use crate::keys::NskBytes;

/// On-disk keystore file format.
#[derive(Debug, Serialize, Deserialize)]
pub struct KeystoreFile {
    /// Format version. Currently 1.
    pub version: u32,
    /// 16-byte Argon2 salt, base64-encoded.
    pub salt_b64: String,
    /// 12-byte AES-GCM nonce, base64-encoded.
    pub nonce_b64: String,
    /// 48-byte ciphertext (32 NSK bytes + 16 GCM tag bytes), base64-encoded.
    pub ciphertext_b64: String,
}

#[derive(Debug, thiserror::Error)]
pub enum KeystoreError {
    #[error("base64 decode error: {0}")]
    Base64(#[from] base64::DecodeError),
    #[error("AES-GCM encryption failed")]
    Encrypt,
    #[error("AES-GCM decryption failed (wrong passphrase or corrupted file)")]
    WrongPassphrase,
    #[error("Argon2 KDF error: {0}")]
    Kdf(String),
    #[error("Keystore ciphertext has unexpected length: {0} (expected 48)")]
    BadLength(usize),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Derive a 32-byte AES key from `passphrase` and `salt` using Argon2id defaults.
///
/// Argon2id default parameters (argon2 crate 0.5): m=19456 KiB, t=2, p=1.
/// These are the OWASP-recommended minimum parameters for passphrase hashing.
fn derive_key(passphrase: &str, salt: &[u8; 16]) -> Result<[u8; 32], KeystoreError> {
    let mut key_bytes = [0u8; 32];
    Argon2::default()
        .hash_password_into(passphrase.as_bytes(), salt, &mut key_bytes)
        .map_err(|e| KeystoreError::Kdf(e.to_string()))?;
    Ok(key_bytes)
}

/// Encrypt `nsk` under `passphrase`, returning a serializable `KeystoreFile`.
pub fn encrypt(nsk: &NskBytes, passphrase: &str) -> Result<KeystoreFile, KeystoreError> {
    // Generate random salt and nonce.
    let mut salt = [0u8; 16];
    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut nonce_bytes);

    // KDF.
    let mut key_bytes = derive_key(passphrase, &salt)?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(&nonce_bytes);

    // Encrypt. GCM appends 16-byte authentication tag -> 48 bytes total.
    let ciphertext = cipher
        .encrypt(nonce, nsk.as_ref())
        .map_err(|_| KeystoreError::Encrypt)?;

    // Zero the derived key material before returning.
    key_bytes.zeroize();

    Ok(KeystoreFile {
        version: 1,
        salt_b64: B64.encode(salt),
        nonce_b64: B64.encode(nonce_bytes),
        ciphertext_b64: B64.encode(&ciphertext),
    })
}

/// Decrypt a `KeystoreFile` with `passphrase`, returning the raw NSK bytes.
pub fn decrypt(file: &KeystoreFile, passphrase: &str) -> Result<NskBytes, KeystoreError> {
    if file.version != 1 {
        return Err(KeystoreError::Kdf(format!(
            "unsupported keystore version {}",
            file.version
        )));
    }

    let salt_vec = B64.decode(&file.salt_b64)?;
    let nonce_vec = B64.decode(&file.nonce_b64)?;
    let ciphertext = B64.decode(&file.ciphertext_b64)?;

    if ciphertext.len() != 48 {
        return Err(KeystoreError::BadLength(ciphertext.len()));
    }

    let salt: [u8; 16] = salt_vec
        .try_into()
        .map_err(|_| KeystoreError::Kdf("salt must be 16 bytes".to_string()))?;
    let nonce_arr: [u8; 12] = nonce_vec
        .try_into()
        .map_err(|_| KeystoreError::Kdf("nonce must be 12 bytes".to_string()))?;

    let mut key_bytes = derive_key(passphrase, &salt)?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(&nonce_arr);

    let plaintext = cipher
        .decrypt(nonce, ciphertext.as_ref())
        .map_err(|_| KeystoreError::WrongPassphrase)?;

    key_bytes.zeroize();

    let nsk: NskBytes = plaintext
        .try_into()
        .map_err(|_| KeystoreError::Kdf("decrypted plaintext is not 32 bytes".to_string()))?;

    Ok(nsk)
}

/// Persist a `KeystoreFile` to disk as JSON.
pub fn save(path: &Path, file: &KeystoreFile) -> Result<(), KeystoreError> {
    let json = serde_json::to_vec_pretty(file)?;
    fs::write(path, json)?;
    Ok(())
}

/// Load a `KeystoreFile` from disk.
pub fn load(path: &Path) -> Result<KeystoreFile, KeystoreError> {
    let bytes = fs::read(path)?;
    Ok(serde_json::from_slice(&bytes)?)
}

// ---- Unit tests (no lez-build dependency) --------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn dummy_nsk() -> NskBytes {
        let mut nsk = [0u8; 32];
        for (i, b) in nsk.iter_mut().enumerate() {
            *b = i as u8;
        }
        nsk
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let nsk = dummy_nsk();
        let passphrase = "correct horse battery staple";

        let file = encrypt(&nsk, passphrase).expect("encrypt should succeed");
        assert_eq!(file.version, 1);

        // Ciphertext is 48 bytes base64-encoded.
        let ct_bytes = B64.decode(&file.ciphertext_b64).unwrap();
        assert_eq!(ct_bytes.len(), 48);

        let recovered = decrypt(&file, passphrase).expect("decrypt should succeed");
        assert_eq!(recovered, nsk);
    }

    #[test]
    fn wrong_passphrase_is_rejected() {
        let nsk = dummy_nsk();
        let file = encrypt(&nsk, "right passphrase").expect("encrypt should succeed");

        let result = decrypt(&file, "wrong passphrase");
        assert!(
            matches!(result, Err(KeystoreError::WrongPassphrase)),
            "wrong passphrase must return WrongPassphrase, got: {result:?}"
        );
    }

    #[test]
    fn different_encryptions_of_same_nsk_differ() {
        // Each call generates fresh random salt + nonce, so ciphertexts must differ.
        let nsk = dummy_nsk();
        let pass = "passphrase";

        let f1 = encrypt(&nsk, pass).unwrap();
        let f2 = encrypt(&nsk, pass).unwrap();

        assert_ne!(
            f1.ciphertext_b64, f2.ciphertext_b64,
            "two encryptions of the same key must produce different ciphertexts"
        );
        assert_ne!(f1.salt_b64, f2.salt_b64, "salts must differ");
    }

    #[test]
    fn tampered_ciphertext_is_rejected() {
        let nsk = dummy_nsk();
        let mut file = encrypt(&nsk, "pass").unwrap();

        // Flip a byte in the ciphertext.
        let mut ct = B64.decode(&file.ciphertext_b64).unwrap();
        ct[10] ^= 0xFF;
        file.ciphertext_b64 = B64.encode(&ct);

        let result = decrypt(&file, "pass");
        assert!(
            matches!(result, Err(KeystoreError::WrongPassphrase)),
            "tampered ciphertext must fail authentication"
        );
    }

    #[test]
    fn json_roundtrip() {
        let nsk = dummy_nsk();
        let file = encrypt(&nsk, "pass").unwrap();

        let json = serde_json::to_string(&file).unwrap();
        let restored: KeystoreFile = serde_json::from_str(&json).unwrap();

        let recovered = decrypt(&restored, "pass").unwrap();
        assert_eq!(recovered, nsk);
    }
}
