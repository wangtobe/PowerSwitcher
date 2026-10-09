import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let card = StatusCardView()
    private let blockersMenu = NSMenu()
    private var blockersItem: NSMenuItem!, applyTimersItem: NSMenuItem!, lastSleepItem: NSMenuItem!
    private var dailyItem: NSMenuItem!, taskItem: NSMenuItem!, sleepItem: NSMenuItem!, timedItem: NSMenuItem!
    private let timedMenu = NSMenu()
    /// Scheduled jobs registered in /Library/LaunchDaemons, re-read on every render.
    private var schedule = Schedule.Installed()
    /// True while an administrator prompt is updating scheduled jobs without switching modes.
    private var scheduling = false

    private var snapshot: PowerSnapshot?
    /// Target mode while an authorised switch is running.
    private var switching: PowerMode?
    private var refreshing = false
    private var menuOpen = false
    private var lowBatteryWarned = false
    private var timer: Timer?
    private var sleepWatchdog: DispatchWorkItem?
    private var lidTimer: Timer?
    private var lidActivity: NSObjectProtocol?
    private var lidWasClosed = false
    private let feedback = FeedbackPopover()
    private let reader = DispatchQueue(label: "org.powerswitcher.reader", qos: .userInitiated)
    private var setupAssistant: SetupAssistant?
    private var settingsWindow: SettingsWindow?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        statusItem.menu = menu
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        // A previous run may have quit with the lid shut and the panel dimmed.
        if Lid.isClosed() != true { restoreBacklight() }
        render()
        readSnapshot { snapshot in
            self.snapshot = snapshot
            self.render()
            if !Preferences.setupCompleted { self.showSetup(nil) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 5
    }

    func applicationWillTerminate(_ notification: Notification) { restoreBacklight() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Preferences.setupCompleted { statusItem.button?.performClick(nil) } else { showSetup(nil) }
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        feedback.dismiss()
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let cardItem = NSMenuItem()
        cardItem.view = card
        menu.addItem(cardItem)
        blockersItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        blockersItem.image = symbol(["exclamationmark.triangle"], L("阻止休眠", "Sleep blockers"))
        blockersItem.submenu = blockersMenu
        menu.addItem(blockersItem)
        applyTimersItem = addItem(L("更新为设定的休眠时间…", "Apply configured sleep timers…"), #selector(applyTimers), symbols: ["arrow.triangle.2.circlepath"])
        lastSleepItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastSleepItem.image = symbol(["clock"], L("上次实际休眠", "Last recorded sleep"))
        lastSleepItem.isEnabled = false
        menu.addItem(lastSleepItem)

        menu.addItem(.separator())
        dailyItem = addItem(PowerMode.normal.title, #selector(chooseDaily), symbols: PowerMode.normal.symbols)
        dailyItem.toolTip = L("允许系统休眠：闲置到设定时间后自动休眠。", "Allow system sleep after the configured idle interval.")
        taskItem = addItem(PowerMode.task.title, #selector(chooseTask), symbols: PowerMode.task.symbols)
        taskItem.toolTip = L("禁止系统休眠（使用电池时也一样），用于合上盖子后继续运行。", "Disable system sleep, including on battery, for ongoing work.")
        timedItem = NSMenuItem(title: L("任务模式，定时结束", "Task Mode for…"), action: nil, keyEquivalent: "")
        timedItem.image = symbol(["timer"], L("定时", "Timer"))
        timedItem.submenu = timedMenu
        menu.addItem(timedItem)

        menu.addItem(.separator())
        sleepItem = addItem(L("立即休眠…", "Sleep Now…"), #selector(sleepNow), symbols: ["moon.zzz"])

        menu.addItem(.separator())
        addItem(L("设置…", "Settings…"), #selector(showSettings), symbols: ["gearshape"], key: ",")
        let languages = NSMenu()
        for (label, value) in [("跟随系统 / System", "system"), ("简体中文", "zh"), ("English", "en")] {
            let item = addItem(label, #selector(setLanguage(_:)), to: languages)
            item.representedObject = value
            item.state = (UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system") == value ? .on : .off
        }
        let languageItem = NSMenuItem(title: "语言 / Language", action: nil, keyEquivalent: "")
        languageItem.submenu = languages
        menu.addItem(languageItem)
        let more = NSMenu()
        addItem(L("详细电源信息…", "Detailed Power Information…"), #selector(showDetails), to: more)
        addItem(L("重新运行设置向导…", "Run Setup Again…"), #selector(showSetup(_:)), to: more)
        more.addItem(.separator())
        addItem(L("关于 PowerSwitcher", "About PowerSwitcher"), #selector(showAbout), to: more)
        let moreItem = NSMenuItem(title: L("更多", "More"), action: nil, keyEquivalent: "")
        moreItem.image = symbol(["ellipsis.circle"], L("更多", "More"))
        moreItem.submenu = more
        menu.addItem(moreItem)

        menu.addItem(.separator())
        let quitItem = addItem(L("退出 PowerSwitcher", "Quit PowerSwitcher"), #selector(quit), symbols: ["power"], key: "q")
        quitItem.toolTip = L("退出不会更改电源设置。", "Quitting does not change power settings.")
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, symbols: [String] = [], key: String = "", to target: NSMenu? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        if !symbols.isEmpty { entry.image = symbol(symbols, title) }
        (target ?? menu).addItem(entry)
        return entry
    }

    private func info(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    // MARK: State

    private func readSnapshot(_ done: @escaping (PowerSnapshot) -> Void) {
        reader.async {
            let snapshot = PowerSnapshot.read()
            DispatchQueue.main.async { done(snapshot) }
        }
    }

    private func refresh() {
        guard switching == nil, !refreshing else { return }
        refreshing = true
        readSnapshot { snapshot in
            self.refreshing = false
            guard self.switching == nil else { return }
            self.snapshot = snapshot
            self.render()
            self.checkLowBattery()
        }
    }

    private func tint(_ mode: PowerMode, _ s: PowerSnapshot) -> NSColor {
        switch mode {
        case .task: return s.source == .battery ? .systemRed : .systemOrange
        case .normal: return .systemIndigo
        }
    }

    private func render() {
        schedule = Schedule.installed()
        let idle = switching == nil && !scheduling
        let mode = switching == nil ? snapshot?.mode : nil
        dailyItem.state = mode == .normal ? .on : .off
        taskItem.state = mode == .task ? .on : .off
        [dailyItem, taskItem, sleepItem, timedItem].forEach { $0?.isEnabled = idle }
        renderTimedMenu(mode)
        sleepItem.title = mode == .task ? L("切回日常模式并立即休眠…", "Switch to Daily Mode and Sleep…") : L("立即休眠…", "Sleep Now…")
        blockersItem.isHidden = true
        applyTimersItem.isHidden = true
        lastSleepItem.title = lastSleepText()

        let icon: [String], label: String
        if let target = switching {
            card.update(symbols: ["hourglass"], tint: .secondaryLabelColor, title: L("正在切换到\(target.title)…", "Switching to \(target.title)…"),
                        detail: L("请在系统对话框中输入管理员密码。之后会逐项应用并校验电源设置，请稍候。", "Enter your administrator password in the system dialog. Settings will then be applied and verified."))
            icon = ["hourglass"]
            label = L("正在切换到", "Switching to ") + target.title
        } else if let s = snapshot, let mode = s.mode {
            let onBattery = s.source == .battery
            var lines: [String] = []
            switch mode {
            case .task:
                lines.append(L("已禁止系统休眠，Mac 不会自动休眠。", "System sleep is disabled. Your Mac will stay awake."))
                if let end = schedule.plan.taskEnd {
                    lines.append(L("将于 \(Format.time(end)) 自动切回日常模式。", "Returns to Daily mode at \(Format.time(end))."))
                }
                if let source = Format.source(s) { lines.append(source) }
                if onBattery { lines.append(L("正在使用电池：放进包里前请切回日常模式。", "On battery: switch to Daily mode before putting your Mac in a bag.")) }
                icon = onBattery ? ["bolt.trianglebadge.exclamationmark.fill", "exclamationmark.triangle.fill"] : mode.symbols
                label = mode.title + (onBattery ? L("（电池供电）", " (on battery)") : "")
            case .normal:
                let matches = s.matches(Preferences.timers)
                lines.append(Format.timers(ac: s.acIdleMinutes, battery: s.idleMinutes("Battery Power")) + (matches ? L("。", ".") : L("（与设定不同）。", " (different from your preferences).")))
                if let source = Format.source(s) { lines.append(source) }
                icon = mode.symbols
                label = mode.title
                renderBlockers(s)
                applyTimersItem.isHidden = matches || !Preferences.setupCompleted
                applyTimersItem.toolTip = L("设定：", "Configured: ") + Format.timers(Preferences.timers, hasBattery: s.hasBattery)
            }
            card.update(symbols: mode.symbols, tint: tint(mode, s), title: mode.title, detail: lines.joined(separator: "\n"))
        } else {
            card.update(symbols: ["questionmark.circle"], tint: .secondaryLabelColor, title: snapshot == nil ? L("正在读取电源状态…", "Reading power status…") : L("无法读取电源状态", "Couldn't read power status"),
                        detail: snapshot == nil ? "" : L("pmset 没有返回可识别的结果。可在“更多 › 详细电源信息”中查看原始输出。", "pmset returned no recognizable status. See More › Detailed Power Information for the raw output."))
            icon = ["questionmark.circle"]
            label = L("电源状态未知", "Power status unknown")
        }

        updateLidWatch()

        guard let button = statusItem.button else { return }
        if let image = symbol(icon, label) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "PS"
        }
        button.toolTip = "PowerSwitcher · " + label
        button.setAccessibilityLabel("PowerSwitcher：" + label)
    }

    /// Only meaningful in daily mode: sleep is allowed, but these processes can still keep the Mac awake.
    private func renderBlockers(_ s: PowerSnapshot) {
        let names = s.blockingProcesses
        guard !names.isEmpty else { return }
        blockersItem.isHidden = false
        blockersItem.title = L("\(names.count) 个进程正在阻止闲置休眠", "\(names.count) processes preventing idle sleep")
        blockersMenu.removeAllItems()
        for b in s.blockers {
            let reason = b.reason.count > 48 ? String(b.reason.prefix(47)) + "…" : b.reason
            let entry = info("\(b.process)（PID \(b.pid)）· \(reason)")
            entry.toolTip = b.kind + ": " + b.reason
            blockersMenu.addItem(entry)
        }
        blockersMenu.addItem(.separator())
        let idleOnly = s.blockers.allSatisfy { $0.kind != "PreventSystemSleep" }
        blockersMenu.addItem(info(idleOnly ? L("这些请求只阻止闲置休眠，不影响“立即休眠”。", "These requests prevent idle sleep, but not Sleep Now.")
                                           : L("部分请求可能阻止所有休眠。结束对应任务后再试。", "Some requests may prevent all sleep. Finish the relevant tasks and retry.")))
        addItem(L("详细电源信息…", "Detailed Power Information…"), #selector(showDetails), to: blockersMenu)
    }

    private func lastSleepText() -> String {
        guard let slept = Preferences.lastSleep else { return L("尚未记录到实际休眠", "No sleep event recorded yet") }
        if let woke = Preferences.lastWake, woke > slept {
            return L("上次实际休眠：\(Format.time(slept))，\(Format.duration(from: slept, to: woke))", "Last sleep: \(Format.time(slept)), \(Format.duration(from: slept, to: woke))")
        }
        return L("上次实际休眠：\(Format.time(slept))", "Last sleep: \(Format.time(slept))")
    }

    // MARK: Switching

    @objc private func chooseDaily() { switchTo(.normal) }
    @objc private func chooseTask() { switchTo(.task) }
    @objc private func applyTimers() { switchTo(.normal) }

    private func switchTo(_ mode: PowerMode, plan: Schedule.Plan? = nil, quiet: Bool = false, then next: ((Bool) -> Void)? = nil) {
        guard switching == nil, !scheduling else { return }
        var plan = plan
        // Returning to Daily mode by hand makes a pending end of Task mode pointless.
        if mode == .normal, plan == nil, schedule.plan.taskEnd != nil {
            plan = schedule.plan
            plan?.taskEnd = nil
        }
        // Re-running the current preset only makes sense when daily timers differ from the settings.
        if let s = snapshot, s.mode == mode, next == nil, plan == nil, mode == .task || s.matches(Preferences.timers) {
            feedback.show(mode.symbols, tint: tint(mode, s), title: L("当前已是", "Already in ") + mode.title, detail: nil, from: statusItem.button)
            return
        }
        switching = mode
        feedback.dismiss()
        render()
        PowerCommand.apply(mode, timers: Preferences.timers, schedule: plan) { outcome in
            self.readSnapshot { snapshot in
                self.switching = nil
                self.snapshot = snapshot
                self.render()
                switch outcome {
                case .success:
                    if !quiet { self.confirmSwitch(mode, snapshot) }
                    next?(true)
                case .cancelled:
                    next?(false)
                case .failed(let log):
                    self.reportFailure(mode, log)
                    next?(false)
                case .scheduleFailed(let log):
                    self.reportScheduleFailure(log)
                    next?(true)
                }
            }
        }
    }

    // MARK: Schedule

    private func renderTimedMenu(_ mode: PowerMode?) {
        timedMenu.removeAllItems()
        if mode == .task, let end = schedule.plan.taskEnd {
            timedMenu.addItem(info(L("将于 \(Format.time(end)) 切回日常模式", "Returns to Daily mode at \(Format.time(end))")))
            addItem(L("取消定时", "Cancel Timer"), #selector(cancelTimed), to: timedMenu)
            timedMenu.addItem(.separator())
            timedMenu.addItem(info(L("改为：", "Change to:")))
        } else if mode != .task {
            timedMenu.addItem(info(L("切到任务模式，到点自动切回：", "Switch to Task mode, then return automatically:")))
        } else {
            timedMenu.addItem(info(L("到点自动切回日常模式：", "Return to Daily mode automatically:")))
        }
        for hours in [1, 2, 4, 8] {
            let item = addItem(L("\(hours) 小时后", hours == 1 ? "In 1 Hour" : "In \(hours) Hours"), #selector(chooseTimed(_:)), to: timedMenu)
            item.representedObject = Schedule.endTime(after: TimeInterval(hours * 3600))
        }
        let morning = Schedule.next(.dailyDefault)
        let until = addItem(L("到 \(Format.time(morning))", "Until \(Format.time(morning))"), #selector(chooseTimed(_:)), to: timedMenu)
        until.representedObject = morning

        timedMenu.addItem(.separator())
        let plan = schedule.plan
        if let time = plan.dailyTask { timedMenu.addItem(info(L("每天 \(time.text) 进入任务模式", "Every day at \(time.text): Task mode"))) }
        if let time = plan.dailyNormal { timedMenu.addItem(info(L("每天 \(time.text) 切回日常模式", "Every day at \(time.text): Daily mode"))) }
        addItem(plan.dailyTask == nil && plan.dailyNormal == nil ? L("每天定时切换…", "Daily Schedule…") : L("更改每天定时…", "Change Daily Schedule…"),
                #selector(showSettings), to: timedMenu)
    }

    @objc private func chooseTimed(_ sender: NSMenuItem) {
        guard let end = sender.representedObject as? Date else { return }
        var plan = schedule.plan
        plan.taskEnd = end
        if snapshot?.mode == .task {
            updateSchedule(plan, done: L("将于 \(Format.time(end)) 切回日常模式", "Returns to Daily mode at \(Format.time(end))"))
        } else {
            switchTo(.task, plan: plan)
        }
    }

    @objc private func cancelTimed() {
        var plan = schedule.plan
        plan.taskEnd = nil
        updateSchedule(plan, done: L("已取消定时，任务模式会一直保持", "Timer cancelled. Task mode stays on"))
    }

    /// Registers `plan` without switching modes.
    private func updateSchedule(_ plan: Schedule.Plan, done: String) {
        guard switching == nil, !scheduling else { return }
        scheduling = true
        feedback.dismiss()
        render()
        PowerCommand.apply(nil, timers: Preferences.timers, schedule: plan) { outcome in
            self.scheduling = false
            self.render()
            switch outcome {
            case .success:
                self.feedback.show(["timer"], tint: .systemBlue, title: done, detail: nil, from: self.statusItem.button)
            case .cancelled:
                break
            case .failed(let log), .scheduleFailed(let log):
                self.reportScheduleFailure(log)
            }
        }
    }

    private func reportScheduleFailure(_ log: String) {
        let (response, _) = UI.alert(L("定时切换没有设置成功", "Couldn't set up the scheduled switch"),
                                     L("当前模式以菜单顶部显示为准。可以稍后再试，或在“设置…”里查看每天定时。", "Check the status at the top of the menu. You can try again later or review the daily schedule in Settings."),
                                     style: .warning, buttons: [L("好", "OK"), L("复制详细信息", "Copy Details")], log: log)
        if response == .alertSecondButtonReturn { copy(log) }
    }

    private func confirmSwitch(_ mode: PowerMode, _ s: PowerSnapshot) {
        var detail: String
        switch mode {
        case .task:
            detail = s.source == .battery ? L("正在使用电池，也不会自动休眠。请留意电量。", "On battery, system sleep is still disabled. Watch your battery level.") : L("已禁止系统休眠，Mac 不会自动休眠。", "System sleep is disabled. Your Mac will stay awake.")
            if let end = schedule.plan.taskEnd { detail += L("\n将于 \(Format.time(end)) 自动切回日常模式。", "\nReturns to Daily mode at \(Format.time(end)).") }
        case .normal:
            detail = Format.timers(ac: s.acIdleMinutes, battery: s.idleMinutes("Battery Power")) + L("。", ".")
            let blockers = s.blockingProcesses.count
            if blockers > 0 { detail += L("\n有 \(blockers) 个进程在阻止闲置休眠，详见菜单。", "\n\(blockers) processes are preventing idle sleep. See the menu.") }
        }
        feedback.show(mode.symbols, tint: tint(mode, s), title: L("已切换到", "Switched to ") + mode.title, detail: detail, from: statusItem.button)
    }

    private func reportFailure(_ mode: PowerMode, _ log: String) {
        let (response, _) = UI.alert(L("未能切换到", "Couldn't switch to ") + mode.title,
                                     L("电源设置如有部分更改，PowerSwitcher 已尝试恢复原状。当前状态以菜单顶部显示为准。", "PowerSwitcher attempted to roll back any partial changes. Check the status at the top of the menu."),
                                     style: .warning, buttons: [L("好", "OK"), L("复制详细信息", "Copy Details")], log: log)
        if response == .alertSecondButtonReturn { copy(log) }
    }

    private func checkLowBattery() {
        guard let s = snapshot, s.mode == .task, s.source == .battery else { lowBatteryWarned = false; return }
        guard Preferences.lowBatteryWarning, !lowBatteryWarned, !menuOpen, switching == nil,
              let percent = s.batteryPercent, percent <= Preferences.lowBatteryThreshold else { return }
        lowBatteryWarned = true
        let (response, _) = UI.alert(L("电量 \(percent)%，Mac 仍在持续运行", "Battery at \(percent)% — your Mac is still awake"),
                                     L("任务模式下即使电量很低也不会自动休眠。如果准备把 Mac 放进包里，建议切回日常模式。", "Task mode prevents automatic sleep even on a low battery. Switch to Daily mode before putting your Mac in a bag."),
                                     style: .warning, buttons: [L("切回日常模式", "Switch to Daily Mode"), L("继续持续运行", "Keep Running")])
        if response == .alertFirstButtonReturn { switchTo(.normal) }
    }

    // MARK: Lid

    /// Watches the lid only while in task mode with the option on.
    private func updateLidWatch() {
        let active = switching == nil && snapshot?.mode == .task && Preferences.displayOffOnLidClose && Lid.exists
        if active, lidTimer == nil {
            // Keep App Nap from deferring the poll. Allows idle system sleep, so it adds no sleep assertion;
            // it only runs in task mode, where system sleep is already disabled.
            lidActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                reason: L("任务模式：合上盖子时关闭屏幕", "Task mode: turn off display when lid closes"))
            lidWasClosed = Lid.isClosed() ?? false
            lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkLid() }
            lidTimer?.tolerance = 0.3
        } else if !active, let timer = lidTimer {
            timer.invalidate()
            lidTimer = nil
            if let activity = lidActivity { ProcessInfo.processInfo.endActivity(activity) }
            lidActivity = nil
            restoreBacklight()
        }
    }

    /// Display sleep is requested once per closing. Remote-control tools (UU Remote, for example) wake the
    /// display again right after it turns off, so when the user opts in, the backlight is also held at zero
    /// for as long as the lid stays shut: the panel stays dark while remote viewing keeps working.
    private func checkLid() {
        guard let closed = Lid.isClosed() else { return }
        let justClosed = closed && !lidWasClosed
        lidWasClosed = closed
        guard closed else { restoreBacklight(); return }
        if Preferences.keepDarkOnLidClose { dimBacklight() } else { restoreBacklight() }
        if justClosed, !Lid.hasExternalDisplay { reader.async { Lid.turnDisplayOff() } }
    }

    private func dimBacklight() {
        guard let level = Backlight.level, level > 0.001 else { return }
        if Preferences.dimmedBrightness == nil { Preferences.dimmedBrightness = level }
        Backlight.set(0)
    }

    private func restoreBacklight() {
        guard let saved = Preferences.dimmedBrightness else { return }
        // Not restored yet when the panel is unavailable (still shut, or clamshell mode); keep the value for later.
        guard let level = Backlight.level else { return }
        if level < 0.001 { Backlight.set(saved) }
        Preferences.dimmedBrightness = nil
    }

    // MARK: Sleep

    @objc private func sleepNow() {
        guard switching == nil else { return }
        if snapshot?.mode == .task {
            // The admin prompt doubles as confirmation; sleep only after daily mode is verified.
            switchTo(.normal, quiet: true) { ok in if ok { self.performSleep() } }
            return
        }
        if !Preferences.skipSleepConfirmation {
            let (response, suppress) = UI.alert(L("现在让 Mac 休眠？", "Put your Mac to sleep now?"), L("正在运行的任务和远程连接会暂停，直到 Mac 被唤醒。", "Running tasks and remote connections will pause until your Mac wakes."),
                                                buttons: [L("休眠", "Sleep"), L("取消", "Cancel")], suppression: L("不再询问", "Don't ask again"))
            guard response == .alertFirstButtonReturn else { return }
            if suppress { Preferences.skipSleepConfirmation = true }
        }
        performSleep()
    }

    private func performSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let (code, output) = run("/usr/bin/pmset", ["sleepnow"])
            guard code == 0 else { self.reportNoSleep(output); return }
            // Requesting sleep is not proof of sleep: confirm via the system's willSleep notification.
            let watchdog = DispatchWorkItem { [weak self] in self?.reportNoSleep(nil) }
            self.sleepWatchdog?.cancel()
            self.sleepWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: watchdog)
        }
    }

    private func reportNoSleep(_ output: String?) {
        sleepWatchdog = nil
        readSnapshot { s in
            self.snapshot = s
            self.render()
            var reasons: [String] = []
            if s.mode == .task { reasons.append(L("仍处于任务模式（已禁止系统休眠）。", "Task mode is still active (system sleep disabled).")) }
            if !s.blockingProcesses.isEmpty { reasons.append(L("正在阻止休眠的进程：", "Processes preventing sleep: ") + s.blockingProcesses.joined(separator: L("、", ", ")) + L("。", ".")) }
            if reasons.isEmpty { reasons.append(L("系统没有进入休眠，原因未知。", "The Mac did not sleep. The reason is unknown.")) }
            let (response, _) = UI.alert(L("Mac 没有进入休眠", "Your Mac did not go to sleep"),
                                         reasons.joined(separator: "\n") + L("\n\nMac 仍在运行。放进包里之前，请确认它已经休眠。", "\n\nYour Mac is still running. Confirm it is asleep before putting it in a bag."),
                                         style: .warning, buttons: [L("好", "OK"), L("查看详细电源信息", "View Power Information")], log: output)
            if response == .alertSecondButtonReturn { self.showDetails() }
        }
    }

    @objc private func willSleep(_ notification: Notification) {
        sleepWatchdog?.cancel()
        sleepWatchdog = nil
        Preferences.lastSleep = Date()
    }

    @objc private func didWake(_ notification: Notification) {
        Preferences.lastWake = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() }
    }

    // MARK: Windows

    @objc private func showSetup(_ sender: Any?) {
        if let assistant = setupAssistant { assistant.show(); return }
        let assistant = SetupAssistant(snapshot: snapshot)
        assistant.onFinish = { [weak self] apply in self?.setupFinished(apply: apply) }
        assistant.onClose = { [weak self] in DispatchQueue.main.async { [weak self] in self?.setupAssistant = nil } }
        setupAssistant = assistant
        assistant.show()
    }

    private func setupFinished(apply: Bool) {
        render()
        if apply {
            switchTo(.normal)
        } else {
            feedback.show(["checkmark.circle"], tint: .systemGreen, title: L("设置完成", "Setup Complete"), detail: L("点按菜单栏图标即可切换模式。", "Use the menu bar icon to switch modes."), from: statusItem.button)
        }
    }

    @objc private func showSettings() {
        if let window = settingsWindow { window.show(); return }
        let window = SettingsWindow(snapshot: snapshot)
        window.onSave = { [weak self] daily in self?.settingsSaved(daily) }
        window.onClose = { [weak self] in DispatchQueue.main.async { [weak self] in self?.settingsWindow = nil } }
        settingsWindow = window
        window.show()
    }

    private func settingsSaved(_ daily: (task: ClockTime?, normal: ClockTime?)) {
        // Jobs returning to Daily mode carry the daily timers, so they are re-registered when the timers change.
        var plan = schedule.plan
        plan.dailyTask = daily.task
        plan.dailyNormal = daily.normal
        let returnsToDaily = plan.taskEnd != nil || plan.dailyNormal != nil
        let needsSync = plan != schedule.plan || (returnsToDaily && schedule.timers != Preferences.timers.clamped)
        readSnapshot { s in
            self.snapshot = s
            self.render()
            let timersPending = s.mode == .normal && !s.matches(Preferences.timers)
            if timersPending {
                let (response, _) = UI.alert(L("现在应用新的休眠时间？", "Apply the new sleep timers now?"), L("当前处于日常模式，系统仍在使用原来的休眠时间。应用新设定需要管理员密码。", "Daily mode is active but the system still uses the old timers. Applying new timers requires an administrator password."),
                                             buttons: [L("现在应用", "Apply Now"), L("稍后", "Later")])
                // One prompt covers both the timers and the schedule.
                if response == .alertFirstButtonReturn { self.switchTo(.normal, plan: needsSync ? plan : nil); return }
            }
            if needsSync {
                self.updateSchedule(plan, done: plan.dailyTask == nil && plan.dailyNormal == nil ? L("已关闭每天定时切换", "Daily schedule turned off") : L("每天定时切换已更新", "Daily schedule updated"))
            } else if !timersPending {
                self.feedback.show(["checkmark.circle"], tint: .systemGreen, title: L("设置已保存", "Settings Saved"),
                                   detail: s.mode == .task ? L("新的休眠时间会在切回日常模式时生效。", "New sleep timers will apply when you return to Daily mode.") : nil, from: self.statusItem.button)
            }
        }
    }

    @objc private func showDetails() {
        reader.async {
            let commands: [(String, [String])] = [("pmset -g", ["-g"]), ("pmset -g custom", ["-g", "custom"]),
                                                  ("pmset -g assertions", ["-g", "assertions"]), ("pmset -g batt", ["-g", "batt"])]
            let raw = commands.map { title, args in "== \(title) ==\n" + run("/usr/bin/pmset", args).1 }.joined(separator: "\n")
            DispatchQueue.main.async {
                let summary = self.detailSummary()
                let (response, _) = UI.alert(L("详细电源信息", "Detailed Power Information"), summary, buttons: [L("关闭", "Close"), L("复制全部", "Copy All")],
                                             log: raw, logSize: NSSize(width: 620, height: 340))
                if response == .alertSecondButtonReturn { self.copy(summary + "\n\n" + raw) }
            }
        }
    }

    private func detailSummary() -> String {
        guard let s = snapshot, let mode = s.mode else { return L("无法解读当前电源状态，请查看下方的原始输出。", "Couldn't interpret power status. See the raw output below.") }
        var lines = [
            L("当前：\(mode.title)（SleepDisabled = \(mode == .task ? 1 : 0)）", "Current: \(mode.title) (SleepDisabled = \(mode == .task ? 1 : 0))"),
            L("闲置休眠：", "Idle sleep: ") + Format.timers(ac: s.acIdleMinutes, battery: s.idleMinutes("Battery Power")),
            L("你的日常模式设定：", "Your Daily mode timers: ") + Format.timers(Preferences.timers, hasBattery: s.hasBattery),
            L("阻止闲置休眠的进程：", "Processes preventing idle sleep: ") + (s.blockingProcesses.isEmpty ? L("无", "None") : s.blockingProcesses.joined(separator: L("、", ", "))),
            lastSleepText(),
        ]
        lines.append(L("菜单栏图标表示当前是否允许休眠，不代表 Mac 已经休眠过。", "The menu bar icon shows whether sleep is allowed, not whether your Mac has actually slept."))
        return lines.joined(separator: "\n")
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: "interfaceLanguage")
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String) == value ? .on : .off }
        UI.alert("语言已保存 / Language saved", "重新打开 PowerSwitcher 后生效。\nReopen PowerSwitcher to apply.\n\n退出应用不会改变电源设置。\nQuitting does not change power settings.")
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: "")
        func line(_ text: String, bold: Bool = false) {
            credits.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: bold ? .semibold : .regular),
                .foregroundColor: NSColor.labelColor
            ]))
        }
        line(L("让 Mac 专注工作，也安心休息。", "Keep your Mac working. Let it rest when you're done."), bold: true)
        line("")
        line(L("作者", "Authors"), bold: true)
        line("Tobe Wang")
        line("GPT")
        line("Claude")
        line("")
        line(L("原生 AppKit · Intel 与 Apple Silicon", "Native AppKit · Intel & Apple Silicon"))
        line(L("不收集数据，不保存管理员密码。", "No data collection. No administrator passwords stored."))
        line(L("MIT 开源许可", "Open source under the MIT License"))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "PowerSwitcher",
            .credits: credits])
    }

    @objc private func quit() {
        guard switching == nil else { return }
        if snapshot?.mode == .task {
            let (response, _) = UI.alert(L("退出后 Mac 仍会持续运行", "Your Mac will stay awake after quitting"), L("退出 PowerSwitcher 不会更改电源设置，任务模式会一直生效，直到你再次切换。", "Quitting PowerSwitcher does not change power settings. Task mode stays active until you switch it off."),
                                         buttons: [L("退出", "Quit"), L("取消", "Cancel")])
            guard response == .alertFirstButtonReturn else { return }
        }
        NSApp.terminate(nil)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.perform() ? 0 : 1)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
