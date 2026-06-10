#pragma once
// Stub API for the Logos Core storage_module platform dependency.
// The real implementation is injected by logos-core at runtime via LogosAPI.

#include <QString>
#include "logos_api.h"

class StorageModule {
public:
    explicit StorageModule(LogosAPI* api) : m_api(api) {}

    // Upload a file at `url` to Logos Storage.
    // `chunkSize` 0 = default. Returns a session ID string.
    QString uploadUrl(const QString& url, int64_t chunkSize) {
        (void)url; (void)chunkSize;
        return {};
    }

    // Download a CID to a local URL.
    // `local` = true stores to disk.
    void downloadToUrl(const QString& cid, const QString& destUrl, bool local, int64_t chunkSize) {
        (void)cid; (void)destUrl; (void)local; (void)chunkSize;
    }

    // Return a JSON array of manifests for stored content.
    QString manifests() { return "[]"; }

private:
    LogosAPI* m_api;
};
