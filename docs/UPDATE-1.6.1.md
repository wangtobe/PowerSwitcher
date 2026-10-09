# PowerSwitcher 1.6.1

**v1.6.1** · [中文](#中文) / [English](#english)

## 中文

这次更新加了定时切换：任务模式可以定时结束，也可以每天固定时间自动切换。

[下载 PowerSwitcher 1.6.1 ↓](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.1/PowerSwitcher-1.6.1-universal-installer.zip) · [下载源码](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.1/PowerSwitcher-1.6.1-source.zip)

### 任务模式，定时结束

菜单里多了「任务模式，定时结束」，可以选 1、2、4、8 小时后、到早上 08:00，或者点「自定义时间…」输入任意日期和时间，精确到分钟，最远 7 天以内。到点后 Mac 会自动切回日常模式。

- 在日常模式下选：先切到任务模式，再定好结束时间，只输一次密码。
- 在任务模式下选：只定结束时间；想改时间就重新选一个。
- 菜单顶部会显示「将于 xx:xx 自动切回日常模式」，子菜单里可以取消。
- 手动切回日常模式时，定时自动取消。

适合 agent 半夜跑完、你还在睡的情况：到点 Mac 自己恢复正常休眠，不会一直醒到天亮。

### 每天定时切换

在「设置…」底部的「每天定时切换」里，可以设：

- 每天几点进入任务模式（默认 23:00）
- 每天几点切回日常模式（默认 08:00）

两项可以只开一项，比如只开「每天 08:00 切回日常模式」，当作忘了切回来时的保底。

### 怎么做到不用输密码的

设置定时的时候需要输一次管理员密码，PowerSwitcher 会在系统里登记定时任务，也就是 `/Library/LaunchDaemons` 里以 `org.powerswitcher.schedule` 开头的文件。到点时由系统执行，所以不用再输密码。

- 用的是和手动切换同一套流程：先设置，再核对，失败就回退。
- 定时任务只在到点时运行一下，执行完就退出，不常驻。执行记录在 `/Library/Logs/PowerSwitcher-schedule.log`。
- 任务模式的定时结束执行一次后会自己删除。
- Mac 在睡眠时错过的定时，会在唤醒后执行；任务模式的定时结束如果遇上关机，开机后也会补上。
- macOS 可能会弹出「已添加后台项目」的通知，属于正常现象。如果在「系统设置 → 通用 → 登录项」里把它关掉，定时就不会执行。

### 删除应用前先关掉定时

定时任务登记在系统里，删掉应用后它们还会按时运行。删除前请先在「设置…」里关掉每天定时，并在菜单里取消任务模式的定时结束。如果已经删了应用，可以在终端运行：

```sh
for j in task-end daily-task daily-normal; do sudo launchctl bootout system/org.powerswitcher.schedule.$j; sudo rm -f /Library/LaunchDaemons/org.powerswitcher.schedule.$j.plist; done
```

### 怎么升级

1. 从菜单退出旧版 PowerSwitcher。任务模式不会因此取消。
2. 下载并解压 `PowerSwitcher-1.6.1-universal-installer.zip`。
3. 把新的 `PowerSwitcher.app` 拖进「应用程序」，替换旧版，然后打开。

设置会保留。

### 要知道的

- 定时切换目前做过模拟测试和 launchd 加载检查，真机上等到点的完整测试还在进行中，欢迎反馈。
- 电源切换、管理员授权、切换后核对和失败回退的逻辑都没有改动。

## English

This update adds scheduled switches: a timer that ends Task mode, and a daily schedule.

[Download PowerSwitcher 1.6.1 ↓](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.1/PowerSwitcher-1.6.1-universal-installer.zip) · [Download source](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.6.1/PowerSwitcher-1.6.1-source.zip)

### Task Mode for…

The menu has a new "Task Mode for…" item: pick 1, 2, 4 or 8 hours, until 08:00, or choose "Custom Time…" to enter any date and time to the minute, up to 7 days ahead. Your Mac returns to Daily mode on its own.

- From Daily mode: switches to Task mode and sets the end time, with a single password prompt.
- From Task mode: just sets the end time. Pick another one to change it.
- The top of the menu shows "Returns to Daily mode at …", and the submenu lets you cancel.
- Switching back to Daily mode by hand cancels the timer.

Handy when an agent finishes in the middle of the night: your Mac goes back to normal sleep instead of staying awake until morning.

### Daily schedule

In Settings, under "Daily Schedule", you can choose:

- a time to enter Task mode every day (23:00 by default)
- a time to return to Daily mode every day (08:00 by default)

You can turn on just one, for example only "every day at 08:00, switch to Daily mode" as a safety net.

### Why no password is needed when it fires

Setting a schedule asks for your administrator password once. PowerSwitcher then registers system jobs: files starting with `org.powerswitcher.schedule` in `/Library/LaunchDaemons`. macOS runs them at the scheduled time, so no password is needed then.

- They use the same steps as manual switches: apply, verify, and roll back on failure.
- The jobs only run briefly at the scheduled time and then exit; nothing stays running. They log to `/Library/Logs/PowerSwitcher-schedule.log`.
- The Task mode timer removes itself after it runs.
- A time missed while your Mac sleeps runs when it wakes, and a Task mode timer missed while it's shut down runs after the next startup.
- macOS may show a "Background Items Added" notification; that's expected. If you turn the item off in System Settings → General → Login Items, schedules won't run.

### Turn off schedules before deleting the app

Scheduled jobs live in the system and keep running after the app is deleted. Before deleting it, turn off the daily schedule in Settings and cancel any Task mode timer from the menu. If the app is already gone, run:

```sh
for j in task-end daily-task daily-normal; do sudo launchctl bootout system/org.powerswitcher.schedule.$j; sudo rm -f /Library/LaunchDaemons/org.powerswitcher.schedule.$j.plist; done
```

### How to update

1. Quit the old PowerSwitcher from its menu. Task mode stays on.
2. Download and unzip `PowerSwitcher-1.6.1-universal-installer.zip`.
3. Drag the new `PowerSwitcher.app` into Applications to replace the old one, then open it.

Your settings are kept.

### Good to know

- Scheduled switches have been checked with mock tests and a launchd load test; hands-on testing at real scheduled times is ongoing. Reports are welcome.
- Power switching, administrator authorization, post-switch checks and rollback are unchanged.
