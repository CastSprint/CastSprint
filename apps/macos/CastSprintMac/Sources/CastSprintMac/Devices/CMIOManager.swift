// CMIOManager.swift — CoreMediaIO Screen Capture Device Provider Activation
import Foundation
import CoreMediaIO

public final class CMIOManager {
    public static let shared = CMIOManager()

    // kCMIOProviderPropertyAllowScreenCaptureDevices = 'take' (0x74616B65)
    private static let cmioPropertyAllowScreenCaptureDevices: FourCharCode = 0x74616B65

    private init() {}

    /// Activates the CoreMediaIO system provider property allowing iOS screen capture devices
    /// to be enumerated by AVFoundation.
    @discardableResult
    public func enableScreenCaptureDevices() -> Bool {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(Self.cmioPropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0,
            nil,
            dataSize,
            &allow
        )

        let success = (status == noErr)
        if success {
            NSLog("CastSprint: Successfully enabled CoreMediaIO iOS screen capture devices")
        } else {
            NSLog("CastSprint: Warning — CMIOObjectSetPropertyData returned OSStatus %d", status)
        }
        return success
    }
}
