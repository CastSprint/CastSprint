// CMIOManager.swift — CoreMediaIO Screen Capture Device Provider Activation
import Foundation
import CoreMediaIO

public final class CMIOManager {
    public static let shared = CMIOManager()

    // Official Apple CoreMediaIO property constants:
    // kCMIOHardwarePropertyAllowScreenCaptureDevices = 'yes ' (0x79657320)
    // kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices = 'wscd' (0x77736364)
    private static let cmioPropertyAllowScreenCaptureDevices: FourCharCode = 0x79657320
    private static let cmioPropertyAllowWirelessScreenCaptureDevices: FourCharCode = 0x77736364

    public private(set) var isScreenCaptureEnabled: Bool = false

    private init() {}

    /// Activates the CoreMediaIO system provider property allowing iOS screen capture devices
    /// to be enumerated by AVFoundation.
    @discardableResult
    public func enableScreenCaptureDevices() -> Bool {
        var allow: UInt32 = 1
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        var propWired = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(Self.cmioPropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let statusWired = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propWired,
            0,
            nil,
            dataSize,
            &allow
        )

        var propWireless = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(Self.cmioPropertyAllowWirelessScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        _ = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propWireless,
            0,
            nil,
            dataSize,
            &allow
        )

        let success = (statusWired == noErr)
        self.isScreenCaptureEnabled = success
        if success {
            NSLog("CastSprint: Successfully enabled CoreMediaIO iOS screen capture devices")
        } else {
            NSLog("CastSprint: Warning — CMIOObjectSetPropertyData returned OSStatus %d", statusWired)
        }
        return success
    }
}
