# PowerSwitcher 1.6.2

**v1.6.2** · [中文](#中文) / [English](#english)

## 中文

这次更新处理一个问题：重启之后，任务模式会被系统取消。

[下载 PowerSwitcher 1.6.2 ↓](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.2/PowerSwitcher-1.6.2-universal-installer.zip) · [下载源码](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.2/PowerSwitcher-1.6.2-source.zip)

### 问题是什么

任务模式靠的是系统的「全局禁止休眠」开关。重启后，macOS 会把这个开关关掉，但休眠时间还停留在任务模式的设置：接电源永不休眠，电池 1 分钟。结果 Mac 处在一种半任务模式的状态：

- 插着电时不会闲置休眠，但合盖会睡；
- 用电池时 1 分钟就会睡。

以前 PowerSwitcher 只会显示「日常模式」，并提示休眠时间和设定不一致，没说清楚发生了什么。

### 现在怎么处理

- **自动识别：** PowerSwitcher 打开后，如果发现任务模式被重启取消了，会弹出提示，菜单栏图标变成警告标志，菜单里出现「恢复任务模式…」和「切回日常模式…」，点哪个都需要输一次密码。
- **可选自动恢复：** 在「设置…」的「定时切换」里，新增「重启后恢复重启前的模式」。开启后，重启前在任务模式，开机后会自动恢复，不用输密码；重启前在日常模式，就保持日常模式（日常模式本来就不受重启影响）。
  - 默认关闭。开启时需要输一次管理员密码，原理和定时切换一样，会登记一个系统任务（`org.powerswitcher.schedule.boot-restore`）。
  - 它只在开机后 15 分钟内动作，而且只在确认任务模式确实被重启取消时才恢复。之后再开启这个选项，不会立刻切到任务模式。
  - 执行记录同样写在 `/Library/Logs/PowerSwitcher-schedule.log`。

### 怎么升级

1. 从菜单退出旧版 PowerSwitcher。
2. 下载并解压 `PowerSwitcher-1.6.2-universal-installer.zip`。
3. 把新的 `PowerSwitcher.app` 拖进「应用程序」，替换旧版，然后打开。

设置和已登记的定时都会保留。

### 每天定时改成按时间段生效

以前「每天定时」只在两个时间点各切一次。比如下午 14:00 设好「9:00 进入任务模式、21:00 切回日常模式」，要等到 21:00 才会第一次动作，9 到 21 点这段反而不是任务模式。睡眠或关机跨过了切换时间，也可能停在错误的模式。

现在两项都开时，两个时间之间就是任务模式，其余时间是日常模式：

- **保存设置时**：如果当前时间落在另一种模式的时间段，会在同一次密码授权里直接切过去，并提示「已按每天定时切到…」。
- **唤醒后**：错过的定时补跑时，先看当前时间属于哪一段，所以不管补跑顺序如何，都会停在正确的模式。
- **开机后**：按当前时间段切到对应模式。这条优先于「重启后恢复重启前的模式」。
- 时间段可以跨午夜，比如 23:00 进入任务模式、08:00 切回日常模式。
- 只开其中一项时，行为和以前一样，到点切换一次。

升级后，菜单会提示定时任务是旧版本登记的，点「更新定时任务…」输一次密码就行。

### 要知道的

- 如果你已经删掉应用，清理定时任务的命令里要多加一个 `boot-restore`，见 README 的「删除应用前先关掉定时」。
- 电源切换、管理员授权、切换后核对和失败回退的逻辑都没有改动。

## English

This update deals with Task mode being turned off by a restart.

[Download PowerSwitcher 1.6.2 ↓](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.2/PowerSwitcher-1.6.2-universal-installer.zip) · [Download source](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.2/PowerSwitcher-1.6.2-source.zip)

### What was wrong

Task mode relies on the system-wide sleep override. A restart makes macOS turn that override off, but the sleep timers stay at Task mode's values: never on power, 1 minute on battery. That leaves your Mac half in Task mode:

- plugged in, it won't idle sleep, but closing the lid puts it to sleep;
- on battery, it sleeps after 1 minute.

PowerSwitcher used to just show Daily mode with timers that didn't match your settings, without explaining what happened.

### What happens now

- **Detection:** when PowerSwitcher opens and finds that a restart cleared Task mode, it shows a notice, the menu bar icon turns into a warning sign, and the menu offers "Restore Task Mode…" and "Switch to Daily Mode…". Either one asks for your password once.
- **Optional automatic restore:** under "Scheduled Switches" in Settings, there's a new "Keep the same mode after a restart" option. With it on, if Task mode was on before a restart, it comes back after startup with no password; if Daily mode was on, it stays that way (Daily mode isn't affected by a restart).
  - It's off by default. Turning it on asks for your administrator password once and registers a system job (`org.powerswitcher.schedule.boot-restore`), the same way scheduled switches work.
  - It only acts within 15 minutes of startup, and only when it can tell that a restart cleared Task mode. Turning the option on later never switches to Task mode on the spot.
  - It logs to `/Library/Logs/PowerSwitcher-schedule.log` like the other jobs.

### How to update

1. Quit the old PowerSwitcher from its menu.
2. Download and unzip `PowerSwitcher-1.6.2-universal-installer.zip`.
3. Drag the new `PowerSwitcher.app` into Applications to replace the old one, then open it.

Your settings and registered schedules are kept.

### Daily schedules now work as a window

A daily schedule used to switch only at its two times. Set "Task mode at 09:00, Daily mode at 21:00" at 14:00, and nothing happened until 21:00, so 09:00–21:00 wasn't Task mode that day. Sleeping or shutting down across a switch time could also leave the wrong mode.

With both times on, Task mode now runs between them and Daily mode the rest of the day:

- **When you save**: if the current time belongs to the other mode, PowerSwitcher switches under the same password prompt and says "Switched by the daily schedule to …".
- **After waking**: late fires check which window the current time is in, so they end in the right mode whatever order they run in.
- **After startup**: the Mac switches to the mode for the current time. This takes priority over "Keep the same mode after a restart".
- Windows can wrap past midnight, e.g. Task mode at 23:00, Daily mode at 08:00.
- With only one of the two times on, it switches once at that time, as before.

After updating, the menu says scheduled switches were set up by an older version; choose "Update Scheduled Switches…" and enter your password once.

### Good to know

- If you've already deleted the app, the cleanup command needs `boot-restore` as well; see "Turn off schedules before deleting the app" in the README.
- Power switching, administrator authorization, post-switch checks and rollback are unchanged.
