# Changelog

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
