# Deployment Guide

## Prerequisites

- Nix with flakes (`experimental-features = nix-command flakes` in `~/.config/nix/nix.conf`)
- Rust stable (`rustup install stable`)
- Docker with Colima or Docker Desktop
- `logoscore` (Logos Core daemon) on PATH

## 1. Build the Rust wallet core

```bash
cd lez-wallet-module/lez-wallet-core
cargo build --release --features lez-bridge
```

This produces `target/release/liblez_wallet_core.a` (static lib) and the cbindgen header.

## 2. Regenerate the FFI header (optional -- committed header is current)

```bash
cbindgen --crate lez-wallet-core --output ../qt-module/lez_wallet_ffi.h
```

## 3. Build the Qt modules

The Nix dev shell provides all C++ deps. If Nix disk is tight, invoke tools directly:

```bash
cd lez-wallet-module/qt-module

LOGOS_CPP_SDK_ROOT=/nix/store/78y89h0z2rdaqjv4ks6bhy8rlhlpbv2c-logos-cpp-sdk
LOGOS_CPP_SDK_LIB=/nix/store/32vx5afm4528y1ilajww0fcr2aw236g0-logos-cpp-sdk-lib-0.1.0
QT_BASE=/nix/store/hf3xciirv7m7j08jbxsbi0ayrarfvy1y-qtbase-6.11.0
QT_RO=/nix/store/vaznnkzhh9gyb7qjr2aiv858g9pbfm9n-qtremoteobjects-6.11.0
NLOHMANN=/nix/store/mdvd0ffl5id9zj9qmhmh3yya5z17y31z-nlohmann_json-3.11.3
BOOST=/nix/store/2blqfsz18yp066ky15nvkihcvwqq7bqz-boost-1.87.0-dev
OPENSSL=/nix/store/a3hhkd5vzw97issax60xx47qfnkl6ddf-openssl-3.6.2
OPENSSL_DEV=/nix/store/8g69q86jfk5rpa34gny4rh057h5yb1nw-openssl-3.6.2-dev
GENERATOR=/nix/store/yc3zmryx6rwlvl406b0fzzn20czdqfyj-logos-cpp-sdk-generator-0.1.0/bin
LEZ_CORE=$(pwd)/../lez-wallet-core/target/release

cmake -S . -B build -GNinja \
  -DCMAKE_PREFIX_PATH="$LOGOS_CPP_SDK_LIB;$QT_BASE;$QT_RO;$NLOHMANN;$BOOST;$OPENSSL;$OPENSSL_DEV" \
  -DLOGOS_CPP_SDK_ROOT="$LOGOS_CPP_SDK_ROOT" \
  -DLEZ_WALLET_CORE_DIR="$LEZ_CORE" \
  -DOPENSSL_ROOT_DIR="$OPENSSL" \
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_DEV/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL/lib/libcrypto.dylib" \
  -DOPENSSL_SSL_LIBRARY="$OPENSSL/lib/libssl.dylib"

PATH=$GENERATOR:$PATH ninja -C build
# Output: build/liblez_wallet_module_plugin.so
```

Repeat for `lp-0008-ai-module/scaffold/` (same cmake flags, no `LEZ_WALLET_CORE_DIR`).

## 4. Build the CLI

```bash
cd lez-wallet-module/lez-agent-cli
cargo build --release
# Output: target/release/lez
```

## 5. Start the local LEZ chain

```bash
cd lez-build
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker-compose up -d
```

Wait for the sequencer to be healthy:

```bash
until curl -sf http://127.0.0.1:3040/health; do sleep 3; done
```

## 6. Deploy an agent

```bash
AGENT_HOME=~/.lez-agents/agent1
mkdir -p $AGENT_HOME

# Create the agent's shielded account
./lez-wallet-module/lez-agent-cli/target/release/lez \
  ensure-account --home $AGENT_HOME --passphrase "your-passphrase"

# Get the agent's NPK (shielded identity for the Agent Card)
./lez-wallet-module/lez-agent-cli/target/release/lez \
  npk --home $AGENT_HOME --passphrase "your-passphrase"
```

## 7. Load modules into Logos Core

```bash
logoscore -D \
  -m lez-wallet-module/qt-module/liblez_wallet_module_plugin.so \
  -m lp-0008-ai-module/scaffold/libagent_module_plugin.so

# Configure the agent
logoscore -c 'lez_wallet_module.ensure_account("your-passphrase")'
logoscore -c 'agent_module.meta_configure("owner_address", "<owner-npk>")'
logoscore -c 'agent_module.meta_configure("per_tx_limit", "10.0")'
logoscore -c 'agent_module.meta_configure("per_period_limit", "100.0")'
logoscore -c 'agent_module.meta_configure("period_seconds", "86400")'

# Verify
logoscore -c 'agent_module.meta_status()'
logoscore -c 'agent_module.meta_skills()'
```

## Three-agent deployment (Storage / Messaging / Blockchain)

Deploy one agent per skill category with separate home directories:

```bash
for AGENT in storage-agent messaging-agent blockchain-agent; do
  mkdir -p ~/.lez-agents/$AGENT
  ./lez ensure-account --home ~/.lez-agents/$AGENT --passphrase "agent-pass"
  ./lez npk --home ~/.lez-agents/$AGENT --passphrase "agent-pass"
done
```

Load each in its own `logoscore -D` instance, each with the shared modules.
Configure each agent's `owner_address` to the same owner NPK so all three respond
to the owner's chat channel.
