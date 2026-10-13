#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "av_sync.hpp"

using namespace castsprint::sync;

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

void TestNoAudioClock() {
    AvSynchronizer sync;
    auto decision = sync.EvaluateVideoFrame(100'000, 50'000);
    CHECK(decision.action == VideoAction::PresentNow);
    CHECK(decision.waitMicros == 0);
}

void TestOnTimeAndWaiting() {
    AvSynchronizer sync(SyncPreset::Balanced);

    // Audio rendered at pts 1'000'000 us at host time 500'000 us
    sync.OnAudioRendered(1'000'000, 500'000);

    // 10ms later in host time (host time = 510'000 us)
    // Effective audio PTS is 1'010'000 us.
    // Video frame at 1'015'000 us is only 5ms ahead -> within on-time window (16.6ms)
    auto d1 = sync.EvaluateVideoFrame(1'015'000, 510'000);
    CHECK(d1.action == VideoAction::PresentNow);
    CHECK(d1.waitMicros == 0);

    // Video frame at 1'050'000 us is 40ms ahead -> should Wait
    auto d2 = sync.EvaluateVideoFrame(1'050'000, 510'000);
    CHECK(d2.action == VideoAction::Wait);
    CHECK(d2.waitMicros == 40'000);

    // Video frame at 950'000 us is 60ms behind (> 50ms drop threshold) -> should DropLate
    auto d3 = sync.EvaluateVideoFrame(950'000, 510'000);
    CHECK(d3.action == VideoAction::DropLate);
}

void TestUserAudioOffset() {
    AvSynchronizer sync(SyncPreset::Balanced);
    sync.OnAudioRendered(1'000'000, 500'000);

    // Add +30ms user audio offset (audio is delayed by 30ms)
    sync.SetUserAudioOffsetMicros(30'000);

    // Effective audio PTS becomes 1'000'000 + 30'000 = 1'030'000 us
    // Video frame at 1'030'000 us should now be PresentNow
    auto d = sync.EvaluateVideoFrame(1'030'000, 500'000);
    CHECK(d.action == VideoAction::PresentNow);
    CHECK(d.skewMicros == 0);
}

void TestReset() {
    AvSynchronizer sync(SyncPreset::Balanced);
    sync.OnAudioRendered(1'000'000, 500'000);
    sync.Reset();

    auto d = sync.EvaluateVideoFrame(1'000'000, 500'000);
    CHECK(d.action == VideoAction::PresentNow);
}
}  // namespace

int main() {
    TestNoAudioClock();
    TestOnTimeAndWaiting();
    TestUserAudioOffset();
    TestReset();

    std::printf("sync_tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
