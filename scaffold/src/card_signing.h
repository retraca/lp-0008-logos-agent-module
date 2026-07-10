// card_signing.h — A2A AgentCardSignature: detached JWS (RFC 7515), EdDSA/Ed25519.
//
// The A2A spec's AgentCardSignature is a JWS over the canonical card JSON:
//   protected header (b64url) . payload (b64url, detached) . signature (b64url)
// We sign with an Ed25519 key the agent generates once and persists in its module
// config; the public key ships in the signature's unprotected header as a JWK so any
// A2A client can verify without extra lookups. Crypto: vendored TweetNaCl (public
// domain, Bernstein et al.) — crypto_sign is Ed25519.
#pragma once
#include <string>
#include <vector>
#include <cstdint>
#include <stdexcept>
#include <fstream>

extern "C" {
#include "tweetnacl.h"
}

// TweetNaCl requires the embedder to provide randombytes(). Declared here with C
// linkage; DEFINED (non-inline) in agent_module_impl.cpp so the C object file
// tweetnacl.o resolves the symbol at link time — an inline definition is not
// guaranteed to be emitted and leaves the .so with an undefined symbol that only
// explodes on the first agent_card call.
extern "C" void randombytes(unsigned char* buf, unsigned long long n);

namespace cardsig {

inline std::string b64url(const unsigned char* data, size_t len) {
    static const char* T = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        uint32_t v = data[i] << 16;
        if (i + 1 < len) v |= data[i + 1] << 8;
        if (i + 2 < len) v |= data[i + 2];
        out += T[(v >> 18) & 63];
        out += T[(v >> 12) & 63];
        if (i + 1 < len) out += T[(v >> 6) & 63];
        if (i + 2 < len) out += T[v & 63];
    }
    return out; // no padding, per RFC 7515 b64url
}
inline std::string b64url(const std::string& s) {
    return b64url(reinterpret_cast<const unsigned char*>(s.data()), s.size());
}

inline std::string hex(const unsigned char* d, size_t n) {
    static const char* H = "0123456789abcdef";
    std::string s; s.reserve(n * 2);
    for (size_t i = 0; i < n; ++i) { s += H[d[i] >> 4]; s += H[d[i] & 15]; }
    return s;
}
inline std::vector<unsigned char> unhex(const std::string& s) {
    auto nib = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    std::vector<unsigned char> out;
    if (s.size() % 2) return out;
    out.reserve(s.size() / 2);
    for (size_t i = 0; i + 1 < s.size(); i += 2) {
        int hi = nib(s[i]), lo = nib(s[i + 1]);
        if (hi < 0 || lo < 0) return {};
        out.push_back(static_cast<unsigned char>((hi << 4) | lo));
    }
    return out;
}

struct Keypair { std::string pk_hex; std::string sk_hex; };

// Generate an Ed25519 keypair (64-byte secret incl. public half, per NaCl convention).
inline Keypair generate() {
    unsigned char pk[crypto_sign_PUBLICKEYBYTES], sk[crypto_sign_SECRETKEYBYTES];
    crypto_sign_keypair(pk, sk);
    return {hex(pk, sizeof pk), hex(sk, sizeof sk)};
}

// Detached Ed25519 signature over `msg` (first 64 bytes of the NaCl signed message).
inline std::string sign_detached_b64url(const std::string& msg, const std::string& sk_hex) {
    auto sk = unhex(sk_hex);
    if (sk.size() != crypto_sign_SECRETKEYBYTES) throw std::runtime_error("card_signing: bad secret key");
    std::vector<unsigned char> sm(msg.size() + crypto_sign_BYTES);
    unsigned long long smlen = 0;
    crypto_sign(sm.data(), &smlen,
                reinterpret_cast<const unsigned char*>(msg.data()), msg.size(), sk.data());
    return b64url(sm.data(), crypto_sign_BYTES);
}

// Verify helper (used by the self-check + peers): detached b64url sig over msg.
inline bool verify_detached(const std::string& msg, const std::string& sig_b64url, const std::string& pk_hex) {
    auto pk = unhex(pk_hex);
    if (pk.size() != crypto_sign_PUBLICKEYBYTES) return false;
    // decode b64url
    auto dec6 = [](char c) -> int {
        if (c >= 'A' && c <= 'Z') return c - 'A';
        if (c >= 'a' && c <= 'z') return c - 'a' + 26;
        if (c >= '0' && c <= '9') return c - '0' + 52;
        if (c == '-') return 62;
        if (c == '_') return 63;
        return -1;
    };
    std::vector<unsigned char> sig;
    uint32_t buf = 0; int bits = 0;
    for (char c : sig_b64url) {
        int v = dec6(c);
        if (v < 0) return false;
        buf = (buf << 6) | v; bits += 6;
        if (bits >= 8) { bits -= 8; sig.push_back((buf >> bits) & 0xFF); }
    }
    if (sig.size() != crypto_sign_BYTES) return false;
    std::vector<unsigned char> sm(sig.size() + msg.size());
    std::copy(sig.begin(), sig.end(), sm.begin());
    std::copy(msg.begin(), msg.end(), sm.begin() + sig.size());
    std::vector<unsigned char> m(sm.size());
    unsigned long long mlen = 0;
    return crypto_sign_open(m.data(), &mlen, sm.data(), sm.size(), pk.data()) == 0;
}

} // namespace cardsig
