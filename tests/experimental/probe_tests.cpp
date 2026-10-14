#include <cstdio>
#include <cstdlib>
#include <string>
#include "../../apps/windows/src/experimental/iphone_usb_probe.hpp"

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

    AttachedIPhoneInfo info;
    info.deviceInstanceId = L"USB\\VID_05AC&PID_12A8\\00008030-00123456789";
    info.friendlyName = L"Apple iPhone 15 Pro";
    info.vendorId = 0x05AC;
    info.productId = 0x12A8;
    info.serialNumber = L"00008030-00123456789";
    info.driverStatus = IPhoneDriverStatus::AppleOfficialDriver;
    info.activeDriverService = L"usbaapl64";
    info.isUserTrusted = true;
    info.streamingCapability = IPhoneStreamingCapability::UnsupportedOnWindows;
    info.diagnosticDetails = L"Standard Apple Mobile Device USB Driver (usbaapl64.sys) is active.";

    mockSummary.devices.push_back(info);
    mockSummary.recommendation = L"Use CastSprint iOS App over Wi-Fi.";

    std::wstring formatted = IPhoneUsbProbe::FormatReport(mockSummary);
    CHECK(formatted.find(L"Apple iPhone 15 Pro") != std::wstring::npos);
    CHECK(formatted.find(L"VID_05AC") != std::wstring::npos);
    CHECK(formatted.find(L"usbaapl64") != std::wstring::npos);
    CHECK(formatted.find(L"Official Apple Driver (usbaapl64.sys)") != std::wstring::npos);
    CHECK(formatted.find(L"Found in %ProgramData%\\Apple\\Lockdown") != std::wstring::npos);
}

void TestDriverOverrideClassification() {
    ProbeSummary mockWinUsb;
    mockWinUsb.hasAppleDeviceAttached = true;
    mockWinUsb.hasNativeMediaFoundationSource = false;

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

} // namespace

int main() {
    TestProbeExecution();
    TestDiagnosticReportFormatting();
    TestDriverOverrideClassification();

    std::printf("probe_tests: %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
