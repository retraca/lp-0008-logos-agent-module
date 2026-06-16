#pragma once
#include <string>
#include <QString>
#include <QByteArray>
#include <QVariant>
#include <QVariantList>
#include "logos_api.h"
#include "logos_api_client.h"

class DeliveryModule {
public:
    explicit DeliveryModule(const std::string& module_name)
        : m_api(new LogosAPI(QString::fromStdString(module_name))),
          m_client(m_api->getClient(QString::fromStdString(module_name))) {}

    explicit DeliveryModule(LogosAPI* api)
        : m_api(api), m_owns(false), m_client(api->getClient("delivery_module")) {}

    // Subscribe to a Waku content topic.
    bool subscribe(const QString& contentTopic) {
        QVariant r = m_client->invokeRemoteMethod(
            "delivery_module", "subscribe", QVariant(contentTopic));
        return r.toBool();
    }

    // Unsubscribe from a content topic.
    bool unsubscribe(const QString& contentTopic) {
        QVariant r = m_client->invokeRemoteMethod(
            "delivery_module", "unsubscribe", QVariant(contentTopic));
        return r.toBool();
    }

    // Publish a message to a content topic (payload as QByteArray).
    bool send(const QString& contentTopic, const QByteArray& payload) {
        // Pass as two-arg: content topic + payload wrapped in QVariant(QByteArray).
        // Some versions of the RPC layer handle QByteArray natively; fall back to
        // passing as a hex string if the call fails.
        QVariant r = m_client->invokeRemoteMethod(
            "delivery_module", "send",
            QVariant(contentTopic), QVariant::fromValue(payload));
        return r.toBool();
    }

    // Convenience overload with UTF-8 string payload.
    bool sendString(const QString& contentTopic, const QString& payload) {
        QByteArray ba = payload.toUtf8();
        return send(contentTopic, ba);
    }

private:
    LogosAPI* m_api;
    bool m_owns = true;
    LogosAPIClient* m_client;
};
