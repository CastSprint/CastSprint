#include <cstdio>
#include <cstdlib>
#include <string>
#include "session_manager.hpp"

using namespace castsprint::session;
using namespace castsprint::protocol;

namespace {
int g_failures = 0;
int g_checks = 0;

#define CHECK(cond)                                                                      \
    do {                                                                                 \
        ++g_checks;                                                                      \
        if (!(cond)) {                                                                   \
            ++g_failures;                                                                \
            std::fprintf(stderr, "%s:%d CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                                \
    } while (0)

void TestPairingAndHello() {
    SessionManager sm;
    sm.InitializePairing("E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855", "123456");
    CHECK(sm.SessionPin() == "123456");
    CHECK(sm.State() == ConnectionState::Disconnected);

    Hello hello;
    hello.minVersion = 1;
    hello.maxVersion = 1;
    hello.capabilities = kCapVideoH264 | kCapAudio;

    // Reject on bad PIN
    auto [ackBad, okBad] = sm.ProcessHello(hello, "654321");
    CHECK(!okBad);
    CHECK(ackBad.status == HelloStatus::Rejected);
    CHECK(sm.State() == ConnectionState::Disconnected);

    // Accept on valid PIN
    auto [ackOk, okGood] = sm.ProcessHello(hello, "123456");
    CHECK(okGood);
    CHECK(ackOk.status == HelloStatus::Accepted);
    CHECK(ackOk.assignedSessionId > 0);
    CHECK(sm.State() == ConnectionState::Connected);
}

void TestVersionIncompatible() {
    SessionManager sm;
    sm.InitializePairing("dummy", "123456");

    Hello helloFuture;
    helloFuture.minVersion = 2;
    helloFuture.maxVersion = 3;

    auto [ack, ok] = sm.ProcessHello(helloFuture, "123456");
    CHECK(!ok);
    CHECK(ack.status == HelloStatus::VersionUnsupported);
}

void TestHeartbeatAndClockOffset() {
    SessionManager sm;
    sm.InitializePairing("dummy", "123456");

    const uint64_t t0 = 1'000'000;
    auto hb = sm.CreateHeartbeat(t0);
    CHECK(hb.timestampMicros == t0);

    // Simulate Android receiver echoing back t0 at Android time 5'000'000
    // Received at Windows at t1 = 1'020'000 (RTT = 20'000 us = 20ms)
    Heartbeat echo;
    echo.timestampMicros = 5'000'000;      // Android clock
    echo.echoTimestampMicros = t0;         // Windows t0
    const uint64_t t1 = 1'020'000;

    sm.ProcessHeartbeatResponse(echo, t1);
    CHECK(sm.Stats().lastRttMicros == 20'000);
    // Estimated Win time at Android = 1'000'000 + 10'000 = 1'010'000
    // Offset = 5'000'000 - 1'010'000 = 3'990'000 us
    CHECK(sm.Stats().estimatedClockOffsetMicros == 3'990'000);
}

void TestFrameStats() {
    SessionManager sm;
    sm.OnVideoFrameReceived(100'000, true);
    sm.OnVideoFrameReceived(50'000, false);
    sm.OnAudioFrameReceived(1'000);
    sm.OnFrameDropped();

    CHECK(sm.Stats().videoFramesReceived == 2);
    CHECK(sm.Stats().keyframesReceived == 1);
    CHECK(sm.Stats().audioFramesReceived == 1);
    CHECK(sm.Stats().droppedFrames == 1);
    CHECK(sm.Stats().totalBytesReceived == 151'000);
}
}  // namespace

int main() {
    TestPairingAndHello();
    TestVersionIncompatible();
    TestHeartbeatAndClockOffset();
    TestFrameStats();

    std::printf("session_tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
