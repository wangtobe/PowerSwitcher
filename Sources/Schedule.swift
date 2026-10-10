import Foundation
import CryptoKit

struct ClockTime: Equatable {
    var hour: Int
    var minute: Int

    static let taskDefault = ClockTime(hour: 23, minute: 0)
    static let dailyDefault = ClockTime(hour: 8, minute: 0)

    var text: String { String(format: "%02d:%02d", hour, minute) }
    var minutes: Int { hour * 60 + minute }
}

/// Scheduled switches run unattended as launchd system jobs, so nobody has to type a password when they fire.
/// The administrator password is asked once, when a schedule is set or changed. Each job's plist carries the
/// complete switching script inline: it is root-owned in /Library/LaunchDaemons and runs nothing a user could
/// modify. Jobs use the same power.sh as manual switches, including verification and rollback, and append to
/// a root-owned log. The one-shot end of Task mode removes itself after it runs.
enum Schedule {
    struct Plan: Equatable {
        /// One-shot: return to Daily mode at this minute.
        var taskEnd: Date?
        /// Every day: enter Task mode.
        var dailyTask: ClockTime?
        /// Every day: return to Daily mode.
        var dailyNormal: ClockTime?
        /// At startup: re-enable Task mode when a restart cleared it.
        var restoreAfterRestart = false

        var isEmpty: Bool { taskEnd == nil && dailyTask == nil && dailyNormal == nil && !restoreAfterRestart }

        /// With both daily times set, the day splits into a Task window and a Daily window.
        var window: Window? {
            guard let task = dailyTask, let normal = dailyNormal, task != normal else { return nil }
            return Window(task: task, normal: normal)
        }
    }

    struct Window: Equatable {
        var task: ClockTime
        var normal: ClockTime

        /// Whether `date` falls in the Task window; windows may wrap past midnight (23:00–08:00).
        func isTask(at date: Date, calendar: Calendar = .current) -> Bool {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0), t = task.minutes, n = normal.minutes
            return t < n ? (m >= t && m < n) : (m >= t || m < n)
        }

        func mode(at date: Date = Date()) -> PowerMode { isTask(at: date) ? .task : .normal }

        /// The same test in sh, setting nothing; `in_task` succeeds inside the Task window.
        var shell: String {
            let t = task.minutes, n = normal.minutes
            let test = t < n ? "[ \"$m\" -ge \(t) ] && [ \"$m\" -lt \(n) ]" : "[ \"$m\" -ge \(t) ] || [ \"$m\" -lt \(n) ]"
            return """
            m=$(/bin/date '+%H %M' | /usr/bin/awk '{print $1 * 60 + $2}')
            in_task() { \(test); }
            """
        }
    }

    enum Job: String, CaseIterable {
        case taskEnd = "org.powerswitcher.schedule.task-end"
        case dailyTask = "org.powerswitcher.schedule.daily-task"
        case dailyNormal = "org.powerswitcher.schedule.daily-normal"
        case bootRestore = "org.powerswitcher.schedule.boot-restore"

        var path: String { "/Library/LaunchDaemons/\(rawValue).plist" }
    }

    static let log = "/Library/Logs/PowerSwitcher-schedule.log"
    static let failureMarker = "PowerSwitcher schedule update failed"
    private static let endKey = "POWERSWITCHER_END", acKey = "POWERSWITCHER_DAILY_AC", batteryKey = "POWERSWITCHER_DAILY_BATTERY",
                       revisionKey = "POWERSWITCHER_REVISION", restoreKey = "POWERSWITCHER_RESTORE"
    /// Bump when the job script layout changes.
    private static let format = "3"

    /// Identifies the switching script baked into registered jobs, so jobs from an older build can be re-registered.
    static let revision: String = {
        SHA256.hash(data: Data((format + "\n" + PowerScripts.body).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }()

    // MARK: Reading

    struct Installed: Equatable {
        var plan = Plan()
        /// Daily timers baked into the jobs that return to Daily mode; nil when no such job exists.
        var timers: DailyTimers?
        /// Some registered job carries a switching script from another build.
        var isStale = false
    }

    /// What is registered now, read from the world-readable plists.
    static func installed(directory: String = "/Library/LaunchDaemons") -> Installed {
        var result = Installed()
        for job in Job.allCases {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(job.rawValue + ".plist")
            guard let data = try? Data(contentsOf: url), let info = parse(data) else { continue }
            switch job {
            case .taskEnd:
                guard let end = info.end else { continue }
                result.plan.taskEnd = Date(timeIntervalSince1970: TimeInterval(end))
            case .dailyTask:
                result.plan.dailyTask = info.time
            case .dailyNormal:
                result.plan.dailyNormal = info.time
            case .bootRestore:
                // The startup job also exists for a daily window; absent flag = registered by 1.6.2 build 14, restore only.
                result.plan.restoreAfterRestart = info.restore ?? true
            }
            if job == .taskEnd || job == .dailyNormal, let timers = info.timers { result.timers = timers }
            if info.revision != revision { result.isStale = true }
        }
        return result
    }

    struct JobInfo {
        var time: ClockTime?
        var end: Int?
        var timers: DailyTimers?
        var revision: String?
        var restore: Bool?
    }

    static func parse(_ data: Data) -> JobInfo? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        var info = JobInfo()
        if let calendar = plist["StartCalendarInterval"] as? [String: Int], let hour = calendar["Hour"], let minute = calendar["Minute"] {
            info.time = ClockTime(hour: hour, minute: minute)
        }
        let env = plist["EnvironmentVariables"] as? [String: String] ?? [:]
        info.end = env[endKey].flatMap { Int($0) }
        info.revision = env[revisionKey]
        info.restore = env[restoreKey].map { $0 == "1" }
        if let ac = env[acKey].flatMap({ Int($0) }), let battery = env[batteryKey].flatMap({ Int($0) }) {
            info.timers = DailyTimers(ac: ac, battery: battery)
        }
        return info
    }

    // MARK: Times

    /// launchd fires at the start of a minute, so end times are whole minutes.
    static func endTime(after interval: TimeInterval, from now: Date = Date()) -> Date {
        let seconds = floor((now.timeIntervalSince1970 + interval) / 60) * 60
        return Date(timeIntervalSince1970: seconds)
    }

    /// The next occurrence of `time`, strictly after `now`.
    static func next(_ time: ClockTime, after now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                          matchingPolicy: .nextTime) ?? now
    }

    // MARK: Writing

    /// Root shell commands that make /Library/LaunchDaemons match `plan`. Prints `failureMarker` and exits 3 on failure.
    static func syncScript(_ plan: Plan, timers: DailyTimers) -> String {
        var lines = [
            "d=/Library/LaunchDaemons",
            "fail() { echo \"\(failureMarker): $1\" >&2; exit 3; }",
            "remove_job() { /bin/launchctl bootout \"system/$1\" </dev/null >/dev/null 2>&1; /bin/rm -f \"$d/$1.plist\" || fail \"remove $1\"; }",
            "install_job() {",
            " remove_job \"$1\"",
            " /bin/cat > \"$d/$1.plist\" || fail \"write $1\"",
            " /usr/sbin/chown root:wheel \"$d/$1.plist\" && /bin/chmod 644 \"$d/$1.plist\" || fail \"permissions $1\"",
            " n=0",
            " until /bin/launchctl bootstrap system \"$d/$1.plist\" </dev/null; do",
            "  n=$((n + 1)); [ \"$n\" -lt 4 ] || fail \"load $1\"; /bin/sleep 1",
            " done",
            "}",
            "/usr/bin/touch \(log) && /usr/sbin/chown root:wheel \(log) && /bin/chmod 644 \(log) || fail log",
        ]
        for job in Job.allCases {
            if let xml = plist(job, plan: plan, timers: timers) {
                lines.append("install_job \(job.rawValue) <<'POWERSWITCHER_PLIST_END'")
                lines.append(xml.trimmingCharacters(in: .newlines))
                lines.append("POWERSWITCHER_PLIST_END")
            } else {
                lines.append("remove_job \(job.rawValue)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The launchd plist for `job`, or nil when the plan does not use it.
    static func plist(_ job: Job, plan: Plan, timers: DailyTimers, calendar: Calendar = .current) -> String? {
        let t = timers.clamped
        var env = [acKey: String(t.ac), batteryKey: String(t.battery)]
        var interval: [String: Int]?
        var runAtLoad = false
        let script: String
        switch job {
        case .taskEnd:
            guard let end = plan.taskEnd else { return nil }
            let epoch = Int(end.timeIntervalSince1970)
            let c = calendar.dateComponents([.month, .day, .hour, .minute], from: end)
            interval = ["Month": c.month ?? 1, "Day": c.day ?? 1, "Hour": c.hour ?? 0, "Minute": c.minute ?? 0]
            env[endKey] = String(epoch)
            // Also runs at load (install, boot) so an end missed while the Mac was off still happens.
            runAtLoad = true
            script = """
            [ -f \(job.path) ] || exit 0
            now=$(/bin/date +%s)
            [ "$now" -ge \(epoch - 60) ] || exit 0
            # Within the last minute (registered just before the end, or a slightly early fire): wait, never end early.
            [ "$now" -ge \(epoch) ] || /bin/sleep $((\(epoch) - now))
            \(body("task-end", .normal, timers: t))
            /bin/rm -f \(job.path)
            /bin/launchctl bootout system/\(job.rawValue) </dev/null >/dev/null 2>&1
            exit $rc
            """
        case .dailyTask:
            guard let time = plan.dailyTask else { return nil }
            interval = ["Hour": time.hour, "Minute": time.minute]
            if let window = plan.window {
                // Acts only inside the Task window, so a fire that launchd delivers late (after sleep) can't undo a later switch.
                script = """
                \(window.shell)
                in_task || exit 0
                [ "$(\(sleepDisabled))" = 0 ] || exit 0
                \(body("daily-task", .task, timers: t))
                exit $rc
                """
            } else {
                script = body("daily-task", .task, timers: t) + "\nexit $rc"
            }
        case .dailyNormal:
            guard let time = plan.dailyNormal else { return nil }
            interval = ["Hour": time.hour, "Minute": time.minute]
            // Daily mode is in effect afterwards, so a pending one-shot end has nothing left to do.
            let clearEnd = """
            /bin/launchctl bootout system/\(Job.taskEnd.rawValue) </dev/null >/dev/null 2>&1
            /bin/rm -f \(Job.taskEnd.path)
            """
            if let window = plan.window {
                script = """
                \(window.shell)
                in_task && exit 0
                [ "$(\(sleepDisabled))" = 1 ] || \(taskTimersLeft) || exit 0
                \(body("daily-normal", .normal, timers: t))
                \(clearEnd)
                exit $rc
                """
            } else {
                script = """
                \(body("daily-normal", .normal, timers: t))
                \(clearEnd)
                exit $rc
                """
            }
        case .bootRestore:
            let window = plan.window
            guard plan.restoreAfterRestart || window != nil else { return nil }
            env[restoreKey] = plan.restoreAfterRestart ? "1" : "0"
            // A restart clears the global SleepDisabled flag but keeps Task mode's idle timers, so a profile left at
            // "never" (0, which Daily mode never sets) with sleep allowed means Task mode was interrupted.
            // With a daily window, startup follows the window instead (a switch may have been missed while off).
            // Runs at load only and acts only shortly after startup, not when registered.
            runAtLoad = true
            let decide: String
            if let window {
                decide = """
                \(window.shell)
                if in_task; then
                \(body("startup (daily window)", .task, timers: t))
                else
                \(taskTimersLeft) || exit 0
                \(body("startup (daily window)", .normal, timers: t))
                fi
                """
            } else {
                decide = """
                \(taskTimersLeft) || exit 0
                \(body("boot-restore", .task, timers: t))
                """
            }
            script = """
            now=$(/bin/date +%s)
            boot=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -E 's/^\\{ sec = ([0-9]+),.*$/\\1/')
            [ $((now - boot)) -lt 900 ] || exit 0
            n=0
            until /usr/bin/pmset -g >/dev/null 2>&1; do n=$((n + 1)); [ "$n" -lt 60 ] || exit 1; /bin/sleep 1; done
            [ "$(\(sleepDisabled))" = 0 ] || exit 0
            \(decide)
            exit $rc
            """
        }
        if job == .dailyTask { env = [:] }
        if job == .bootRestore { env.removeValue(forKey: acKey); env.removeValue(forKey: batteryKey) }
        env[revisionKey] = revision
        var dict: [String: Any] = [
            "Label": job.rawValue,
            "ProgramArguments": ["/bin/sh", "-c", script],
            "RunAtLoad": runAtLoad,
            "StandardOutPath": log,
            "StandardErrorPath": log,
            "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier ?? "org.powerswitcher.app"],
        ]
        dict["EnvironmentVariables"] = env
        if let interval { dict["StartCalendarInterval"] = interval }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Prints the live global SleepDisabled value (0 when absent).
    private static let sleepDisabled = "/usr/bin/pmset -g | /usr/bin/awk '$1==\"SleepDisabled\" {print $2; f=1} END {if (!f) print 0}'"
    /// Succeeds when a power-adapter profile is still at Task mode's "never" (0), which Daily mode never sets.
    private static let taskTimersLeft = "/usr/bin/pmset -g custom | /usr/bin/awk '/^[^ \\t].*:$/ {a=($0==\"AC Power:\" || $0==\"UPS Power:\")} a && $1==\"sleep\" && $2==\"0\" {f=1} END {exit !f}'"

    /// Runs the regular switching script in a subshell and logs the result; leaves its exit status in `rc`.
    private static func body(_ name: String, _ mode: PowerMode, timers: DailyTimers) -> String {
        """
        echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') \(name): switching to \(mode.rawValue)"
        out=$(/usr/bin/mktemp)
        (
        \(PowerCommand.script(for: mode, timers: timers))
        ) >"$out" 2>&1
        rc=$?
        # pmset's advice about display vs. sleep timers is noise here (Task mode disables sleep anyway).
        /usr/bin/grep -v -e 'may not behave as expected' -e 'should have a lower timeout than system sleep' "$out"
        /bin/rm -f "$out"
        echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') \(name): exit $rc"
        """
    }
}
