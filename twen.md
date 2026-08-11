# twen

A minimal macOS menu bar app for the 20-20-20 rule: every 20 minutes of real screen work, look 20 feet away for 20 seconds.

Existing apps are heavy or aggressive. twen nudges instead of blocking.

## Core idea

- After 20 min of non-idle work, the screen **slowly desaturates** toward grayscale over ~2 min.
- No blocking, no modal, no sound. The fading color is the entire notification.
- User starts the break via **global keyboard shortcut** or the **menu bar** item.
- Break = 20s countdown in the menu bar popover; saturation ramps back to normal as it runs.
- If the user goes idle ≥1 min while desaturated, the break counts as taken automatically — color returns on their next input.
- If ignored, the screen holds at full grayscale until a break is taken (passive nag, never a blocker).

## Non-goals

- No accounts, no network, no analytics, no telemetry.
- No blocking overlays, forced breaks, or streak gamification.
- No App Store (unsandboxed by design); no cross-platform.

## Timer semantics

- Work timer accrues only during active input.
- Idle 1–3 min → pause timer. (Was 20s–1 min; reading without input is still screen time, so short input gaps must not reset the timer.)
- Idle >3 min → reset timer.
- Idle ≥1 min while desaturated → break satisfied (separate threshold from the reset: a minute genuinely away rests the eyes).
- Screen lock / sleep / user switch → treated as idle from that moment, same thresholds: unlock within 3 min just pauses accrual, longer resets; ≥1 min while desaturated satisfies the break.
- Timer starts from first real activity, not app launch.

## Things to poll

- `CGEventSourceSecondsSinceLastEventType(.hidSystemState, .anyInputEventType)` — seconds since last HID input. No permissions. Poll every 1–5s.
- `IOPMCopyAssertionsByProcess` — power assertions. `PreventUserIdleDisplaySleep` covers video playback, presentations, video calls and games in one check. Primary suppression signal.
- `CGWindowListCopyWindowInfo` — secondary fullscreen check: layer 0 window with bounds == display bounds.
- Camera in-use state — likely video call.
- Screen sharing / recording active — never desaturate mid-demo.

## Things to listen to

- `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` (distributed notifications).
- `NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`.
- `NSWorkspace.willSleepNotification` / `didWakeNotification`.
- `NSWorkspace.sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` (fast user switching).
- `NSApplication.didChangeScreenParametersNotification` — display added/removed/resolution change.
- Screensaver start/stop notifications.

## Suppression rules

Don't start or advance desaturation when:

- A `PreventUserIdleDisplaySleep` assertion is held (video, presentation, call, game).
- A native-fullscreen window covers a display.
- Screen sharing or recording is active.
- Optional: Low Power Mode / on battery.

Suppression pauses the ramp; it does not consume the break.

## Desaturation implementation

~~Needs a spike~~ — **spiked 2026-08-11, resolved.** Private `CABackdropLayer` + `colorSaturate` CAFilter works on macOS 26.5: smooth true desaturation across 3 displays, judged clearly nicer than the overlay fallback. Chosen as the primary backend; the overlay+gamma approach stays as a fallback backend behind the same protocol in case a macOS release breaks the private API. Prototypes live in `spike/`.

- Gamma tables (`CGSetDisplayTransferByTable`) are per-channel curves. They can dim and warm but **cannot desaturate**. Not sufficient alone.
- Private `CABackdropLayer` + `colorSaturate` filter gives true gradual desaturation. Works, but undocumented and may break between macOS releases.
- Accessibility grayscale toggle is binary, not gradual, and needs permission. Rejected.
- **Fallback:** click-through borderless overlay window per display, mid-gray, alpha ramping 0 → ~0.3. Not literal desaturation but reads as the screen quietly draining. Fully public API. Combine with a gamma contrast reduction to get closer.
- Ramp driven by Core Animation, not a per-frame timer.
- All displays desaturate together.

## Settings

- Work interval (default 20 min), break length (default 20s).
- Ramp duration (default 2 min).
- Global shortcut.
- Launch at login.
- Pause for 1h / until tomorrow / while on battery.

## Stack

- Swift + SwiftUI, `MenuBarExtra` (macOS 13+).
- `LSUIElement` — menu bar only, no dock icon.
- `SMAppService` for launch at login.
- Carbon `RegisterEventHotKey` for the global shortcut (no Accessibility permission needed).
- Unsandboxed, notarized, hardened runtime.

## Distribution

- Open source.
- Notarized `.dmg` on GitHub Releases.
- Homebrew cask (`brew install --cask twen`).
- Sparkle for in-app updates.

## Performance budget

- Idle CPU ≈ 0%. Single lightweight poll timer; no work while suppressed or fully saturated.
- No background threads spinning during the ramp — hand off to Core Animation.
- Small binary, no dependencies beyond Sparkle.

## Deferred

- **Do Not Disturb / Focus awareness.** No public API; requires reading `~/Library/DoNotDisturb/DB/*.json`. Deferred to a later version, ideally per-Focus-mode.
- **Per-app exclusion list.** For color-critical work (Figma, Photoshop, Lightroom, DaVinci, Final Cut) where desaturation actively interferes. Revisit once the ramp is real and we can feel how bad it is.
- Break history / stats.
- Per-display independent state.
- Optional dim-and-warm mode as an alternative to grayscale.
