import Foundation

func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    p.standardOutput = pipe; p.standardError = pipe
    do {
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    } catch { return (-1, error.localizedDescription) }
}

func appleQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

/// The two presets. Their meaning is defined by Scripts/power.sh and must not drift:
/// normal = global sleep allowed with idle timers; task = global sleep disabled.
enum PowerMode: String, CaseIterable {
    case normal, task

    var name: String { self == .normal ? L("日常模式", "Daily mode") : L("任务模式", "Task mode") }
    var effect: String { self == .normal ? L("允许休眠", "Sleep allowed") : L("持续运行", "Stay awake") }
    var title: String { name + " · " + effect }
    var symbols: [String] { self == .normal ? ["moon"] : ["bolt.fill"] }
}

enum PowerSource { case ac, battery, ups, unknown }

struct SleepBlocker: Equatable {
    let pid: Int
    let process: String
    let kind: String
    let reason: String
}

/// A read-only view of what pmset reports right now. Reading never changes power settings.
struct PowerSnapshot {
    /// nil when pmset output could not be interpreted.
    var mode: PowerMode?
    var profiles: [String: [String: Int]] = [:]
    var blockers: [SleepBlocker] = []
    var source: PowerSource = .unknown
    var batteryPercent: Int?

    var hasBattery: Bool { profiles["Battery Power"] != nil || batteryPercent != nil }

    /// Distinct process names holding sleep-blocking assertions, in first-seen order.
    var blockingProcesses: [String] {
        blockers.reduce(into: [String]()) { names, b in if !names.contains(b.process) { names.append(b.process) } }
    }

    /// AC idle timer; UPS-only Macs report their timer under "UPS Power".
    var acIdleMinutes: Int? { idleMinutes("AC Power") ?? idleMinutes("UPS Power") }

    /// A restart clears the global SleepDisabled flag but keeps Task mode's idle timers: sleep is allowed while a
    /// power-adapter profile still says never (0), which Daily mode never sets.
    var looksLikeInterruptedTask: Bool { mode == .normal && ["AC Power", "UPS Power"].contains { idleMinutes($0) == 0 } }

    func idleMinutes(_ section: String) -> Int? { profiles[section]?["sleep"] }

    /// Whether the live idle timers equal the user's daily preset (only for profiles this Mac reports),
    /// with no display timer longer than the idle timer: power.sh lowers those in Daily mode.
    func matches(_ timers: DailyTimers) -> Bool {
        let expected = [("AC Power", timers.ac), ("UPS Power", timers.ac), ("Battery Power", timers.battery)]
        return expected.allSatisfy { section, minutes in
            guard let idle = idleMinutes(section) else { return true }
            guard idle == minutes else { return false }
            guard let display = profiles[section]?["displaysleep"] else { return true }
            return display != 0 && display <= minutes
        }
    }

    static func read() -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        let (liveCode, live) = run("/usr/bin/pmset", ["-g"])
        if liveCode == 0, let disabled = parseSleepDisabled(live) { snapshot.mode = disabled ? .task : .normal }
        let (customCode, custom) = run("/usr/bin/pmset", ["-g", "custom"])
        if customCode == 0 { snapshot.profiles = parseProfiles(custom) }
        let (assertCode, assertions) = run("/usr/bin/pmset", ["-g", "assertions"])
        if assertCode == 0 { snapshot.blockers = parseBlockers(assertions) }
        let (battCode, batt) = run("/usr/bin/pmset", ["-g", "batt"])
        if battCode == 0 { (snapshot.source, snapshot.batteryPercent) = parseBattery(batt) }
        return snapshot
    }

    /// Same rule as power.sh: an absent SleepDisabled key means sleep is allowed.
    static func parseSleepDisabled(_ text: String) -> Bool? {
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.first == "SleepDisabled" else { continue }
            switch fields.count > 1 ? fields[1] : "" {
            case "0": return false
            case "1": return true
            default: return nil
            }
        }
        return false
    }

    /// Mirrors get_setting in power.sh: "Section:" headings followed by indented "key value" lines.
    static func parseProfiles(_ text: String) -> [String: [String: Int]] {
        var result: [String: [String: Int]] = [:]
        var section: String?
        for line in text.split(separator: "\n") {
            if let first = line.first, !first.isWhitespace, line.hasSuffix(":") {
                section = String(line.dropLast())
                continue
            }
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard let section = section, fields.count > 1, let value = Int(fields[1]) else { continue }
            result[section, default: [:]][String(fields[0])] = value
        }
        return result
    }

    static let blockingKinds: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]

    /// Per-process assertions that keep the system from idle sleep. powerd's own
    /// "display is on" assertion is normal behaviour, not a third-party blocker.
    static func parseBlockers(_ text: String) -> [SleepBlocker] {
        let pattern = #"pid (\d+)\((.*?)\): \[[^\]]*\] \S+ (\w+) named: "(.*?)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [SleepBlocker] = []
        for line in text.split(separator: "\n") {
            let s = String(line), ns = s as NSString
            guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
            let blocker = SleepBlocker(pid: Int(ns.substring(with: m.range(at: 1))) ?? 0,
                                       process: ns.substring(with: m.range(at: 2)),
                                       kind: ns.substring(with: m.range(at: 3)),
                                       reason: ns.substring(with: m.range(at: 4)))
            guard blockingKinds.contains(blocker.kind), blocker.process != "powerd", !result.contains(blocker) else { continue }
            result.append(blocker)
        }
        return result
    }

    static func parseBattery(_ text: String) -> (PowerSource, Int?) {
        var source = PowerSource.unknown, percent: Int?
        for line in text.split(separator: "\n") {
            if line.contains("drawing from") {
                if line.contains("'AC Power'") { source = .ac }
                else if line.contains("'Battery Power'") { source = .battery }
                else if line.contains("'UPS Power'") { source = .ups }
            } else if line.contains("InternalBattery"), let r = line.range(of: #"\d+%"#, options: .regularExpression) {
                percent = Int(line[r].dropLast())
            }
        }
        return (source, percent)
    }
}

enum SwitchOutcome {
    case success, cancelled, failed(String)
    /// The mode switch (if any) succeeded, but registering the scheduled jobs did not.
    case scheduleFailed(String)
}

enum PowerCommand {
    /// Values are integers clamped in Swift and validated again by power.sh before any change.
    static func script(for mode: PowerMode, timers: DailyTimers) -> String {
        let t = timers.clamped
        return "mode=\(mode.rawValue)\ndaily_ac=\(t.ac)\ndaily_battery=\(t.battery)\n" + PowerScripts.body
    }

    /// Switches to `mode` and/or registers `schedule`, with a single administrator prompt.
    /// The schedule is only touched after the switch succeeded.
    static func apply(_ mode: PowerMode?, timers: DailyTimers, schedule: Schedule.Plan? = nil, completion: @escaping (SwitchOutcome) -> Void) {
        let (script, prompt) = command(mode, timers: timers, schedule: schedule)
        let source = "do shell script " + appleQuote(script) + " with prompt " + appleQuote(prompt) + " with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            let (code, detail) = run("/usr/bin/osascript", ["-e", source])
            let log = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome: SwitchOutcome
            if code == 0 { outcome = .success }
            else if detail.contains("(-128)") { outcome = .cancelled }
            else if detail.contains(Schedule.failureMarker) { outcome = .scheduleFailed(log) }
            else { outcome = .failed(log) }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    static func command(_ mode: PowerMode?, timers: DailyTimers, schedule: Schedule.Plan?) -> (script: String, prompt: String) {
        var parts: [String] = []
        var prompt: String
        if let mode {
            // Without a schedule the switching script runs exactly as before.
            parts.append(schedule == nil ? script(for: mode, timers: timers) : "(\n" + script(for: mode, timers: timers) + "\n) || exit $?")
            prompt = L("PowerSwitcher 需要管理员权限来切换到“\(mode.title)”", "PowerSwitcher needs administrator access to switch to “\(mode.title)”")
            if let end = schedule?.taskEnd, mode == .task {
                prompt += L("，并在 \(Format.time(end)) 自动切回日常模式。", " and to return to Daily mode at \(Format.time(end)).")
            } else {
                prompt += L("。", ".")
            }
        } else {
            prompt = L("PowerSwitcher 需要管理员权限来更新定时切换。", "PowerSwitcher needs administrator access to update scheduled switches.")
        }
        if let schedule { parts.append(Schedule.syncScript(schedule, timers: timers)) }
        return (parts.joined(separator: "\n"), prompt)
    }
}
