#include <cstdio>
#include <cstdlib>
#include <string>
#include "../../apps/windows/src/experimental/iphone_usb_probe.hpp"
#include "../../apps/windows/src/experimental/airplay_usb_receiver.hpp"

using namespace castsprint::windows::experimental;

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

} // namespace

int main() {
    TestProbeExecution();
    TestDiagnosticReportFormatting();
    TestDriverOverrideClassification();
    TestAppleUsbHotspotDetectionAndFormatting();
    TestAirPlayRtspParser();
    TestAirPlayRtspStateTransitions();
    TestNonDrmScreenMirroringClassification();

    std::printf("probe_tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
