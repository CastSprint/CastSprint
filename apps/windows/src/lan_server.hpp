#pragma once
// CastSprint Windows Native LAN Receiver & Security Server
// Normative specification: docs/architecture/AUDIO_AND_LAN.md
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <wincrypt.h>
#define SECURITY_WIN32
#include <security.h>
#include <schnlsp.h>

#include <cstdint>
#include <atomic>
#include <string>
#include <vector>
#include <thread>
#include <functional>
#include <span>

#include "castsprint/protocol/protocol.hpp"
#include "castsprint/session/session_manager.hpp"

namespace castsprint::windows {

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

    // Initializes Windows SChannel certificate and starts listening on port
    bool Start(uint16_t port, LanCallbacks callbacks);
    void Stop();

    bool IsRunning() const noexcept { return isRunning_.load(); }
    std::string_view SessionPin() const noexcept { return sessionManager_.SessionPin(); }
    std::string_view CertificateFingerprintSha256() const noexcept { return certFingerprintHex_; }
    std::string PairingUri(std::string_view localIp) const;

    const session::SessionStats& Stats() const noexcept { return sessionManager_.Stats(); }
    session::ConnectionState State() const noexcept { return sessionManager_.State(); }

private:
    bool GenerateSelfSignedCert();
    void CleanupCert();
    void ServerAcceptLoop();
    void HandleClient(SOCKET clientSock);

    bool PerformTlsHandshake(SOCKET sock, CtxtHandle* phContext, SecBufferDesc* pOutBuffer);
    bool ReadEncryptedMessage(SOCKET sock, CtxtHandle* phContext, std::vector<uint8_t>& decBuffer);
    bool SendEncryptedMessage(SOCKET sock, CtxtHandle* phContext, std::span<const uint8_t> plainData);

    std::atomic<bool> isRunning_{false};
    uint16_t port_ = protocol::kDefaultPort;
    SOCKET listenSocket_ = INVALID_SOCKET;
    std::thread serverThread_;

    LanCallbacks callbacks_;
    session::SessionManager sessionManager_;

    PCCERT_CONTEXT certContext_ = nullptr;
    HCRYPTPROV hCryptProv_ = 0;
    CredHandle hServerCred_{};
    bool hasCredHandle_ = false;
    std::string certFingerprintHex_;
};

}  // namespace castsprint::windows
