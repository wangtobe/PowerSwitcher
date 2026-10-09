import AppKit
import IOKit

/// Lid state and displays. With system sleep disabled, closing the lid no longer triggers
/// the sleep path that normally darkens the panel, so task mode turns the display off itself.
enum Lid {
    /// nil on Macs without a lid, or when the state is unavailable.
    static func isClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static var exists: Bool { isClosed() != nil }

    /// Lid closed with an external display is clamshell mode; that display must stay on.
    static var hasExternalDisplay: Bool {
        NSScreen.screens.contains { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
    }

    /// Display sleep only; system sleep and running tasks are unaffected. No administrator rights needed.
    static func turnDisplayOff() { _ = run("/usr/bin/pmset", ["displaysleepnow"]) }
}
