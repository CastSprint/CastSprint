#pragma once
#include <cstdint>
#include <atomic>
#include <string>
#include <vector>
#include <thread>
#include <functional>
#include <span>

#include "castsprint/protocol/protocol.hpp"
#include "session_manager.hpp"

namespace castsprint::linux_app {

struct LanCallbacks {
    std::function<void(const protocol::VideoConfig&)> onVideoConfig;
    std::function<void(const protocol::VideoFrame&)> onVideoFrame;
    std::function<void(const protocol::AudioConfig&)> onAudioConfig;
    std::function<void(const protocol::AudioFrame&)> onAudioFrame;
    std::function<void(session::ConnectionState)> onStateChanged;
};

class LanServer {
public:
    LanServer();
    ~LanServer();

    LanServer(const LanServer&) = delete;
    LanServer& operator=(const LanServer&) = delete;

    bool Start(uint16_t port, LanCallbacks callbacks);
    void Stop();

    bool IsRunning() const noexcept { return isRunning_.load(); }
    std::string_view SessionPin() const noexcept { return sessionManager_.SessionPin(); }

    const session::SessionStats& Stats() const noexcept { return sessionManager_.Stats(); }
    session::ConnectionState State() const noexcept { return sessionManager_.State(); }

private:
    void ServerAcceptLoop();
    void HandleClient(int clientSock);

    std::atomic<bool> isRunning_{false};
    uint16_t port_{27183};
    int listenSock_{-1};
    std::thread acceptThread_;
    std::thread clientThread_;
    int activeClientSock_{-1};

    session::SessionManager sessionManager_;
    LanCallbacks callbacks_;
};

} // namespace castsprint::linux_app
