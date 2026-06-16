#ifndef LOGOS_MODE_H
#define LOGOS_MODE_H

// Compatibility shim — logos_mode.h was removed from logos-cpp-sdk 0.2.0.
// This shim re-exports the same types so code written against 0.1.x still
// compiles.  Only packaging glue; no logic added.

#include <QDebug>

enum class LogosMode {
    Remote,
    Local,
    Mock
};

struct Timeout {
    int ms;
    explicit Timeout(int milliseconds = 20000) : ms(milliseconds) {}
};

namespace LogosModeConfig {

    inline LogosMode& modeStorage() {
        static LogosMode mode = LogosMode::Remote;
        return mode;
    }

    inline void setMode(LogosMode mode) {
        modeStorage() = mode;
        QString modeName = (mode == LogosMode::Local) ? "Local"
                         : (mode == LogosMode::Mock)  ? "Mock"
                                                       : "Remote";
        qDebug() << "LogosModeConfig: Mode set to" << modeName;
    }

    inline LogosMode getMode() {
        return modeStorage();
    }

    inline bool isLocal()  { return modeStorage() == LogosMode::Local;  }
    inline bool isRemote() { return modeStorage() == LogosMode::Remote; }
    inline bool isMock()   { return modeStorage() == LogosMode::Mock;   }
}

#endif // LOGOS_MODE_H
