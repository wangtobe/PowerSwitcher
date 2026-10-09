import Foundation
import ServiceManagement

/// Idle-sleep minutes used by 日常模式. Task mode ignores these.
struct DailyTimers: Equatable {
    static let defaults = DailyTimers(ac: 15, battery: 5)
    static let acChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
    static let batteryChoices = [1, 2, 3, 5, 10, 15, 20, 30, 60]

    var ac: Int
    var battery: Int

    /// Same bounds power.sh accepts.
    var clamped: DailyTimers { DailyTimers(ac: min(max(ac, 1), 180), battery: min(max(battery, 1), 180)) }
}

enum Preferences {
    static let setupVersion = 1
    static let lowBatteryThreshold = 20
    private static var store: UserDefaults { .standard }

    static var setupCompleted: Bool {
        get { store.integer(forKey: "setupVersion") >= setupVersion }
        set { store.set(newValue ? setupVersion : 0, forKey: "setupVersion") }
    }
    static var timers: DailyTimers {
        get {
            let ac = store.integer(forKey: "dailyACMinutes"), battery = store.integer(forKey: "dailyBatteryMinutes")
            return DailyTimers(ac: ac > 0 ? ac : DailyTimers.defaults.ac,
                               battery: battery > 0 ? battery : DailyTimers.defaults.battery).clamped
        }
        set {
            store.set(newValue.clamped.ac, forKey: "dailyACMinutes")
            store.set(newValue.clamped.battery, forKey: "dailyBatteryMinutes")
        }
    }
    static var lowBatteryWarning: Bool {
        get { (store.object(forKey: "lowBatteryWarning") as? Bool) ?? true }
        set { store.set(newValue, forKey: "lowBatteryWarning") }
    }
    static var displayOffOnLidClose: Bool {
        get { (store.object(forKey: "displayOffOnLidClose") as? Bool) ?? true }
        set { store.set(newValue, forKey: "displayOffOnLidClose") }
    }
    static var skipSleepConfirmation: Bool {
        get { store.bool(forKey: "skipSleepConfirmation") }
        set { store.set(newValue, forKey: "skipSleepConfirmation") }
    }
    /// Observed from NSWorkspace sleep/wake notifications: evidence the Mac actually slept.
    static var lastSleep: Date? {
        get { store.object(forKey: "lastSleep") as? Date }
        set { store.set(newValue, forKey: "lastSleep") }
    }
    static var lastWake: Date? {
        get { store.object(forKey: "lastWake") as? Date }
        set { store.set(newValue, forKey: "lastWake") }
    }
}

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// Returns an error message, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        guard enabled != isEnabled else { return nil }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum Format {
    static func minutes(_ value: Int) -> String {
        if value < 60 { return L("\(value) 分钟", "\(value) min") }
        let hours = value / 60, rest = value % 60
        return rest == 0 ? L("\(hours) 小时", "\(hours) hr") : L("\(hours) 小时 \(rest) 分钟", "\(hours) hr \(rest) min")
    }

    static func duration(from start: Date, to end: Date) -> String {
        let total = max(Int(end.timeIntervalSince(start) / 60), 0)
        return total < 1 ? L("持续不到 1 分钟", "less than 1 minute") : L("持续 ", "for ") + minutes(total)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }

    /// One self-contained clause per power source, e.g. "接电时闲置 15 分钟后休眠；使用电池时不会闲置休眠"
    static func timers(ac: Int?, battery: Int?) -> String {
        func clause(_ source: String, _ value: Int) -> String {
            value == 0 ? L("\(source)不会闲置休眠", "\(source): never sleep when idle") : L("\(source)闲置 \(minutes(value))后休眠", "\(source): sleep after \(minutes(value)) idle")
        }
        let parts = [ac.map { clause(L("接电时", "On power"), $0) }, battery.map { clause(L("使用电池时", "On battery"), $0) }].compactMap { $0 }
        return parts.isEmpty ? L("闲置休眠时间未知", "Idle sleep timer unknown") : parts.joined(separator: L("；", "; "))
    }

    static func timers(_ t: DailyTimers, hasBattery: Bool) -> String {
        timers(ac: t.ac, battery: hasBattery ? t.battery : nil)
    }

    static func source(_ snapshot: PowerSnapshot) -> String? {
        let percent = snapshot.batteryPercent.map { L("电池 \($0)%", "Battery \($0)%") }
        switch snapshot.source {
        case .ac: return [L("电源适配器供电", "Connected to power"), percent].compactMap { $0 }.joined(separator: " · ")
        case .battery: return L("电池供电", "Running on battery") + (snapshot.batteryPercent.map { L(" · 剩余 \($0)%", " · \($0)% remaining") } ?? "")
        case .ups: return L("UPS 供电", "Running on UPS")
        case .unknown: return percent
        }
    }
}
