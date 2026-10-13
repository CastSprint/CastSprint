#include "session_manager.hpp"
#include <random>

namespace castsprint::session {

SessionManager::SessionManager() {
    Reset();
}

void SessionManager::InitializePairing(std::string_view certFingerprintSha256, std::string_view pin) {
    certFingerprint_ = certFingerprintSha256;
    if (!pin.empty()) {
        sessionPin_ = pin;
    } else {
        // Generate random 6-digit numeric PIN
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<int> dist(100000, 999999);
        sessionPin_ = std::to_string(dist(gen));
    }
}

void SessionManager::Reset() {
    state_ = ConnectionState::Disconnected;
    sessionId_ = 0;
    stats_ = SessionStats{};
    lastStatsUpdateMicros_ = 0;
    bytesSinceLastStats_ = 0;
    framesSinceLastStats_ = 0;
    lastSentHeartbeatMicros_ = 0;
}

std::pair<protocol::HelloAck, bool> SessionManager::ProcessHello(const protocol::Hello& hello, std::string_view providedPin) {
    protocol::HelloAck ack{};

    // Check version compatibility
    if (hello.minVersion > protocol::kVersion || hello.maxVersion < protocol::kVersion) {
        ack.status = protocol::HelloStatus::VersionUnsupported;
        ack.acceptedVersion = protocol::kVersion;
        return {ack, false};
    }

    // Verify session pairing token (PIN) if pairing is initialized
    if (!sessionPin_.empty() && providedPin != sessionPin_) {
        ack.status = protocol::HelloStatus::Rejected;
        ack.acceptedVersion = protocol::kVersion;
        return {ack, false};
    }

    // Assign session ID
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint32_t> dist(1, 0xFFFFFFFE);
    sessionId_ = dist(gen);

    ack.status = protocol::HelloStatus::Accepted;
    ack.acceptedVersion = protocol::kVersion;
    ack.assignedSessionId = sessionId_;
    ack.maxPayloadSize = protocol::kMaxPayloadSize;

    state_ = ConnectionState::Connected;
    return {ack, true};
}

protocol::Heartbeat SessionManager::CreateHeartbeat(uint64_t nowMicros) {
    lastSentHeartbeatMicros_ = nowMicros;
    protocol::Heartbeat hb{};
    hb.timestampMicros = nowMicros;
    hb.echoTimestampMicros = 0;
    return hb;
}

void SessionManager::ProcessHeartbeatResponse(const protocol::Heartbeat& hb, uint64_t nowMicros) {
    if (hb.echoTimestampMicros > 0 && nowMicros >= hb.echoTimestampMicros) {
        const uint64_t rtt = nowMicros - hb.echoTimestampMicros;
        stats_.lastRttMicros = rtt;

        // Cross-device clock offset estimate:
        // offset = t_android - (t0_win + RTT/2)
        const uint64_t estimatedWinTimeAtAndroid = hb.echoTimestampMicros + (rtt / 2);
        const int64_t offset = static_cast<int64_t>(hb.timestampMicros) - static_cast<int64_t>(estimatedWinTimeAtAndroid);
        stats_.estimatedClockOffsetMicros = offset;
    }
}

void SessionManager::OnVideoFrameReceived(uint32_t payloadBytes, bool isKeyframe) {
    stats_.totalBytesReceived += payloadBytes;
    bytesSinceLastStats_ += payloadBytes;
    stats_.videoFramesReceived++;
    framesSinceLastStats_++;
    if (isKeyframe) {
        stats_.keyframesReceived++;
    }
}

void SessionManager::OnAudioFrameReceived(uint32_t payloadBytes) {
    stats_.totalBytesReceived += payloadBytes;
    bytesSinceLastStats_ += payloadBytes;
    stats_.audioFramesReceived++;
}

void SessionManager::OnFrameDropped() {
    stats_.droppedFrames++;
}

void SessionManager::UpdatePeriodicStats(uint64_t nowMicros) {
    if (lastStatsUpdateMicros_ == 0) {
        lastStatsUpdateMicros_ = nowMicros;
        return;
    }

    const uint64_t elapsed = nowMicros - lastStatsUpdateMicros_;
    if (elapsed >= 500'000) {  // update every 500ms
        const double elapsedSec = static_cast<double>(elapsed) / 1'000'000.0;
        stats_.currentFps = static_cast<double>(framesSinceLastStats_) / elapsedSec;
        stats_.currentBitrateMbps = (static_cast<double>(bytesSinceLastStats_ * 8)) / (elapsedSec * 1'000'000.0);

        lastStatsUpdateMicros_ = nowMicros;
        bytesSinceLastStats_ = 0;
        framesSinceLastStats_ = 0;
    }
}

}  // namespace castsprint::session
