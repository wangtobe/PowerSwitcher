# Validation — 1.6.2 (2026-10-10)

## What happened on the reporting Mac (read-only)

- 2026-10-10 08:00:04: daily Task job ran, exit 0. The 20:30 daily Daily job had been registered at 21:37 the evening before, after its time, so it had not run yet.
- The user restarted manually at 10:04 (a shutdown-stall report, no panic). Afterwards `SleepDisabled` was 0 while AC sleep stayed 0 and battery sleep 1: Task mode had been cleared by the restart.

## Results

- Mock tests 15/15. Universal build without errors or warnings. Self-tests **25/25** native and under Rosetta, including restart detection and the boot-restore plist (no calendar, RunAtLoad, Task script).
- Schedule sandbox **17/17**, with `sysctl` mocked for the boot time: boot-restore restores Task mode when a restart cleared it; leaves Daily timers, an hour-old boot, and an active Task mode alone. The sandbox caught a greedy `sed` that read `usec` instead of `sec` from `kern.boottime` (it would never have restored); fixed and checked against the real `sysctl` output.
- Registering Task mode plus boot-restore through `osascript … do shell script` in the sandbox: exit 0, plists pass `plutil -lint`, and after a simulated restart the job restored Task mode.
- Settings rendered offscreen in Chinese and English; it read the user's real registered schedule (08:00 / 20:30).

## Daily window (build 15)

- Reported by the user: setting 09:00–21:00 at 14:00 left Daily mode until 21:00.
- Self-tests **27/27** (window inside/outside, past midnight; startup job registered for a window without the restore option).
- Schedule sandbox **27/27** with `date` mocked: Task job acts only inside the window, Daily job only outside; both late fires at 10:00 or 23:30 end in the right mode in either order; startup at 14:00 → Task, at 22:00 with Task timers left → Daily, at 22:00 already Daily → nothing.
- Through `osascript … do shell script` in the sandbox: registering a 09:00–21:00 window with Task mode, then startup at 22:00 → Daily (10 min timers), Daily job at 22:00 and Task job at 14:00 behave as above; plists pass `plutil -lint`.

## Not performed

- No real restart with the option on, no administrator prompt, no job registered on the real system by the assistant.

---

# Validation — 1.6.1 (2026-10-09)

1.6.1 = the 1.6.0 test build plus the "Custom Time…" picker. Results below were rerun on 1.6.1 unless noted.

## Build results

- Host: Apple M1 Pro, macOS 15.7.4, SDK 15.5.
- Python mock tests: **12/12 PASS**.
- Universal build: **PASS**, no compiler errors or warnings; `lipo -archs`: `x86_64 arm64`; strict ad-hoc signature verification passes.
- Build-time self-test and extracted x86_64 self-test under Rosetta: **23/23 PASS**. New checks: minute-aligned timer end, next 08:00, job plists parse and round-trip with `sh -n`, unused job omitted, sync script.

## Schedule scripts in a sandbox (assistant, no root)

The generated sync script and job scripts were run with `/Library` paths redirected to a temporary directory and `launchctl`, `chown` and `pmset` replaced by mocks (the pmset mock from `Tests/test_power.py`). 14/14 checks passed:

- sync installs three plists (mode 644), bootstraps three jobs, creates the log; an empty plan removes all jobs;
- the one-shot end does nothing before its time or without its plist; after its time it switches to Daily mode with the baked-in 20/4 min timers, removes its plist and boots itself out;
- the daily Task job switches to Task mode; the daily Daily job switches to Daily mode and clears a pending end;
- a failing pmset call inside a job rolls back and exits non-zero.
- an end registered less than a minute ahead waits until the end time, then switches (added after the user's hands-on test, see below).

## Hands-on check by the user (build 13)

- App 1.6.1 (13) installed; the stale daily jobs were re-registered at 21:21:45 with the current revision.
- Daily schedule set to 21:24 Task / 21:27 Daily. Log: `21:24:05 daily-task … exit 0`, `21:27:02 daily-normal … exit 0`, fired by the calendar a few seconds after the minute, not at registration. No pmset warnings in these entries.
- After the Daily switch: SleepDisabled 0; Battery displaysleep lowered 3 → 1 to match sleep 1; AC displaysleep 2 left alone (already below sleep 10).
- No idle sleep followed before the user returned (AC timer 10 min; Claude and backupd-helper held sleep assertions), so a real sleep after a scheduled switch was confirmed only for build 10 (20:42:16, see below).

## Stale job detection (build 13)

- On the reporting Mac, the installed app was still build 10 and its two daily jobs (registered 21:15) carried build 10's script. `Schedule.installed()` run read-only against /Library/LaunchDaemons reports them stale; freshly generated jobs are not. Self-test now also checks that every generated job carries the current revision. Mock tests 15/15, self-tests 24/24, sandbox 14/14.
- Log read at 21:19: the 21:08:08 Task mode end exited 0 and SleepDisabled is 0 (Daily mode). Display timers were not aligned because build 12+ had not been installed.

## Display timer alignment (build 12)

- Reported Mac: Battery displaysleep 0 / sleep 1, AC displaysleep 10 / sleep 5. pmset warned on every Daily switch, and powerd's "Prevent sleep while display is on" assertion means idle sleep waits for the display.
- power.sh now lowers displaysleep to the idle timer in Daily mode when it is longer or 0. Mock tests added: lowers 10→5 and 0→4, keeps a shorter 3; Task mode keeps 30 and 0; a failure restores displaysleep. **15/15 PASS**.
- Self-tests: **24/24 PASS** (native and Rosetta), including a longer display timer counting as not matching the preset.
- Schedule sandbox: **14/14 PASS**. A first attempt captured job output with `$( … )`, which broke on power.sh's `case` patterns; the self-test and sandbox caught it before delivery, and output now goes through a temp file. With a pmset mock that prints the display warnings, the job log keeps only the start and exit lines.
- Not done by the assistant: a real Daily switch on the reported Mac.

## Hands-on check by the user (1.6.1 build 10)

- Three Task mode timers set with "Custom Time…" each switched back to Daily mode (schedule log: exit 0 at 20:33:33, 20:36:17, 20:41:04). Their non-zero seconds suggest they ran at registration rather than on the calendar trigger: either the end had already passed while the password was typed (expected catch-up) or it was less than 60 s away, which the old 60 s tolerance ran immediately. Build 11 waits for the exact time instead.
- After the 20:41:04 switch the Mac actually slept: `pmset -g log` shows "Entering Sleep state due to 'Idle Sleep'" on battery at 20:42:16 for 186 s, woken by opening the lid at 20:45:22.
- Daily schedule jobs were registered at 20:39 (both plists present, root:wheel 644).

The combined "switch to Task mode + register schedule" script also ran through `osascript -e 'do shell script …'` (without administrator privileges, sandboxed) to check AppleScript quoting: exit 0, Task mode set, three plists written, all pass `plutil -lint`.

## launchd acceptance (assistant)

A copy of the generated one-shot plist, with its label renamed and its program replaced by `echo`, was loaded into the user's `gui/501` domain: launchd registered the calendar trigger (Month/Day/Hour/Minute), ran it once at load, passed the environment variables, then it was booted out. Nothing was loaded into the system domain.

## Not performed

- No administrator authorization, no jobs registered in `/Library/LaunchDaemons`, no real scheduled switch, wake/boot catch-up, Background Items notification or Login Items toggle. These need a hands-on test by the user.
- Settings window rendered offscreen (Chinese and English); the menu itself was not exercised.

---

# Validation — 1.5.1 (2026-10-09)

## Diagnosis on the reporting machine (read-only)

- Apple M1 Pro (MacBookPro18,3), macOS 15.7.4, PowerSwitcher 1.5.0 in Task mode, built-in display only.
- `pmset -g log` during the user's lid test: display turned off about 2 s after the lid event (consistent with the 2 s lid poll), then `UURemoteServer` created `UserIsActive "Wake Up Display"` assertions and the display turned on again within 0–1 s of each later display-off. AweSun also held a display-sleep assertion.
- `DisplayServicesGetBrightness` on the built-in display returned a value; no brightness was changed during diagnosis.

## Build results

- Python mock tests: **12/12 PASS**.
- Universal build: **PASS**, no compiler errors or warnings; `lipo -archs`: `x86_64 arm64`; strict ad-hoc signature verification passes.
- Build-time self-test and extracted x86_64 self-test under Rosetta: **18/18 PASS**; both report `Backlight API: available`.
- Settings window rendered offscreen in Chinese and English to check layout of the new option.

## Hands-on check by the user

- On the reporting M1 Pro / macOS 15.7.4 machine, the user installed the 1.5.1 build, closed the lid in Task mode and reported the screen-stays-lit problem resolved. Individual observations (light leak, UU Remote viewing, restore on open) were not itemized in the report.

## Not performed

- No lid close, brightness change, mode switch or administrator authorization by the assistant.
- External-display clamshell mode, crash-recovery restore, other Mac models and other macOS versions were not tested.

---

## 1.5.0 publication rebuild — 2026-10-09

- About credits and README now list Tobe Wang, GPT, Claude without author-rank labels. The spelling correction to Claude was rebuilt and the checks below rerun.
- Rebuilt Universal 2 successfully on macOS 15.7.4 / SDK 15.5. Build-time self-test: 18/18 PASS.
- Extracted archive: arm64 and x86_64 self-tests each 18/18 PASS; x86_64 runs under Rosetta. `lipo -archs`: x86_64 arm64. Strict ad-hoc signature verification passes.
- No power logic changes, real mode switches, administrator authorization or UI/lid behavior tests performed in this rebuild.

# Validation — 1.5.0 (2026-10-04)

## Changes and results

- Added `Localization.swift`: system preferred language selects Chinese for `zh` variants and English otherwise; manual `zh` / `en` overrides apply on next launch.
- Translated menus, setup/settings, feedback, date/time formatting and authorization prompt. Added native About credits in the requested order: Tobe Wang, GPT, Claude.
- Host: Apple M1 Pro, macOS 15.7.4, macOS SDK 15.5, Python 3.9.
- Python mock tests: **12/12 PASS** (5.159 seconds).
- Universal build: **PASS**, targets arm64 and x86_64, minimum macOS 13.0. `lipo -archs` on the extracted app: `x86_64 arm64`.
- Compilation fix: `.copyright` is not an `NSApplication.AboutPanelOptionKey`; copyright is now supplied through `NSHumanReadableCopyright` in Info.plist. Final build has no compiler errors or warnings.
- Build-time self-test: **18/18 PASS**.
- Freshly extracted app, native arm64: **18/18 PASS** with English and **18/18 PASS** with Chinese.
- Freshly extracted app, `arch -x86_64` under Rosetta: **18/18 PASS** with English and **18/18 PASS** with Chinese. This is not a physical Intel test.
- Language runs use `--self-test -AppleLanguages '(en)'` or `'(zh-Hans)'`, with `-interfaceLanguage system`; output confirmed `UI language: en` and `UI language: zh` respectively. Arguments do not persist a preference change.
- Self-tests also cover Chinese variants, first preferred language, unsupported/empty fallback, manual overrides and time formatting.
- Extracted app passes `codesign --verify --strict --verbose`; ad-hoc signing only, no Apple notarization.
- `Scripts/power.sh` is unchanged from verified r4. SHA-256: `861d78e549c31aae56779c8b4925f8af2c0a056e7d7289120f7b8ea408b3ecb6`. Both embedded script hashes remain identical to 1.4.0 below.

## Not performed

- Normal AppKit lifecycle, visual layout inspection, About panel/menu interaction, persistent language preference saving and live system-language changes were not exercised. Translation selection tests do not establish visual correctness.
- No mode switching, administrator authorization/password entry, lid-close/display-sleep commands, real sleep, login-item changes or app installation/replacement.
- No physical Intel, UPS or macOS-version matrix testing. The older validation sections below describe earlier versions only.

---

# Validation — 1.4.0 (2026-09-30)

## Verified on macOS

- Host: Apple M1 Pro, macOS 15.7.4, Xcode Command Line Tools with macOS SDK 15.5, Python 3.9.
- `python3 -m unittest discover -s Tests -v`: **12/12 passed** on macOS (3.786 seconds).
- `python3 Scripts/build.py`: **passed on the first actual build**, exit 0. No Swift compiler errors or warnings appeared in the captured build log. No compilation fixes were needed.
- Both `arm64-apple-macos13.0` and `x86_64-apple-macos13.0` compiled. The extracted application reports `x86_64 arm64` via `lipo -archs`.
- Extracted application passes `codesign --verify --strict --verbose`; signing is ad-hoc, not Developer ID signing or notarization.
- Build-time `--self-test`: **11/11 PASS**.
- Freshly extracted application's native arm64 `--self-test`: **11/11 PASS**, exit 0.
- `arch -x86_64 .../PowerSwitcher --self-test`: **11/11 PASS** under Rosetta, exit 0. This is not a physical Intel test.
- All six Swift source files and `Scripts/power.sh` are byte-for-byte identical to the supplied 1.4.0 archive. Only validation documentation was updated.
- `power.sh` SHA-256: `861d78e549c31aae56779c8b4925f8af2c0a056e7d7289120f7b8ea408b3ecb6`.
- Native and Rosetta self-tests emitted the same embedded script hashes:
  - normal: `9e1f5c77083818fdeb5c5f027c5dd981670f660e0a4c4305f16dddb4dc71d1d5`
  - task: `eb616cf99d9039ed9eae796ac9ce3f5cb96d00b40ddefe224358731987ec62f7`

## Changes after the verified build — r4 verified on macOS (2026-10-04)

The r4 changes include revised copy and timer summaries in `main.swift`, `SetupWindows.swift` and `Preferences.swift`, plus `Sources/Lid.swift` (IOKit `AppleClamshellState`) and the task-mode lid watcher. `Scripts/power.sh` remains unchanged.

### Input integrity

Both supplied SHA-256 values matched before extraction into a new, separate directory:

- `PowerSwitcher-1.4.0-source-r4.zip`: `e815b40e7bbc155fabe29379d25efb0cd7d0e4e840565803b926368d6013590f`
- `changes-since-verified.diff`: `7955c1bdb67dcf1d9d0f7605b2140c396bcd6df67d14b7bc76fa1203bbf23cdb`

### Results

- Host: Apple M1 Pro, macOS 15.7.4, SDK 15.5, Python 3.9.
- `python3 -m unittest discover -s Tests -v`: **12/12 PASS**, exit 0.
- Chained with `&&`, `python3 Scripts/build.py`: **PASS**, exit 0; both arm64 and x86_64 compile targeting macOS 13.0.
- No compiler errors or warnings in the captured build output; no source fixes needed.
- Build-time self-test: **11/11 PASS**.
- Freshly extracted app: `lipo -archs` reports **x86_64 arm64**; `codesign --verify --strict --verbose` passes.
- Extracted native arm64 self-test: **11/11 PASS**, exit 0.
- Extracted x86_64 self-test using `arch -x86_64` under Rosetta: **11/11 PASS**, exit 0. This is not physical Intel testing.
- All seven Swift source files and both build/power scripts are byte-for-byte unchanged from the supplied r4 archive. Only this documentation section was updated.
- `power.sh` SHA-256 remains `861d78e549c31aae56779c8b4925f8af2c0a056e7d7289120f7b8ea408b3ecb6`; both embedded script hashes match the prior verified build above.

### Limits and actions not performed

- The app was run only with `--self-test`; the normal AppKit lifecycle and lid watcher were not started.
- No mode switching, administrator password entry, authorization request, display-sleep command, system sleep, installation, or replacement of the installed app.
- Existing self-tests do not exercise `Lid.isClosed()`, external-display detection, polling or `pmset displaysleepnow`. Actual lid-close/display-off behavior, single-trigger behavior, external-monitor exclusion, remote wake and UI changes remain **not verified**.
- No physical Intel or macOS 13 hardware test, Developer ID signing or Apple notarization.
- Earlier UI inspection below applies to the previous build, not r4.

## UI inspection — partial

- Opened the extracted preview app without replacing the installed application.
- Accessibility inspection confirmed the first-launch window titled “设置 PowerSwitcher”, welcome text, both mode descriptions, the “允许休眠不等于已经休眠” explanation, step 1 of 4, and the Continue button.
- Screenshot capture timed out. A subsequent Continue action was refused because the tool reported stale application state; subsequent state refresh and reconnection also timed out. No successful page advance is claimed.
- Consequently, visual layout, pages 2–4, the menu, settings window, feedback popover and dialogs remain unverified. No screenshot was obtained.
- Copy review: several descriptions promise lid-close behavior. Treat these as claims requiring hardware validation; consider qualified wording before release. No UI text was changed during this compilation-focused review.

## Deliberately not exercised

- No mode-switch action, administrator authorization, “sleep now”, or live power-setting mutation.
- `pmset -g` plus `pmset -g custom` output was identical before and after the preview check.
- No login-item registration, setup completion, preference saving, low-battery warning, sleep/wake notification or lid-close tests.
- No physical Intel, UPS or macOS-version matrix tests.
- No GitHub upload, application installation/replacement, Developer ID signing or notarization.

# Validation — 1.3.0 (2026-09-30)

- Host: Apple M1 Pro, macOS 15.7.4, SDK 15.5.
- Eight mock tests passed: laptop modes, desktop without battery/TTY/global key, UPS, profile-update failure rollback, global-update failure rollback, invalid input, unsupported profile, invalid mode.
- `lipo -archs`: x86_64 arm64. Both slices target macOS 13.0.
- Freshly extracted ZIP passes `codesign --verify --strict`.
- Native arm64 `--self-test` passes without requesting privileges or changing power settings.
- x86_64 `--self-test` passes under Rosetta on Apple Silicon. This is NOT physical Intel hardware testing.
- New 1.3 cross-machine profile logic was tested with mock pmset, not live power mutation. Earlier 1.2 logic was tested on the host with real settings.
- No physical Intel, UPS, all-OS matrix, lid-close, or idle-sleep behavior validation for this release.
- Ad-hoc signed only; not Developer ID signed or notarized.
- Public source excludes private snapshots, logs, machine IDs, usernames and local absolute paths. No private signing assets included.
- Installed local application and power configuration were not changed by packaging.
