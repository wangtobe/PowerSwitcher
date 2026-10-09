# PowerSwitcher 1.5.1

**v1.5.1** · [中文](#中文) / [English](#english)

## 中文

这次更新修了一个问题：任务模式下合上盖子，屏幕还亮着。

[下载 PowerSwitcher 1.5.1 ↓](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.5.1/PowerSwitcher-1.5.1-universal-installer.zip) · [下载源码](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.5.1/PowerSwitcher-1.5.1-source.zip)

### 修了什么

以前合盖时，PowerSwitcher 只关一次屏幕。如果装了 UU 远程这类远程控制软件，它们会在屏幕熄灭后一秒内把屏幕重新点亮，于是盖子合着、屏幕却一直亮着。

### 新增选项：合盖期间保持黑屏

在「设置…」里，「任务模式下，合上盖子时关闭屏幕」下面多了一个选项「合盖期间保持黑屏」，默认开启：

- 合盖期间，内屏亮度保持在 0。就算屏幕被其他软件点亮，也不会发光。
- 屏幕在系统里仍然算开着，所以远程控制过来，画面照常。
- 开盖后恢复原来的亮度。退出应用、切回日常模式时也会恢复。
- 接着外接显示器合盖时，内屏本来就不用，这时不会调亮度。
- 不需要的话，取消勾选就行。

### 怎么升级

1. 从菜单退出旧版 PowerSwitcher。任务模式不会因此取消。
2. 下载并解压 `PowerSwitcher-1.5.1-universal-installer.zip`。
3. 把新的 `PowerSwitcher.app` 拖进「应用程序」，替换旧版，然后打开。

设置会保留。第一次打开如果提示「无法验证开发者」，去「系统设置 → 隐私与安全性」点「仍要打开」。

### 要知道的

- 「保持黑屏」用的是 macOS 未公开的亮度接口，以后的系统更新可能让它失效。失效时这个选项会自动隐藏，合盖照旧只关一次屏幕。
- 万一 PowerSwitcher 在合盖期间意外退出，开盖后屏幕可能是黑的。按键盘上的亮度键就能调回来，下次打开 PowerSwitcher 也会自动恢复。
- 目前只在一台 M1 Pro MacBook（macOS 15）上实测过。其他机型欢迎反馈。
- 电源切换、管理员授权、切换后核对和失败回退的逻辑都没有改动。

## English

This update fixes an issue where the screen stayed on with the lid closed in Task mode.

[Download PowerSwitcher 1.5.1 ↓](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.5.1/PowerSwitcher-1.5.1-universal-installer.zip) · [Download source](https://github.com/wangtobe/PowerSwitcher/releases/download/v1.5.1/PowerSwitcher-1.5.1-source.zip)

### What was wrong

PowerSwitcher used to turn the display off once when the lid closed. Remote-control apps such as UU Remote wake the display again within a second of it turning off, so the screen kept glowing with the lid shut.

### New option: Keep the screen dark while the lid is closed

In Settings, under "Turn off the display when closing the lid in Task mode", there's a new option, on by default:

- While the lid is closed, the built-in brightness stays at 0, so the panel stays dark even if another app wakes the display.
- The display still counts as on, so remote viewing works as usual.
- Brightness comes back when you open the lid, quit the app or switch to Daily mode.
- With an external display in clamshell mode, the built-in screen isn't in use, so brightness is left alone.
- Untick it if you don't want it.

### How to update

1. Quit the old PowerSwitcher from its menu. Task mode stays on.
2. Download and unzip `PowerSwitcher-1.5.1-universal-installer.zip`.
3. Drag the new `PowerSwitcher.app` into Applications to replace the old one, then open it.

Your settings are kept. If macOS says it can't verify the developer, go to System Settings → Privacy & Security and click Open Anyway.

### Good to know

- Keeping the screen dark relies on a private macOS brightness API, which a future macOS update could break. If it's unavailable, the option hides itself and the lid falls back to a one-time display-off.
- If PowerSwitcher quits unexpectedly while the lid is closed, the screen may be dark when you open it. Press the brightness keys to bring it back; PowerSwitcher also restores it the next time it opens.
- Tested hands-on on one M1 Pro MacBook running macOS 15 so far. Reports from other Macs are welcome.
- Power switching, administrator authorization, post-switch checks and rollback are unchanged.
