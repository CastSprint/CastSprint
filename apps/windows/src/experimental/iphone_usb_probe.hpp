#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace castsprint::windows::experimental {

enum class IPhoneDriverStatus {
    NotInstalled,
    AppleOfficialDriver,     // usbaapl64.sys (Normal iTunes / Apple Devices driver)
    GenericWinUsbDriver,     // winusb.sys (Custom replacement driver)
    UnknownDriver
};

enum class IPhoneStreamingCapability {
    UnsupportedOnWindows,    // Standard state on Windows (no CoreMediaIO subsystem)
    RequiresDriverOverride,  // Requires replacing Apple driver with WinUSB (destroys Apple sync)
    RequiresCompanionApp     // Supported via CastSprint iOS app (Wi-Fi or Usbmux port forward)
};

struct AttachedIPhoneInfo {
    std::wstring deviceInstanceId;
    std::wstring friendlyName;
    uint16_t vendorId = 0x05AC; // Apple Inc.
    uint16_t productId = 0;
    std::wstring serialNumber;
    IPhoneDriverStatus driverStatus = IPhoneDriverStatus::NotInstalled;
    std::wstring activeDriverService;
    bool isUserTrusted = false;
    IPhoneStreamingCapability streamingCapability = IPhoneStreamingCapability::UnsupportedOnWindows;
    std::wstring diagnosticDetails;
};

struct ProbeSummary {
    bool hasAppleDeviceAttached = false;
    std::vector<AttachedIPhoneInfo> devices;
    bool hasNativeMediaFoundationSource = false;
    std::wstring recommendation;
};

class IPhoneUsbProbe {
public:
    IPhoneUsbProbe() = default;
    ~IPhoneUsbProbe() = default;

    // Executes a non-destructive hardware scan using standard Windows SetupAPI and Media Foundation
    ProbeSummary RunProbe();

    // Helper: Formats the diagnostic probe report as a readable human/CLI string
    static std::wstring FormatReport(const ProbeSummary& summary);

private:
    std::vector<AttachedIPhoneInfo> ScanSetupApiUsbDevices();
    bool CheckMediaFoundationCaptureSources();
    bool CheckLockdownPairingStatus(const std::wstring& serialNumber);
};

} // namespace castsprint::windows::experimental
