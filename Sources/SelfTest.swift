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
        print("Backlight API: " + (Backlight.available ? "available" : "unavailable (lid dimming disabled)"))
        print("UI language: " + (L10n.isChinese ? "zh" : "en"))
        print("Application: " + Bundle.main.bundleURL.path)
        return ok
    }
}
