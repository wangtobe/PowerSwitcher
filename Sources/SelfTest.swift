import Foundation
import CryptoKit

/// `PowerSwitcher --self-test`: checks the embedded script and parsers without touching power settings.
enum SelfTest {
    static func perform() -> Bool {
        var ok = true
        func check(_ condition: Bool, _ name: String) {
            print((condition ? "PASS " : "FAIL ") + name)
            ok = ok && condition
        }
        for mode in PowerMode.allCases {
            let script = PowerCommand.script(for: mode, timers: .defaults)
            let result = run("/bin/sh", ["-n", "-c", script])
            if result.0 != 0 { print(result.1) }
            check(result.0 == 0, "embedded script: " + mode.rawValue)
            print(SHA256.hash(data: Data(script.utf8)).map { String(format: "%02x", $0) }.joined())
        }
        check(PowerMode(rawValue: "invalid") == nil, "unknown mode rejected; no resource files required")
        let clamped = PowerCommand.script(for: .normal, timers: DailyTimers(ac: 999, battery: 0))
        check(clamped.hasPrefix("mode=normal\ndaily_ac=180\ndaily_battery=1\n"), "daily timers clamped to 1...180")

        check(PowerSnapshot.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\n") == true, "SleepDisabled 1 means task mode")
        check(PowerSnapshot.parseSleepDisabled("System-wide power settings:\n") == false, "absent SleepDisabled means sleep allowed")
        check(PowerSnapshot.parseSleepDisabled(" SleepDisabled x\n") == nil, "unreadable SleepDisabled is unknown")

        let profiles = PowerSnapshot.parseProfiles("Battery Power:\n sleep                5\n ttyskeepawake        1\nAC Power:\n sleep                15 (sleep prevented by caffeinate)\n")
        check(profiles["AC Power"]?["sleep"] == 15 && profiles["Battery Power"]?["ttyskeepawake"] == 1, "profile parsing")
        var snapshot = PowerSnapshot()
        snapshot.profiles = profiles
        check(snapshot.matches(DailyTimers(ac: 15, battery: 5)) && !snapshot.matches(DailyTimers(ac: 30, battery: 5)), "preset comparison")
        var display = PowerSnapshot()
        display.profiles = PowerSnapshot.parseProfiles("AC Power:\n displaysleep         10\n sleep                5\nBattery Power:\n displaysleep         0\n sleep                5\n")
        var shorter = display
        shorter.profiles["AC Power"]?["displaysleep"] = 3
        shorter.profiles["Battery Power"]?["displaysleep"] = 5
        check(!display.matches(DailyTimers(ac: 5, battery: 5)) && shorter.matches(DailyTimers(ac: 5, battery: 5)), "display timer longer than idle timer needs updating")
        var restarted = PowerSnapshot()
        restarted.mode = .normal
        restarted.profiles = ["AC Power": ["sleep": 0], "Battery Power": ["sleep": 1]]
        var daily = restarted
        daily.profiles = ["AC Power": ["sleep": 15], "Battery Power": ["sleep": 1]]
        var task = restarted
        task.mode = .task
        check(restarted.looksLikeInterruptedTask && !daily.looksLikeInterruptedTask && !task.looksLikeInterruptedTask, "Task mode cleared by a restart recognized")

        let assertions = """
        Listed by owning process:
           pid 97(powerd): [0x0000000100000001] 00:10:00 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
           pid 812(caffeinate): [0x0000000100000002] 00:05:00 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
           pid 900(Music): [0x0000000100000003] 00:01:00 PreventUserIdleDisplaySleep named: "Playing audio"
        """
        check(PowerSnapshot.parseBlockers(assertions).map { $0.process } == ["caffeinate"], "sleep blockers; powerd and display-only filtered")

        let (source, percent) = PowerSnapshot.parseBattery("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1234)\t82%; discharging; 4:10 remaining present: true\n")
        check(source == .battery && percent == 82, "battery parsing")

        check(L10n.chinese(preferred: ["zh-Hans-CN", "en"]), "Simplified Chinese selected")
        check(L10n.chinese(preferred: ["zh-Hant-TW"]), "Traditional Chinese preference selects Chinese UI")
        check(!L10n.chinese(preferred: ["en-US", "zh"]), "first preferred language wins")
        check(!L10n.chinese(preferred: ["ja-JP"]), "unsupported language falls back to English")
        check(!L10n.chinese(preferred: []), "empty language list falls back to English")
        check(L10n.chinese(preferred: ["en"], override: "zh") && !L10n.chinese(preferred: ["zh"], override: "en"), "manual language override")
        check(Format.minutes(15) == L("15 分钟", "15 min"), "localized time formatting")
        // Scheduled jobs: generated, never installed by the self-test.
        let end = Schedule.endTime(after: 7200, from: Date(timeIntervalSince1970: 1_800_000_030))
        check(end.timeIntervalSince1970 == 1_800_007_200, "timer end aligned to a whole minute")
        let morning = Schedule.next(ClockTime(hour: 8, minute: 0), after: Date())
        check(morning > Date() && morning.timeIntervalSinceNow <= 86_400, "next 08:00 within a day")
        let plan = Schedule.Plan(taskEnd: end, dailyTask: ClockTime(hour: 23, minute: 5), dailyNormal: ClockTime(hour: 7, minute: 30), restoreAfterRestart: true)
        let timers = DailyTimers(ac: 20, battery: 4)
        var jobsOK = true
        for job in Schedule.Job.allCases {
            guard let xml = Schedule.plist(job, plan: plan, timers: timers), let info = Schedule.parse(Data(xml.utf8)),
                  let dict = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any],
                  dict["Label"] as? String == job.rawValue, let args = dict["ProgramArguments"] as? [String], args.count == 3 else { jobsOK = false; continue }
            if run("/bin/sh", ["-n", "-c", args[2]]).0 != 0 { jobsOK = false }
            switch job {
            case .taskEnd: jobsOK = jobsOK && info.end == 1_800_007_200 && info.timers == timers && dict["RunAtLoad"] as? Bool == true
            case .dailyTask: jobsOK = jobsOK && info.time == ClockTime(hour: 23, minute: 5) && args[2].contains("mode=task")
            case .dailyNormal: jobsOK = jobsOK && info.time == ClockTime(hour: 7, minute: 30) && info.timers == timers && args[2].contains(Schedule.Job.taskEnd.path)
            case .bootRestore: jobsOK = jobsOK && dict["StartCalendarInterval"] == nil && dict["RunAtLoad"] as? Bool == true && args[2].contains("mode=task")
            }
        }
        let revisionsOK = Schedule.Job.allCases.allSatisfy { job in
            Schedule.plist(job, plan: plan, timers: timers).flatMap { Schedule.parse(Data($0.utf8)) }?.revision == Schedule.revision
        }
        check(jobsOK && revisionsOK, "scheduled job plists parse, round-trip and pass sh -n")
        check(Schedule.plist(.taskEnd, plan: Schedule.Plan(), timers: timers) == nil, "unused scheduled job omitted")
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date())! }
        let day = Schedule.Window(task: ClockTime(hour: 9, minute: 0), normal: ClockTime(hour: 21, minute: 0))
        let night = Schedule.Window(task: ClockTime(hour: 23, minute: 0), normal: ClockTime(hour: 8, minute: 0))
        check(day.isTask(at: at(14, 0)) && day.isTask(at: at(9, 0)) && !day.isTask(at: at(21, 0)) && !day.isTask(at: at(8, 59))
              && night.isTask(at: at(2, 0)) && night.isTask(at: at(23, 0)) && !night.isTask(at: at(12, 0)) && !night.isTask(at: at(8, 0)),
              "daily window, including one past midnight")
        let windowOnly = Schedule.Plan(dailyTask: day.task, dailyNormal: day.normal)
        let startup = Schedule.plist(.bootRestore, plan: windowOnly, timers: timers).flatMap { Schedule.parse(Data($0.utf8)) }
        check(startup?.restore == false && Schedule.plist(.bootRestore, plan: Schedule.Plan(dailyNormal: day.normal), timers: timers) == nil,
              "startup job follows a daily window without the restore option")
        let sync = Schedule.syncScript(Schedule.Plan(dailyNormal: ClockTime(hour: 8, minute: 0)), timers: timers)
        check(run("/bin/sh", ["-n", "-c", sync]).0 == 0 && sync.contains("remove_job " + Schedule.Job.taskEnd.rawValue)
              && sync.contains("install_job " + Schedule.Job.dailyNormal.rawValue), "schedule sync script")
        print("Backlight API: " + (Backlight.available ? "available" : "unavailable (lid dimming disabled)"))
        print("UI language: " + (L10n.isChinese ? "zh" : "en"))
        print("Application: " + Bundle.main.bundleURL.path)
        return ok
    }
}
