#pragma once
// Stub API for the Logos Core chat_module platform dependency.
// The real implementation is injected by logos-core at runtime via LogosAPI.
// This stub exists only to satisfy the compiler; all calls go through logos_api_client.h
// at link time via the remote-objects dispatch layer.

#include <QString>
#include <QVariant>
#include "logos_api.h"

class ChatModule {
public:
    explicit ChatModule(LogosAPI* api) : m_api(api) {}

    // Open a 1:1 E2E encrypted conversation with `recipient` (intro-bundle string).
    // Sends `initialMessage` (hex-encoded) as the first message.
    // Returns a JSON object with {"convoId": "...", "status": "..."}.
    QString newPrivateConversation(const QString& recipient, const QString& initialMessage) {
        (void)recipient; (void)initialMessage;
        return "{}";
    }

    // Send a message to an existing conversation.
    void sendMessage(const QString& convoId, const QString& hexContent) {
        (void)convoId; (void)hexContent;
    }

private:
    LogosAPI* m_api;
};
