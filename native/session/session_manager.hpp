// CastSprint Session Manager and Clock Estimator
// Normative specification: docs/architecture/PROTOCOL.md and AUDIO_AND_LAN.md
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
#include <chrono>
#include "castsprint/protocol/protocol.hpp"

namespace castsprint::session {

enum class ConnectionState {
    Disconnected,
    Listening,
    Handshaking,
    Connected,
    Reconnecting,
    Closed
};

struct SessionStats {
    uint64_t totalBytesReceived = 0;
    uint32_t videoFramesReceived = 0;
    uint32_t audioFramesReceived = 0;
    uint32_t keyframesReceived = 0;
    uint32_t droppedFrames = 0;
    double currentFps = 0.0;
    double currentBitrateMbps = 0.0;
    uint64_t lastRttMicros = 0;
    int64_t estimatedClockOffsetMicros = 0;
};

class SessionManager {
public:
    SessionManager();

    // Generates a random 6-digit session PIN and sets up pairing
    void InitializePairing(std::string_view certFingerprintSha256, std::string_view pin = "");

    std::string_view SessionPin() const noexcept { return sessionPin_; }
    std::string_view CertificateFingerprint() const noexcept { return certFingerprint_; }
    ConnectionState State() const noexcept { return state_; }
    uint32_t SessionId() const noexcept { return sessionId_; }

    // Evaluates an incoming Hello message
    // Returns pair: (HelloAck to send, bool isAccepted)
    std::pair<protocol::HelloAck, bool> ProcessHello(const protocol::Hello& hello, std::string_view providedPin);

    // Creates an outbound Heartbeat packet with current timestamp
    protocol::Heartbeat CreateHeartbeat(uint64_t nowMicros);

    // Processes an incoming echoed Heartbeat to update RTT and clock offset
    void ProcessHeartbeatResponse(const protocol::Heartbeat& hb, uint64_t nowMicros);

    // Frame tracking
    void OnVideoFrameReceived(uint32_t payloadBytes, bool isKeyframe);
    void OnAudioFrameReceived(uint32_t payloadBytes);
    void OnFrameDropped();

    // Updates rolling FPS and bitrate calculations
    void UpdatePeriodicStats(uint64_t nowMicros);

    const SessionStats& Stats() const noexcept { return stats_; }

    void SetState(ConnectionState state) noexcept { state_ = state; }
    void Reset();

private:
    ConnectionState state_ = ConnectionState::Disconnected;
    std::string sessionPin_;
    std::string certFingerprint_;
    uint32_t sessionId_ = 0;

    SessionStats stats_;

    // Periodic rate calculation
    uint64_t lastStatsUpdateMicros_ = 0;
    uint64_t bytesSinceLastStats_ = 0;
    uint32_t framesSinceLastStats_ = 0;

    // Heartbeat tracking
    uint64_t lastSentHeartbeatMicros_ = 0;
};

}  // namespace castsprint::session
