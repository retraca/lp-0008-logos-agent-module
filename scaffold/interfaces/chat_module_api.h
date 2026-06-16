#pragma once
#include <string>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <functional>
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_object.h"

class ChatModule {
public:
    explicit ChatModule(const std::string& module_name)
        : m_api(new LogosAPI(QString::fromStdString(module_name))),
          m_client(m_api->getClient(QString::fromStdString(module_name))) {}

    explicit ChatModule(LogosAPI* api)
        : m_api(api), m_owns(false), m_client(api->getClient("chat_module")) {}

    // Open a 1:1 E2E encrypted conversation.
    // Returns JSON {"convoId":"...", "status":"..."}
    QString newPrivateConversation(const QString& introBundleStr, const QString& contentHex) {
        QVariant r = m_client->invokeRemoteMethod(
            "chat_module", "newPrivateConversation",
            QVariant(introBundleStr), QVariant(contentHex));
        return r.toString();
    }

    // Send a message to an existing conversation.
    bool sendMessage(const QString& convoId, const QString& hexContent) {
        QVariant r = m_client->invokeRemoteMethod(
            "chat_module", "sendMessage",
            QVariant(convoId), QVariant(hexContent));
        return r.toBool();
    }

    // Get the chat module's own intro bundle (for publishing in agent_card).
    QString createIntroBundle() {
        QVariant r = m_client->invokeRemoteMethod("chat_module", "createIntroBundle");
        return r.toString();
    }

    // List known conversations.
    QString listConversations() {
        QVariant r = m_client->invokeRemoteMethod("chat_module", "listConversations");
        return r.toString();
    }

    // Get own identity / chat public key.
    QString getIdentity() {
        QVariant r = m_client->invokeRemoteMethod("chat_module", "getIdentity");
        return r.toString();
    }

private:
    LogosAPI* m_api;
    bool m_owns = true;
    LogosAPIClient* m_client;
};
