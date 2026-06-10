// lez-wallet-core: public surface
//
// The crate has two distinct layers:
//
//   1. `keystore` + `keys`: standalone, light deps only, always compiled.
//      These can be tested on any machine with `cargo test --features standalone-tests`.
//
//   2. `provider` + `ffi`: heavy, depend on the lez-build crate tree.
//      Gated behind `--features lez-bridge`. DO NOT compile on a machine without
//      Risc0, logos-blockchain-circuits, and the lez-build workspace present.

pub mod keystore;
pub mod keys;

#[cfg(feature = "lez-bridge")]
pub mod provider;

#[cfg(feature = "lez-bridge")]
pub mod ffi;
