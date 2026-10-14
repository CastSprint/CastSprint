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
    UnsupportedOnWindows,    // No connection or unrecognized hardware
    RequiresDriverOverride,  // Direct QuickTime USB: requires WinUSB or USB filter driver (e.g. libusb/usbdk)
    RequiresCompanionApp,    // Dedicated gaming stream via CastSprint iOS app (Wi-Fi or LAN)
    AirPlayOverUsbHotspot,   // Native iOS AirPlay over Apple Mobile Device Ethernet NDIS adapter (No app, zero driver mod)
    AirPlayWireless,         // Native iOS AirPlay over local Wi-Fi (No companion app required)
    DeveloperModeDvt         // Apple Developer Services (DVT/Instruments): video only, requires iOS Developer Mode
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
    bool hasAppleUsbNetworkAdapter = false;
    std::wstring appleUsbNetworkAdapterName;
    std::string appleUsbNetworkIp;
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
