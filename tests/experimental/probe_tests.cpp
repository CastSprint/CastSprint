#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "../../apps/windows/src/experimental/iphone_usb_probe.hpp"
#include "../../apps/windows/src/experimental/airplay_usb_receiver.hpp"
#include "../../apps/windows/src/airplay/airplay_constants.hpp"
#include "../../apps/windows/src/airplay/airplay_rtsp_codec.hpp"
#include "../../apps/windows/src/airplay/airplay_receiver.hpp"

using namespace castsprint::windows::experimental;
namespace airplay = castsprint::windows::airplay;

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

void TestProbeExecution() {
    IPhoneUsbProbe probe;
    ProbeSummary summary = probe.RunProbe();

    CHECK(!summary.recommendation.empty());

    std::wstring report = IPhoneUsbProbe::FormatReport(summary);
    CHECK(!report.empty());
    CHECK(report.find(L"CastSprint Windows — Experimental iPhone USB Feasibility Probe") != std::wstring::npos);
}

void TestDiagnosticReportFormatting() {
    ProbeSummary mockSummary;
    mockSummary.hasAppleDeviceAttached = true;
    mockSummary.hasNativeMediaFoundationSource = false;
    mockSummary.hasAppleUsbNetworkAdapter = false;

    AttachedIPhoneInfo info;
    info.deviceInstanceId = L"USB\\VID_05AC&PID_12A8\\00008030-00123456789";
    info.friendlyName = L"Apple iPhone 15 Pro";
    info.vendorId = 0x05AC;
    info.productId = 0x12A8;
    info.serialNumber = L"00008030-00123456789";
    info.driverStatus = IPhoneDriverStatus::AppleOfficialDriver;
    info.activeDriverService = L"usbaapl64";
    info.isUserTrusted = true;
    info.streamingCapability = IPhoneStreamingCapability::AirPlayWireless;
    info.diagnosticDetails = L"Standard Apple Mobile Device USB Driver (usbaapl64.sys) is active.";

    mockSummary.devices.push_back(info);
    mockSummary.recommendation = L"Use AirPlay over USB Hotspot or local Wi-Fi.";

    std::wstring formatted = IPhoneUsbProbe::FormatReport(mockSummary);
    CHECK(formatted.find(L"Apple iPhone 15 Pro") != std::wstring::npos);
    CHECK(formatted.find(L"VID_05AC") != std::wstring::npos);
    CHECK(formatted.find(L"usbaapl64") != std::wstring::npos);
    CHECK(formatted.find(L"Official Apple Driver (usbaapl64.sys)") != std::wstring::npos);
    CHECK(formatted.find(L"Found in %ProgramData%\\Apple\\Lockdown") != std::wstring::npos);
    CHECK(formatted.find(L"Apple Mobile Device Ethernet Adapter: NO") != std::wstring::npos);
}

void TestDriverOverrideClassification() {
    ProbeSummary mockWinUsb;
    mockWinUsb.hasAppleDeviceAttached = true;
    mockWinUsb.hasNativeMediaFoundationSource = false;
    mockWinUsb.hasAppleUsbNetworkAdapter = false;

    AttachedIPhoneInfo info;
    info.deviceInstanceId = L"USB\\VID_05AC&PID_12A8\\CUSTOM";
    info.friendlyName = L"Apple Mobile Device (WinUSB)";
    info.vendorId = 0x05AC;
    info.productId = 0x12A8;
    info.driverStatus = IPhoneDriverStatus::GenericWinUsbDriver;
    info.activeDriverService = L"winusb";
    info.isUserTrusted = false;
    info.streamingCapability = IPhoneStreamingCapability::RequiresDriverOverride;
    info.diagnosticDetails = L"WinUSB bound. Apple sync disabled.";

    mockWinUsb.devices.push_back(info);

    std::wstring formatted = IPhoneUsbProbe::FormatReport(mockWinUsb);
    CHECK(formatted.find(L"Generic WinUSB Driver (winusb.sys)") != std::wstring::npos);
}

void TestAppleUsbHotspotDetectionAndFormatting() {
    ProbeSummary mockHotspot;
    mockHotspot.hasAppleDeviceAttached = true;
    mockHotspot.hasNativeMediaFoundationSource = false;
    mockHotspot.hasAppleUsbNetworkAdapter = true;
    mockHotspot.appleUsbNetworkAdapterName = L"Apple Mobile Device Ethernet";
    mockHotspot.appleUsbNetworkIp = "172.20.10.2";

    AttachedIPhoneInfo info;
    info.deviceInstanceId = L"USB\\VID_05AC&PID_12A8\\HOTSPOT";
    info.friendlyName = L"Apple iPhone 14";
    info.vendorId = 0x05AC;
    info.productId = 0x12A8;
    info.driverStatus = IPhoneDriverStatus::AppleOfficialDriver;
    info.activeDriverService = L"usbaapl64";
    info.isUserTrusted = true;
    info.streamingCapability = IPhoneStreamingCapability::AirPlayOverUsbHotspot;
    info.diagnosticDetails = L"Apple Mobile Device Ethernet active (172.20.10.2). Zero-app AirPlay over USB available.";

    mockHotspot.devices.push_back(info);
    mockHotspot.recommendation = L"AirPlay over USB Personal Hotspot (APPROACH B) is AVAILABLE.";

    std::wstring formatted = IPhoneUsbProbe::FormatReport(mockHotspot);
    CHECK(formatted.find(L"Apple Mobile Device Ethernet Adapter: YES") != std::wstring::npos);
    CHECK(formatted.find(L"172.20.10.2") != std::wstring::npos);
    CHECK(formatted.find(L"AirPlay over USB Personal Hotspot (APPROACH B) is AVAILABLE") != std::wstring::npos);
}

void TestAirPlayRtspParser() {
    AirPlayRtspRequest req;
    std::string rawOptions =
        "OPTIONS * RTSP/1.0\r\n"
        "CSeq: 1\r\n"
        "User-Agent: AirPlay/600.7\r\n"
        "Client-Instance: 0123456789ABCDEF\r\n"
        "\r\n";

    CHECK(AirPlayUsbReceiver::ParseRtspRequest(rawOptions, req));
    CHECK(req.method == "OPTIONS");
    CHECK(req.uri == "*");
    CHECK(req.protocolVersion == "RTSP/1.0");
    CHECK(req.headers["CSeq"] == "1");
    CHECK(req.headers["User-Agent"] == "AirPlay/600.7");
}

void TestAirPlayRtspStateTransitions() {
    AirPlayUsbReceiver receiver;
    CHECK(receiver.GetState() == AirPlaySessionState::Idle);

    receiver.Initialize(7000);
    CHECK(receiver.GetState() == AirPlaySessionState::ScanningUsbNetwork);

    UsbNetworkInterfaceInfo mockNet;
    mockNet.isPresent = true;
    mockNet.friendlyName = L"Apple Mobile Device Ethernet";
    mockNet.ipAddress = "172.20.10.2";
    mockNet.gatewayAddress = "172.20.10.1";
    mockNet.linkSpeedMbps = 480;

    receiver.InjectMockUsbNetwork(mockNet);
    CHECK(receiver.GetState() == AirPlaySessionState::WaitingForDevice);
    CHECK(receiver.GetActiveInterface().isPresent);
    CHECK(receiver.GetActiveInterface().ipAddress == "172.20.10.2");

    // 1. OPTIONS
    std::string optionsMsg = "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n";
    AirPlayRtspResponse respOptions = receiver.HandleRtspMessage(optionsMsg);
    CHECK(respOptions.statusCode == 200);
    CHECK(respOptions.headers["CSeq"] == "1");
    CHECK(respOptions.headers["Public"].find("ANNOUNCE") != std::string::npos);
    CHECK(receiver.GetState() == AirPlaySessionState::RtsHandshake);

    // 2. ANNOUNCE
    std::string announceSdp =
        "v=0\r\n"
        "o=AirPlay 1234 0 IN IP4 172.20.10.1\r\n"
        "s=AirPlay Screen Mirror\r\n"
        "m=video 7010 RTP/AVP 96\r\n"
        "a=rtpmap:96 H264/90000\r\n";
    std::string announceMsg =
        "ANNOUNCE rtsp://172.20.10.2/stream RTSP/1.0\r\n"
        "CSeq: 2\r\n"
        "Content-Type: application/sdp\r\n"
        "Content-Length: " + std::to_string(announceSdp.size()) + "\r\n"
        "\r\n" + announceSdp;

    AirPlayRtspResponse respAnnounce = receiver.HandleRtspMessage(announceMsg);
    CHECK(respAnnounce.statusCode == 200);
    CHECK(respAnnounce.headers["CSeq"] == "2");

    // 3. SETUP
    std::string setupMsg =
        "SETUP rtsp://172.20.10.2/stream RTSP/1.0\r\n"
        "CSeq: 3\r\n"
        "Transport: RTP/AVP/UDP;unicast;client_port=6000-6001\r\n"
        "\r\n";
    AirPlayRtspResponse respSetup = receiver.HandleRtspMessage(setupMsg);
    CHECK(respSetup.statusCode == 200);
    CHECK(respSetup.headers["Transport"].find("server_port=7010") != std::string::npos);
    CHECK(respSetup.headers["Session"] == "1");

    // 4. RECORD
    std::string recordMsg =
        "RECORD rtsp://172.20.10.2/stream RTSP/1.0\r\n"
        "CSeq: 4\r\n"
        "Session: 1\r\n"
        "\r\n";
    AirPlayRtspResponse respRecord = receiver.HandleRtspMessage(recordMsg);
    CHECK(respRecord.statusCode == 200);
    CHECK(receiver.GetState() == AirPlaySessionState::StreamingActive);

    // 5. TEARDOWN
    std::string teardownMsg =
        "TEARDOWN rtsp://172.20.10.2/stream RTSP/1.0\r\n"
        "CSeq: 5\r\n"
        "Session: 1\r\n"
        "\r\n";
    AirPlayRtspResponse respTeardown = receiver.HandleRtspMessage(teardownMsg);
    CHECK(respTeardown.statusCode == 200);
    CHECK(receiver.GetState() == AirPlaySessionState::Teardown);
}

void TestNonDrmScreenMirroringClassification() {
    // Standard H.264 screen mirroring SDP (gameplay / UI)
    std::string nonDrmSdp =
        "v=0\r\n"
        "m=video 7010 RTP/AVP 96\r\n"
        "a=rtpmap:96 H264/90000\r\n";
    CHECK(AirPlayUsbReceiver::IsNonDrmScreenMirroring(nonDrmSdp));

    // FairPlay DRM protected commercial video SDP (e.g. Netflix/Apple TV+)
    std::string drmSdp =
        "v=0\r\n"
        "m=video 7010 RTP/AVP 96\r\n"
        "a=fmtp:96 fairplay-enc=1;kFairPlayKey=ABCDEF\r\n";
    CHECK(!AirPlayUsbReceiver::IsNonDrmScreenMirroring(drmSdp));
}

void TestNativeAirPlayRtspCodec() {
    // Test RtspCodec::Parse and RtspCodec::Serialize roundtrip
    std::string rawReq =
        "ANNOUNCE rtsp://192.168.1.100/stream RTSP/1.0\r\n"
        "CSeq: 42\r\n"
        "Content-Type: application/sdp\r\n"
        "User-Agent: AirPlay/600.7\r\n"
        "Content-Length: 15\r\n"
        "\r\n"
        "v=0\r\nm=video 0\r\n";

    airplay::RtspMessage msg;
    CHECK(airplay::RtspCodec::Parse(rawReq, msg));
    CHECK(!msg.isResponse);
    CHECK(msg.method == "ANNOUNCE");
    CHECK(msg.uri == "rtsp://192.168.1.100/stream");
    CHECK(msg.GetHeader("CSeq") == "42");
    CHECK(msg.GetHeader("User-Agent") == "AirPlay/600.7");
    CHECK(msg.body.size() == 15);

    // Test Response creation
    airplay::RtspMessage resp = airplay::RtspCodec::CreateResponse(msg, 200, "OK");
    CHECK(resp.isResponse);
    CHECK(resp.statusCode == 200);
    CHECK(resp.GetHeader("CSeq") == "42");
    CHECK(resp.GetHeader("Server").find("AirTunes") != std::string::npos);

    std::string serialized = airplay::RtspCodec::Serialize(resp);
    CHECK(serialized.find("RTSP/1.0 200 OK") != std::string::npos);
    CHECK(serialized.find("CSeq: 42") != std::string::npos);
    CHECK(serialized.find("Server: AirTunes") != std::string::npos);

    // Test SDP Parsing
    std::string sdp =
        "v=0\r\n"
        "m=video 7010 RTP/AVP 96\r\n"
        "a=rtpmap:96 H264/90000\r\n"
        "m=audio 7012 RTP/AVP 97\r\n"
        "a=rtpmap:97 AAC-ELD/44100/2\r\n";
    airplay::SdpVideoInfo vInfo;
    airplay::SdpAudioInfo aInfo;
    CHECK(airplay::RtspCodec::ParseSdp(sdp, vInfo, aInfo));
    CHECK(vInfo.hasVideo);
    CHECK(vInfo.codec == "H264");
    CHECK(vInfo.isNonDrmMirror);
    CHECK(aInfo.hasAudio);
    CHECK(aInfo.codec == "AAC-ELD");
}

void TestRtpVideoDepacketizer() {
    std::vector<uint8_t> receivedNalu;
    uint64_t receivedPts = 0;

    airplay::RtpVideoDepacketizer depacketizer([&](std::span<const uint8_t> nalu, uint64_t pts) {
        receivedNalu.assign(nalu.begin(), nalu.end());
        receivedPts = pts;
    });

    // 1. Single NAL unit packet (IDR slice type 5)
    // RTP Header: 12 bytes
    // V=2 (0x80), PT=96 (0x60), Seq=1 (0x00, 0x01), Timestamp=90000 (1 sec = 0x00, 0x01, 0x5F, 0x90), SSRC=0
    std::vector<uint8_t> rtpSingle = {
        0x80, 0x60, 0x00, 0x01,
        0x00, 0x01, 0x5F, 0x90,
        0x00, 0x00, 0x00, 0x01,
        // Payload: NAL type 5 (IDR)
        0x25, 0xAA, 0xBB, 0xCC
    };

    CHECK(depacketizer.ProcessRtpPacket(rtpSingle));
    CHECK(!receivedNalu.empty());
    // Must have Annex-B start code: 0x00 0x00 0x00 0x01
    CHECK(receivedNalu[0] == 0x00 && receivedNalu[1] == 0x00 &&
          receivedNalu[2] == 0x00 && receivedNalu[3] == 0x01);
    CHECK(receivedNalu[4] == 0x25);
    CHECK(receivedNalu.size() == 8);
    CHECK(receivedPts == 1000000ULL); // 90000 ticks at 90kHz = 1,000,000 microseconds

    // 2. FU-A Fragmented NAL unit (Start bit + End bit)
    receivedNalu.clear();
    // Packet 1: FU-A Start (type 28, NAL type 1)
    std::vector<uint8_t> rtpFuStart = {
        0x80, 0x60, 0x00, 0x02,
        0x00, 0x01, 0x5F, 0x90,
        0x00, 0x00, 0x00, 0x01,
        // FU Indicator (type 28), FU Header (S=1, E=0, type=1)
        0x7C, 0x81, 0x11, 0x22
    };
    CHECK(depacketizer.ProcessRtpPacket(rtpFuStart));
    CHECK(receivedNalu.empty()); // Incomplete, waiting for end

    // Packet 2: FU-A End
    std::vector<uint8_t> rtpFuEnd = {
        0x80, 0x60, 0x00, 0x03,
        0x00, 0x01, 0x5F, 0x90,
        0x00, 0x00, 0x00, 0x01,
        // FU Indicator (type 28), FU Header (S=0, E=1, type=1)
        0x7C, 0x41, 0x33, 0x44
    };
    CHECK(depacketizer.ProcessRtpPacket(rtpFuEnd));
    CHECK(!receivedNalu.empty());
    // Verify start code + reconstructed NAL header (0x7C & 0xE0) | (0x41 & 0x1F) = 0x60 | 0x01 = 0x61
    CHECK(receivedNalu[0] == 0x00 && receivedNalu[1] == 0x00 &&
          receivedNalu[2] == 0x00 && receivedNalu[3] == 0x01);
    CHECK(receivedNalu[4] == 0x61);
    CHECK(receivedNalu.size() == 9); // 4 start code + 1 header + 2 payload + 2 payload
}

void TestAirPlayReceiverLifecycle() {
    airplay::AirPlayReceiverConfig config;
    config.receiverName = "CastSprint Desktop";
    config.rtspPort = 7000;

    airplay::AirPlayReceiver receiver(config);
    CHECK(!receiver.IsRunning());
    CHECK(receiver.State() == airplay::ReceiverState::Stopped);

    CHECK(receiver.Start());
    CHECK(receiver.IsRunning());
    CHECK(receiver.State() == airplay::ReceiverState::Advertising);

    // Process simulated RTSP pairing and streaming handshake
    std::string respOptions = receiver.ProcessRtspCommand("OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n");
    CHECK(respOptions.find("200 OK") != std::string::npos);
    CHECK(respOptions.find("Public: ") != std::string::npos);

    std::string respPairSetup = receiver.ProcessRtspCommand("POST /pair-setup RTSP/1.0\r\nCSeq: 2\r\n\r\n");
    CHECK(respPairSetup.find("200 OK") != std::string::npos);

    std::string respPairVerify = receiver.ProcessRtspCommand("POST /pair-verify RTSP/1.0\r\nCSeq: 3\r\n\r\n");
    CHECK(respPairVerify.find("200 OK") != std::string::npos);
    CHECK(receiver.State() == airplay::ReceiverState::ClientConnected);

    std::string respFpSetup = receiver.ProcessRtspCommand("POST /fp-setup RTSP/1.0\r\nCSeq: 4\r\n\r\n");
    CHECK(respFpSetup.find("200 OK") != std::string::npos);

    std::string announceSdp =
        "v=0\r\n"
        "m=video 7010 RTP/AVP 96\r\n"
        "a=rtpmap:96 H264/90000\r\n";
    std::string respAnnounce = receiver.ProcessRtspCommand(
        "ANNOUNCE rtsp://172.20.10.2/stream RTSP/1.0\r\nCSeq: 5\r\nContent-Length: " +
        std::to_string(announceSdp.size()) + "\r\n\r\n" + announceSdp);
    CHECK(respAnnounce.find("200 OK") != std::string::npos);

    std::string respSetup = receiver.ProcessRtspCommand(
        "SETUP rtsp://172.20.10.2/stream RTSP/1.0\r\nCSeq: 6\r\nTransport: RTP/AVP/UDP;unicast\r\n\r\n");
    CHECK(respSetup.find("200 OK") != std::string::npos);
    CHECK(respSetup.find("server_port=7010") != std::string::npos);

    std::string respRecord = receiver.ProcessRtspCommand("RECORD rtsp://172.20.10.2/stream RTSP/1.0\r\nCSeq: 7\r\n\r\n");
    CHECK(respRecord.find("200 OK") != std::string::npos);
    CHECK(receiver.State() == airplay::ReceiverState::StreamingActive);

    std::string respTeardown = receiver.ProcessRtspCommand("TEARDOWN rtsp://172.20.10.2/stream RTSP/1.0\r\nCSeq: 8\r\n\r\n");
    CHECK(respTeardown.find("200 OK") != std::string::npos);
    CHECK(receiver.State() == airplay::ReceiverState::Advertising);

    receiver.Stop();
    CHECK(!receiver.IsRunning());
    CHECK(receiver.State() == airplay::ReceiverState::Stopped);
}

} // namespace

int main() {
    TestProbeExecution();
    TestDiagnosticReportFormatting();
    TestDriverOverrideClassification();
    TestAppleUsbHotspotDetectionAndFormatting();
    TestAirPlayRtspParser();
    TestAirPlayRtspStateTransitions();
    TestNonDrmScreenMirroringClassification();
    TestNativeAirPlayRtspCodec();
    TestRtpVideoDepacketizer();
    TestAirPlayReceiverLifecycle();

    std::printf("probe_tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
