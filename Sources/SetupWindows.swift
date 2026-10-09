import AppKit
import ServiceManagement

/// Controls shared by the setup assistant and the settings window.
final class PreferencesForm: NSObject {
    let hasBattery: Bool
    private let acPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let batteryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lowBatteryBox = NSButton(checkboxWithTitle: L("任务模式下，电池电量低于 \(Preferences.lowBatteryThreshold)% 时提醒我", "Warn me below \(Preferences.lowBatteryThreshold)% battery in Task mode"), target: nil, action: nil)
    private let loginBox = NSButton(checkboxWithTitle: L("登录 Mac 时自动打开 PowerSwitcher", "Open PowerSwitcher when I log in"), target: nil, action: nil)
    private let lidBox = NSButton(checkboxWithTitle: L("任务模式下，合上盖子时关闭屏幕（任务继续运行）", "Turn off the display when closing the lid in Task mode"), target: nil, action: nil)
    private let darkBox = NSButton(checkboxWithTitle: L("合盖期间保持黑屏（亮度降到 0，开盖后恢复）", "Keep the screen dark while the lid is closed"), target: nil, action: nil)
    private let hasLid = Lid.exists
    private let width: CGFloat

    init(snapshot: PowerSnapshot?, timers: DailyTimers, width: CGFloat) {
        hasBattery = snapshot?.hasBattery ?? true
        self.width = width
        super.init()
        select(timers)
        lowBatteryBox.state = Preferences.lowBatteryWarning ? .on : .off
        loginBox.state = LoginItem.isEnabled ? .on : .off
        lidBox.state = Preferences.displayOffOnLidClose ? .on : .off
        darkBox.state = Preferences.keepDarkOnLidClose ? .on : .off
        lidBox.target = self
        lidBox.action = #selector(lidChanged)
        lidChanged()
    }

    @objc private func lidChanged() { darkBox.isEnabled = lidBox.state == .on }

    /// The lid option, plus the dark-screen option indented under it when brightness control is available.
    private func lidView() -> NSView {
        guard Backlight.available else { return lidBox }
        let note = UI.paragraph(L("远程控制等软件可能会在合盖后重新点亮屏幕。开启后会把内屏亮度降到 0，屏幕不发光，远程画面照常；开盖后恢复原亮度。",
                                  "Remote-control apps may wake the screen after the lid closes. With this on, PowerSwitcher sets the built-in brightness to 0 so the panel stays dark while remote viewing keeps working, and restores it when you open the lid."),
                                width: width - 40, size: 11)
        let sub = UI.stack([darkBox, note], spacing: 4)
        sub.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        return UI.stack([lidBox, sub], spacing: 6)
    }

    var timers: DailyTimers {
        DailyTimers(ac: acPopup.selectedTag(), battery: hasBattery ? batteryPopup.selectedTag() : Preferences.timers.battery)
    }

    func select(_ timers: DailyTimers) {
        fill(acPopup, DailyTimers.acChoices, selected: timers.ac)
        fill(batteryPopup, DailyTimers.batteryChoices, selected: timers.battery)
    }

    func timersView() -> NSView {
        func after() -> NSTextField { UI.label(L("后自动休眠", "before sleeping"), color: .secondaryLabelColor) }
        var rows: [[NSView]] = [[UI.label(L("接电时闲置", "On power, idle for")), acPopup, after()]]
        if hasBattery { rows.append([UI.label(L("使用电池时闲置", "On battery, idle for")), batteryPopup, after()]) }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }

    func optionsView() -> NSView {
        var views: [NSView] = [loginBox]
        if LoginItem.status == .requiresApproval {
            let open = NSButton(title: L("打开登录项设置…", "Open Login Items…"), target: self, action: #selector(openLoginItems))
            open.controlSize = .small
            views.append(UI.stack([UI.paragraph(L("已添加，但需要在“系统设置 › 通用 › 登录项”中允许。", "Added. Allow it in System Settings › General › Login Items."), width: width - 140, size: 11), open],
                                  spacing: 8, vertical: false))
        }
        if hasLid { views.append(lidView()) }
        if hasBattery { views.append(lowBatteryBox) }
        return UI.stack(views, spacing: 8)
    }

    /// Returns an error message when the login item could not be changed.
    func save() -> String? {
        Preferences.timers = timers
        if hasBattery { Preferences.lowBatteryWarning = lowBatteryBox.state == .on }
        if hasLid {
            Preferences.displayOffOnLidClose = lidBox.state == .on
            Preferences.keepDarkOnLidClose = darkBox.state == .on
        }
        return LoginItem.set(loginBox.state == .on)
    }

    @objc private func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    private func fill(_ popup: NSPopUpButton, _ choices: [Int], selected: Int) {
        popup.removeAllItems()
        for value in Set(choices + [selected]).sorted() {
            popup.addItem(withTitle: Format.minutes(value))
            popup.lastItem?.tag = value
        }
        _ = popup.selectItem(withTag: selected)
    }
}

/// First-launch walkthrough: explains the two modes, then lets the user pick their own daily timers.
final class SetupAssistant: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 472
    private static let pageCount = 4
    var onFinish: ((_ applyNow: Bool) -> Void)?
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let form: PreferencesForm
    private let snapshot: PowerSnapshot?
    private let prefilled: Bool
    private let host = NSView()
    private let stepLabel = UI.label("", size: 11, color: .tertiaryLabelColor)
    private let backButton = NSButton(title: L("上一步", "Back"), target: nil, action: nil)
    private let nextButton = NSButton(title: L("继续", "Continue"), target: nil, action: nil)
    private let applyBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var applyOffered = false
    private var index = 0

    init(snapshot: PowerSnapshot?) {
        self.snapshot = snapshot
        let (timers, prefilled) = SetupAssistant.suggestedTimers(snapshot)
        self.prefilled = prefilled
        form = PreferencesForm(snapshot: snapshot, timers: timers, width: SetupAssistant.width)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 570),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = L("设置 PowerSwitcher", "Set Up PowerSwitcher")
        window.isReleasedWhenClosed = false
        window.delegate = self
        layout()
        show(page: 0)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    /// Prefer what this Mac already uses in daily mode, so setup does not silently change habits.
    private static func suggestedTimers(_ snapshot: PowerSnapshot?) -> (DailyTimers, Bool) {
        if Preferences.setupCompleted { return (Preferences.timers, false) }
        var timers = DailyTimers.defaults, prefilled = false
        if let s = snapshot, s.mode == .normal {
            if let ac = s.idleMinutes("AC Power") ?? s.idleMinutes("UPS Power"), (1...180).contains(ac) { timers.ac = ac; prefilled = true }
            if let battery = s.idleMinutes("Battery Power"), (1...180).contains(battery) { timers.battery = battery; prefilled = true }
        }
        return (timers, prefilled)
    }

    private func layout() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 570))
        backButton.target = self
        backButton.action = #selector(goBack)
        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.keyEquivalent = "\r"
        for view in [host, stepLabel, backButton, nextButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            host.bottomAnchor.constraint(lessThanOrEqualTo: nextButton.topAnchor, constant: -20),
            nextButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            nextButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            backButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            backButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            stepLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stepLabel.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
        ])
        window.contentView = content
    }

    private func show(page: Int) {
        index = page
        host.subviews.forEach { $0.removeFromSuperview() }
        let view = makePage(page)
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        stepLabel.stringValue = L("第 \(page + 1) 步，共 \(SetupAssistant.pageCount) 步", "Step \(page + 1) of \(SetupAssistant.pageCount)")
        backButton.isHidden = page == 0
        nextButton.title = page == SetupAssistant.pageCount - 1 ? L("完成", "Done") : L("继续", "Continue")
    }

    private func makePage(_ page: Int) -> NSView {
        let w = SetupAssistant.width
        func heading(_ text: String) -> NSTextField { UI.label(text, size: 20, weight: .bold) }
        switch page {
        case 0:
            return UI.stack([
                heading(L("欢迎使用 PowerSwitcher", "Welcome to PowerSwitcher")),
                UI.paragraph(L("在菜单栏一键切换两种电源状态：需要合上盖子继续跑 agent、构建或下载时切到任务模式，用完再恢复正常休眠。", "Switch power modes from the menu bar. Use Task mode for ongoing agents, builds or downloads, then return to Daily mode."), width: w),
                UI.row(PowerMode.task.symbols, tint: .systemOrange, title: PowerMode.task.title,
                       detail: L("禁止系统休眠（使用电池时也一样），用于合上盖子后继续运行，直到你切回日常模式。合盖后能否保持运行取决于机型和系统，第一次使用请先确认。", "Disables system sleep, including on battery, until you return to Daily mode. Lid behavior depends on your Mac and macOS; verify it before relying on it."), width: w),
                UI.row(PowerMode.normal.symbols, tint: .systemIndigo, title: PowerMode.normal.title,
                       detail: L("允许系统休眠：闲置到你设定的时间后自动休眠；合上盖子时按系统默认方式处理。", "Allows idle sleep after your chosen interval. Closing the lid follows the system's normal behavior."), width: w),
                UI.row(["info.circle"], tint: .secondaryLabelColor, title: L("“允许休眠”不等于“已经休眠”", "“Sleep allowed” does not mean “asleep”"),
                       detail: L("日常模式只是允许 Mac 休眠，后台应用仍可能阻止闲置休眠。菜单会列出这些进程，并显示 Mac 上次实际休眠的时间。", "Background apps may still prevent idle sleep. The menu lists those processes and shows the last sleep event recorded by PowerSwitcher."), width: w),
            ], spacing: 16)
        case 1:
            var views: [NSView] = [
                heading(L("日常模式的休眠时间", "Daily mode sleep timers")),
                UI.paragraph(L("切换到“\(PowerMode.normal.title)”后，Mac 闲置多久自动休眠。任务模式不使用这些时间。", "Choose how long your Mac can stay idle in “\(PowerMode.normal.title)”. Task mode does not use these timers."), width: w),
                form.timersView(),
            ]
            if prefilled { views.append(UI.paragraph(L("已按这台 Mac 当前的设置预填。", "Prefilled from this Mac's current settings."), width: w, size: 11, color: .tertiaryLabelColor)) }
            if snapshot?.profiles["UPS Power"] != nil {
                views.append(UI.paragraph(L("连接 UPS 时使用与接电相同的时间。", "UPS power uses the same timer as external power."), width: w, size: 11, color: .tertiaryLabelColor))
            }
            return UI.stack(views, spacing: 16)
        case 2:
            return UI.stack([
                heading(L("提醒与启动", "Reminders & Startup")),
                form.optionsView(),
                UI.row(["lock"], tint: .secondaryLabelColor, title: L("每次切换都需要管理员密码", "Switching requires an administrator password"),
                       detail: L("修改系统电源设置需要授权。PowerSwitcher 不保存密码，也不安装常驻的高权限服务。", "Power settings require authorization. PowerSwitcher never stores your password or installs a privileged background service."), width: w),
            ], spacing: 18)
        default:
            let timers = form.timers
            let summary = [
                L("• \(PowerMode.normal.title)：\(Format.timers(timers, hasBattery: form.hasBattery))。", "• \(PowerMode.normal.title): \(Format.timers(timers, hasBattery: form.hasBattery))."),
                L("• \(PowerMode.task.title)：禁止系统休眠（使用电池时也一样），用于合上盖子后继续运行。", "• \(PowerMode.task.title): disables system sleep, including on battery, for ongoing work."),
                L("• 以后可以在菜单栏图标 › 设置… 中修改。", "• Change these later in the menu bar › Settings…"),
            ].joined(separator: "\n")
            var views: [NSView] = [heading(L("准备就绪", "You're ready")), UI.paragraph(summary, width: w, color: .labelColor)]
            applyOffered = true
            switch snapshot?.mode {
            case .normal?:
                if let s = snapshot, s.matches(timers) {
                    applyOffered = false
                    views.append(UI.paragraph(L("当前已是日常模式，休眠时间与设定一致。", "Daily mode is already active and its timers match your settings."), width: w))
                } else {
                    applyBox.title = L("立即把以上休眠时间应用到当前的日常模式（需要管理员密码）", "Apply these timers now (administrator password required)")
                    applyBox.state = .on
                }
            case .task?:
                applyBox.title = L("现在切换到日常模式（需要管理员密码）", "Switch to Daily mode now (administrator password required)")
                applyBox.state = .off
                views.append(UI.paragraph(L("当前处于任务模式。如果有任务正在运行，可以稍后再从菜单切换。", "Task mode is active. If work is running, you can switch later from the menu."), width: w))
            case nil:
                applyBox.title = L("现在切换到日常模式（需要管理员密码）", "Switch to Daily mode now (administrator password required)")
                applyBox.state = .off
            }
            if applyOffered { views.append(applyBox) }
            return UI.stack(views, spacing: 16)
        }
    }

    @objc private func goBack() { if index > 0 { show(page: index - 1) } }

    @objc private func goNext() {
        guard index == SetupAssistant.pageCount - 1 else { show(page: index + 1); return }
        if let error = form.save() {
            UI.alert(L("无法更改登录项", "Couldn't update login item"), error + L("\n\n可以稍后在“系统设置 › 通用 › 登录项”中手动添加。", "\n\nYou can add it later in System Settings › General › Login Items."), style: .warning)
        }
        Preferences.setupCompleted = true
        let apply = applyOffered && applyBox.state == .on, finish = onFinish
        window.close()
        finish?(apply)
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    private let window: NSWindow
    private let form: PreferencesForm

    init(snapshot: PowerSnapshot?) {
        form = PreferencesForm(snapshot: snapshot, timers: Preferences.timers, width: 400)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: 320),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = L("PowerSwitcher 设置", "PowerSwitcher Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self

        let body = UI.stack([
            UI.label(PowerMode.normal.title, weight: .semibold),
            UI.paragraph(L("Mac 闲置多久后自动休眠。任务模式不受影响。", "Choose idle sleep timers. Task mode is unaffected."), width: 400, size: 12),
            form.timersView(),
            UI.label(L("提醒与启动", "Reminders & Startup"), weight: .semibold),
            form.optionsView(),
        ], spacing: 10)
        let resetButton = NSButton(title: L("恢复默认时间", "Reset Timers"), target: self, action: #selector(resetTimers))
        let cancelButton = NSButton(title: L("取消", "Cancel"), target: self, action: #selector(cancelClicked))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: L("保存", "Save"), target: self, action: #selector(saveClicked))
        saveButton.keyEquivalent = "\r"

        let content = NSView()
        for view in [body, resetButton, cancelButton, saveButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 448),
            body.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            saveButton.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 24),
            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            resetButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            resetButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
        // Size from the constraints before handing the view to the window.
        let size = content.fittingSize
        content.setFrameSize(size)
        window.setContentSize(size)
        window.contentView = content
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    @objc private func resetTimers() { form.select(.defaults) }

    @objc private func cancelClicked() { window.close() }

    @objc private func saveClicked() {
        if let error = form.save() {
            UI.alert(L("无法更改登录项", "Couldn't update login item"), error + L("\n\n可以稍后在“系统设置 › 通用 › 登录项”中手动添加。", "\n\nYou can add it later in System Settings › General › Login Items."), style: .warning)
        }
        let saved = onSave
        window.close()
        saved?()
    }
}
