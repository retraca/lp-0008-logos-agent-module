#pragma once
// Stub API for the Logos Core delivery_module platform dependency.
// The real implementation is injected by logos-core at runtime via LogosAPI.

#include <QString>
#include "logos_api.h"

class DeliveryModule {
public:
    explicit DeliveryModule(LogosAPI* api) : m_api(api) {}

    // Subscribe to a content topic (Waku/Status delivery layer).
    void subscribe(const QString& topic) { (void)topic; }

    // Unsubscribe from a content topic.
    void unsubscribe(const QString& topic) { (void)topic; }

private:
    LogosAPI* m_api;
};
