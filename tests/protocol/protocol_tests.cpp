#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

#include "castsprint/protocol/protocol.hpp"

using namespace castsprint::protocol;

namespace {
int g_failures = 0;
int g_checks = 0;
#define CHECK(cond)                                                              \
    do {                                                                         \
        ++g_checks;                                                              \
        if (!(cond)) {                                                           \
            ++g_failures;                                                        \
            std::fprintf(stderr, "%s:%d CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                        \
    } while (0)

std::vector<std::uint8_t> Encode(const Payload& p, std::uint32_t session = 0xA1B2C3D4, std::uint32_t seq = 7) {
    std::vector<std::uint8_t> out;
    bool ok = EncodeMessage(session, seq, p, out);
    CHECK(ok);
    return out;
}

template <typename T>
T RoundTrip(const T& in) {
    auto bytes = Encode(in);
    Message msg;
    std::size_t consumed = 0;
    auto err = DecodeMessage(bytes, msg, consumed);
    CHECK(err == DecodeError::None);
    CHECK(consumed == bytes.size());
    CHECK(msg.header.sessionId == 0xA1B2C3D4);
    CHECK(msg.header.sequence == 7);
    CHECK(msg.header.type == TypeOf(Payload{in}));
    CHECK(std::holds_alternative<T>(msg.payload));
    return std::holds_alternative<T>(msg.payload) ? std::get<T>(msg.payload) : T{};
}

DecodeError DecodeErr(const std::vector<std::uint8_t>& b) {
    Message m;
    std::size_t c = 0;
    return DecodeMessage(b, m, c);
}

void TestGoldenHeartbeat() {
    // Golden vector shared with Android ProtocolCodecTest — keep in sync.
    Heartbeat hb{0x0102030405060708ull, 0x1112131415161718ull};
    auto b = Encode(hb, 0x00000001, 0x00000002);
    const std::vector<std::uint8_t> expected = {
        0x43, 0x53, 0x50, 0x52, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    };
    CHECK(b == expected);
}

void TestRoundTrips() {
    Hello h;
    h.capabilities = kCapVideoH264 | kCapAudio;
    h.androidApiLevel = 34; h.screenWidth = 1080; h.screenHeight = 2400; h.densityDpi = 420;
    h.deviceName = "Pixel 8"; h.deviceModel = "shiba";
    auto h2 = RoundTrip(h);
    CHECK(h2.deviceName == "Pixel 8" && h2.deviceModel == "shiba" && h2.screenHeight == 2400 &&
          h2.capabilities == h.capabilities && h2.androidApiLevel == 34 && h2.densityDpi == 420);

    HelloAck a{HelloStatus::Accepted, 1, 42, 1u << 20};
    auto a2 = RoundTrip(a);
    CHECK(a2.assignedSessionId == 42 && a2.maxPayloadSize == (1u << 20));

    VideoConfig vc;
    vc.configId = 3; vc.profile = 100; vc.level = 42; vc.rotation = Rotation::R90;
    vc.width = 1920; vc.height = 1080; vc.frameRate = 60; vc.bitrate = 12'000'000;
    vc.codecConfig = {0, 0, 0, 1, 0x67, 0x64, 0, 0, 0, 1, 0x68};
    auto vc2 = RoundTrip(vc);
    CHECK(vc2.codecConfig == vc.codecConfig && vc2.rotation == Rotation::R90 && vc2.bitrate == 12'000'000);

    VideoFrame vf;
    vf.configId = 3; vf.frameFlags = kFrameKeyframe; vf.ptsMicros = 123456789012ull;
    vf.data.assign(5000, 0xAB);
    auto vf2 = RoundTrip(vf);
    CHECK(vf2.data == vf.data && vf2.ptsMicros == vf.ptsMicros && (vf2.frameFlags & kFrameKeyframe));

    AudioConfig ac{AudioCodec::Opus, 2, 48000, {1, 2, 3}};
    CHECK(RoundTrip(ac).sampleRate == 48000);
    AudioFrame af{99, {9, 9, 9}};
    CHECK(RoundTrip(af).data.size() == 3);
    DisplayChanged dc{2400, 1080, Rotation::R270, 4};
    CHECK(RoundTrip(dc).rotation == Rotation::R270);
    CHECK(RoundTrip(Status{5, "encoder ready"}).message == "encoder ready");
    CHECK(RoundTrip(Disconnect{DisconnectReason::Timeout, "bye"}).reason == DisconnectReason::Timeout);
    auto e2 = RoundTrip(ErrorMessage{17, true, "decoder failed"});
    CHECK(e2.fatal && e2.code == 17);
}

void TestPartialAndStream() {
    auto a = Encode(Heartbeat{1, 2});
    auto b = Encode(Status{1, "x"});
    std::vector<std::uint8_t> stream = a;
    stream.insert(stream.end(), b.begin(), b.end());
    for (std::size_t n = 0; n < a.size(); ++n) {
        CHECK(DecodeErr(std::vector<std::uint8_t>(stream.begin(), stream.begin() + static_cast<std::ptrdiff_t>(n))) == DecodeError::NeedMoreData);
    }
    Message m; std::size_t c = 0;
    CHECK(DecodeMessage(stream, m, c) == DecodeError::None && c == a.size());
    CHECK(DecodeMessage(std::span(stream).subspan(c), m, c) == DecodeError::None &&
          std::holds_alternative<Status>(m.payload));
}

void TestInvalid() {
    auto base = Encode(Heartbeat{1, 2});

    auto bad = base; bad[0] = 'X';
    CHECK(DecodeErr(bad) == DecodeError::BadMagic);

    bad = base; bad[4] = 2;
    CHECK(DecodeErr(bad) == DecodeError::UnsupportedVersion);
    bad = base; bad[4] = 0;
    CHECK(DecodeErr(bad) == DecodeError::UnsupportedVersion);

    bad = base; bad[5] = 0x7F;
    CHECK(DecodeErr(bad) == DecodeError::UnknownType);

    bad = base; bad[7] = 1;  // header flags
    CHECK(DecodeErr(bad) == DecodeError::ReservedNotZero);
    bad = base; bad[23] = 1;  // reserved
    CHECK(DecodeErr(bad) == DecodeError::ReservedNotZero);

    // Control message claiming > 64 KiB payload.
    bad = base; bad[16] = 0; bad[17] = 0x01; bad[18] = 0x00; bad[19] = 0x01;
    CHECK(DecodeErr(bad) == DecodeError::PayloadTooLarge);
    // Media message claiming > 8 MiB.
    auto vf = Encode(VideoFrame{1, 0, 0, {1}});
    vf[16] = 0x00; vf[17] = 0x80; vf[18] = 0x00; vf[19] = 0x01;
    CHECK(DecodeErr(vf) == DecodeError::PayloadTooLarge);

    // Heartbeat payload length shortened (Truncated) / extended (TrailingBytes).
    bad = base; bad[19] = 0x0F; bad.pop_back();
    CHECK(DecodeErr(bad) == DecodeError::Truncated);
    bad = base; bad[19] = 0x11; bad.push_back(0);
    CHECK(DecodeErr(bad) == DecodeError::TrailingBytes);

    // Invalid rotation in DisplayChanged.
    auto dc = Encode(DisplayChanged{100, 100, Rotation::R0, 0});
    dc[kHeaderSize + 4] = 4;
    CHECK(DecodeErr(dc) == DecodeError::InvalidField);

    // String length over limit.
    auto st = Encode(Status{1, "a"});
    st[kHeaderSize + 2] = 0x01; st[kHeaderSize + 3] = 0x01;  // 257
    CHECK(DecodeErr(st) == DecodeError::StringTooLong);

    // VideoConfig csd length beyond payload.
    VideoConfig vc; vc.width = 10; vc.height = 10; vc.codecConfig = {1, 2};
    auto vcb = Encode(vc);
    vcb[kHeaderSize + 23] = 3;
    CHECK(DecodeErr(vcb) == DecodeError::Truncated);

    // Unknown frame flags.
    auto vf2 = Encode(VideoFrame{1, 0, 0, {1}});
    vf2[kHeaderSize + 4] = 0x80;
    CHECK(DecodeErr(vf2) == DecodeError::InvalidField);

    // Encoder rejects invalid input.
    std::vector<std::uint8_t> out;
    CHECK(!EncodeMessage(0, 0, Status{1, std::string(300, 'a')}, out) && out.empty());
    CHECK(!EncodeMessage(0, 0, VideoFrame{1, 0, 0, {}}, out));
    CHECK(EncodeMessage(0, 0, VideoFrame{1, kFrameEndOfStream, 0, {}}, out));
    out.clear();
    CHECK(!EncodeMessage(0, 0, VideoConfig{}, out) && out.empty());  // zero width/height
}

void TestVersionNegotiationFields() {
    Hello h; h.minVersion = 2; h.maxVersion = 1;
    std::vector<std::uint8_t> out;
    CHECK(!EncodeMessage(0, 0, h, out));
    Hello ok; ok.minVersion = 1; ok.maxVersion = 3;  // future-compatible range
    auto b = Encode(ok);
    CHECK(DecodeErr(b) == DecodeError::None);
}
}  // namespace

int main() {
    TestGoldenHeartbeat();
    TestRoundTrips();
    TestPartialAndStream();
    TestInvalid();
    TestVersionNegotiationFields();
    std::printf("protocol_tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
