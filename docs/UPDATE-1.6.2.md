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
- **可选自动恢复：** 在「设置…」的「定时切换」里，新增「重启后自动恢复任务模式」。开启后，如果重启前在任务模式，开机后会自动恢复，不用输密码。
  - 默认关闭。开启时需要输一次管理员密码，原理和定时切换一样，会登记一个系统任务（`org.powerswitcher.schedule.boot-restore`）。
  - 它只在开机后 15 分钟内动作，而且只在确认任务模式确实被重启取消时才恢复。之后再开启这个选项，不会立刻切到任务模式。
  - 执行记录同样写在 `/Library/Logs/PowerSwitcher-schedule.log`。

### 怎么升级

1. 从菜单退出旧版 PowerSwitcher。
2. 下载并解压 `PowerSwitcher-1.6.2-universal-installer.zip`。
3. 把新的 `PowerSwitcher.app` 拖进「应用程序」，替换旧版，然后打开。

设置和已登记的定时都会保留。

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
- **Optional automatic restore:** under "Scheduled Switches" in Settings, there's a new "Restore Task mode after a restart" option. With it on, if Task mode was on before a restart, it comes back after startup with no password.
  - It's off by default. Turning it on asks for your administrator password once and registers a system job (`org.powerswitcher.schedule.boot-restore`), the same way scheduled switches work.
  - It only acts within 15 minutes of startup, and only when it can tell that a restart cleared Task mode. Turning the option on later never switches to Task mode on the spot.
  - It logs to `/Library/Logs/PowerSwitcher-schedule.log` like the other jobs.

### How to update

1. Quit the old PowerSwitcher from its menu.
2. Download and unzip `PowerSwitcher-1.6.2-universal-installer.zip`.
3. Drag the new `PowerSwitcher.app` into Applications to replace the old one, then open it.

Your settings and registered schedules are kept.

### Good to know

- If you've already deleted the app, the cleanup command needs `boot-restore` as well; see "Turn off schedules before deleting the app" in the README.
- Power switching, administrator authorization, post-switch checks and rollback are unchanged.
