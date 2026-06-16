#pragma once
#include <QString>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_types.h"

class StorageModule {
public:
    explicit StorageModule(LogosAPI* api)
        : m_api(api), m_client(api->getClient("storage_module")) {}

    // Upload a file at `url` (file:// URL) to Logos Storage.
    // Returns a LogosResult; check .value for session_id.
    LogosResult uploadUrl(const QUrl& url, int chunkSize = 0) {
        QVariant r = m_client->invokeRemoteMethod(
            "storage_module", "uploadUrl",
            QVariant::fromValue(url), QVariant(chunkSize));
        return r.value<LogosResult>();
    }

    // Upload using QString URL (convenience).
    LogosResult uploadUrl(const QString& url, int64_t chunkSize = 0) {
        return uploadUrl(QUrl(url), static_cast<int>(chunkSize));
    }

    // Download a CID to a local path.
    LogosResult downloadToUrl(const QString& cid, const QString& destUrl, bool local = true) {
        QVariant r = m_client->invokeRemoteMethod(
            "storage_module", "downloadToUrl",
            QVariant(cid), QVariant::fromValue(QUrl(destUrl)), QVariant(local));
        return r.value<LogosResult>();
    }

    // Return a LogosResult containing JSON array of manifests.
    LogosResult manifests() {
        QVariant r = m_client->invokeRemoteMethod("storage_module", "manifests");
        return r.value<LogosResult>();
    }

    // Check if a CID exists.
    LogosResult exists(const QString& cid) {
        QVariant r = m_client->invokeRemoteMethod("storage_module", "exists", QVariant(cid));
        return r.value<LogosResult>();
    }

private:
    LogosAPI* m_api;
    LogosAPIClient* m_client;
};
