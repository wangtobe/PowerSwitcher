# Changelog

## 1.6.2 — 2026-10-10

- A restart clears macOS's global SleepDisabled flag but keeps Task mode's idle timers (power adapter "never", battery 1 min), leaving the Mac half in Task mode. The app now recognizes this (sleep allowed while an AC/UPS profile is at 0, which Daily mode never sets, after Task mode was last seen), shows a notice once per launch, a warning icon and status card, and offers "Restore Task Mode…" and "Switch to Daily Mode…".
- New opt-in "Keep the same mode after a restart" under Scheduled Switches in Settings. It registers `org.powerswitcher.schedule.boot-restore`, a launchd job that runs at load, waits for powerd, acts only within 15 minutes of startup and only in that interrupted state, and re-applies Task mode through the regular switching script.
- Uninstall command and docs cover the new job. Self-tests 25 (restart detection, boot-restore plist). Power switching, authorization, verification and rollback logic are unchanged.

## 1.6.1 — 2026-10-09

First public release of scheduled switches; 1.6.0 was an unreleased test build without the custom time option.

- Scheduled switches. "Task Mode for…" in the menu ends Task mode after 1, 2, 4 or 8 hours, at 08:00, or at a custom date and time to the minute (up to 7 days ahead), entering Task mode first when needed; a daily schedule in Settings enters Task mode and/or returns to Daily mode at chosen times.
- Schedules run unattended as launchd jobs in /Library/LaunchDaemons (`org.powerswitcher.schedule.*`), registered with one administrator prompt. Each plist carries the regular switching script inline (root-owned, nothing user-writable is executed), so scheduled switches use the same apply, verify and rollback steps. Jobs log to /Library/Logs/PowerSwitcher-schedule.log.
- The one-shot end of Task mode also runs at load so it catches up after a shutdown, checks its end time and its own plist before acting, and removes itself afterwards. The daily return to Daily mode and manual switches to Daily mode clear a pending end.
- If the one-shot end is registered less than a minute before its time (or launchd fires slightly early), the job waits for the exact time instead of ending Task mode early.
- Daily timers are baked into the jobs and re-registered when they change. A switch combined with a schedule change uses a single prompt; schedule registration only happens after the switch succeeds.
- Docs: privacy wording now says schedules register system jobs only when set; uninstall steps for schedules; `disablesleep 0` recovery wording corrected.
- Daily mode lowers `displaysleep` to the idle timer when it is longer or 0 (never): powerd keeps the Mac awake while the display is on, so the daily timer had no effect. Shorter values are left alone, Task mode never touches it, and it is verified and rolled back with the other settings. The app treats a longer display timer as not matching the preset, so "Apply configured sleep timers…" appears.
- Registered jobs carry a revision of the switching script. Jobs registered by another build are flagged in the status card and the timer submenu ("Update Scheduled Switches…"), and refreshed under the same prompt as the next switch or settings change.
- Scheduled job logs drop pmset's display-vs-sleep timer warnings; other output, including rollback diagnostics, is kept.
- Six new self-tests (24 total) and three new mock tests (15 total). Authorization, verification and rollback logic are unchanged.

## 1.5.1 — 2026-10-09

- Fix: in Task mode the screen could stay lit with the lid closed. Display sleep was requested once per closing, and remote-control tools (seen with UU Remote) woke the display again within a second.
- New option, on by default: "Keep the screen dark while the lid is closed". Holds the built-in brightness at 0 while the lid stays shut and restores it when the lid opens, so remote viewing keeps working with a dark panel. Uses the private DisplayServices framework; disabled automatically when unavailable.
- The saved brightness is persisted and restored on the next launch if the app quits with the panel dimmed.
- Lid polling interval 2 s → 1 s. Power switching, authorization, verification and rollback logic are unchanged.

## 1.5.0 — 2026-10-04

- Add Chinese/English UI with automatic system-language selection and a manual override (applies on next launch).
- Add native About credits: Tobe Wang, GPT, Claude, in that order.
- Increase setup window height for translated copy and localize date/time formatting.
- Add language-selection self-tests. Power switching, authorization, verification and rollback logic are unchanged.

## 1.4.0 — 2026-09-30

- First-launch setup assistant: explains both modes and lets users choose daily-mode AC / battery idle timers (prefilled from the Mac's current settings), login item and low-battery reminder. Re-run from the menu; edit later in Settings.
- `power.sh` accepts `daily_ac` / `daily_battery` (1–180 minutes, validated before any change; defaults 15 / 5). Task mode, verification and rollback are unchanged.
- Menu redesign: status card (mode, live idle timers, power source), sleep-blocking processes submenu, last actual sleep time, “更多” submenu for rarely used items.
- Switch feedback: transient popover instead of modal success alerts; alerts remain for failures, low battery in task mode, and sleep that did not happen.
- “立即休眠” verifies the Mac actually went to sleep; in task mode it becomes “切回日常模式并立即休眠”.
- Clear separation of “允许休眠” (allowed) vs “已经休眠” (actually slept) in icons and wording; unified SF Symbols with fallbacks.
- Confirmation before quitting in task mode; admin prompt names the target mode.
- Sources split into several files; power state is read off the main thread.
- Task mode: closing the lid turns the display off (`pmset displaysleepnow`, display only, once per close, skipped with an external display). With sleep disabled the lid no longer triggers the sleep path that normally darkens the panel. Optional in Settings; `power.sh` unchanged.
- Wording: lid-close behaviour is described as the intended use (confirm on first use), not a guarantee; switching status no longer claims settings are untouched; idle-timer summaries use one clause per power source.

## 1.3.0 — 2026-09-30

- First source release with a reproducible Universal 2 build targeting macOS 13+.
- Detect available power profiles; skip absent battery/UPS and optional TTY setting.
- Interpret absent global SleepDisabled key as the default enabled-sleep state.
- Validate live configuration and attempt rollback on failed updates.
- Embed switching scripts so application relocation does not break mode changes.
- Add mocked tests, CI, original icon, and MIT license.
- Remove private machine snapshots, usernames, local paths, and machine identifiers.
- Developer ID signing, notarization and physical Intel validation remain outstanding.
