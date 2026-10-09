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

/// Built-in panel brightness through the private DisplayServices framework.
/// Remote-control tools wake the display while the lid is shut so they can capture it; with the
/// backlight at zero the panel stays dark while the framebuffer, and remote viewing, keep working.
/// Every call is a no-op when the framework or an active built-in display is unavailable.
enum Backlight {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let api: (get: GetFn, set: SetFn)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(get, to: GetFn.self), unsafeBitCast(set, to: SetFn.self))
    }()

    static var available: Bool { api != nil }

    /// The built-in panel while it is active. In clamshell mode with an external display it is inactive, so nothing is dimmed.
    private static var builtin: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// 0...1, or nil when unavailable.
    static var level: Float? {
        guard let api, let id = builtin else { return nil }
        var value: Float = 0
        return api.get(id, &value) == 0 ? value : nil
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let api, let id = builtin else { return false }
        return api.set(id, min(max(value, 0), 1)) == 0
    }
}
