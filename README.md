# twen

A macOS menu bar app for the 20-20-20 rule: every 20 minutes of screen work, look 20 feet away for 20 seconds.

twen doesn't block you or pop up alerts. When a break is due, the screen slowly fades to grayscale, and the colour comes back once you've taken the break.

## Install

With Homebrew:

```bash
brew install --cask kannwism/tap/twen
```

Or download `twen-<version>.zip` from [Releases](https://github.com/kannwism/twen/releases), unzip it and move `twen.app` to `/Applications`.

twen is not notarized yet, so macOS may block the first launch. You can allow it in **System Settings → Privacy & Security**, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/twen.app
```

To build from source (requires macOS 13+ and Xcode 16 / Swift 6), run `make app`. The app is written to `build/twen.app`.

## The menu bar eye

| Icon | State | Meaning |
|:---:|---|---|
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/working-dark.png"><img src="docs/icons/working-light.png" height="36" alt="Half-filled eye"></picture> | Working | The lens fills as the 20 minutes build up. An empty eye means the timer hasn't started (it starts on your first input). |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/ramping-dark.png"><img src="docs/icons/ramping-light.png" height="36" alt="Eye half closed"></picture> | Fading | Break due. The screen is fading to gray, and the lid closes at the same pace. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/gray-dark.png"><img src="docs/icons/gray-light.png" height="36" alt="Closed eye"></picture> | Gray | Screen fully gray. It stays that way until you take a break. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/countdown-xx-dark.png"><img src="docs/icons/countdown-xx-light.png" height="36" alt="XX"></picture> <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/countdown-15-dark.png"><img src="docs/icons/countdown-15-light.png" height="36" alt="15"></picture> | Break | The countdown runs from `XX` (20) to `01`, and colour returns as it does. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/satisfied-dark.png"><img src="docs/icons/satisfied-light.png" height="36" alt="Eye with a check"></picture> | Break taken | You were away for at least a minute while the screen was gray. Colour returns on your next input. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/paused-dark.png"><img src="docs/icons/paused-light.png" height="36" alt="Eye with a pause sign"></picture> | Paused | Paused from the menu (1 hour / until tomorrow) or because you're on battery. |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/icons/suppressed-dark.png"><img src="docs/icons/suppressed-light.png" height="36" alt="Eye with a hollow square"></picture> | On hold | Something that shouldn't be interrupted is running (see below). |

States with an arbitrary fill are shown half full. Wherever the pupil sits below the fill line, it's drawn as a hole instead of solid.

Start a break from the menu or with the global shortcut (default **⌥⌘B**).

## When twen holds off

twen won't start or continue fading while any of these is true:

- **Display-sleep power assertion**: an app is holding `PreventUserIdleDisplaySleep`. Video players, presentations, video calls and games do this.
- **Screen sharing**: Screen Sharing / Remote Desktop style sessions.
- **Camera in use**: most likely a video call.
- **Fullscreen window**: a window covers an entire display.

While one of these is active, colour comes back within 2 seconds and the eye shows the hollow square. The timer stays full rather than resetting, and once the signal clears the fade starts over from the beginning.

The work timer also stops counting when you're not at the keyboard:

- Idle for 1–3 minutes pauses the timer. Idle for more than 3 minutes resets it.
- Screen lock, sleep and switching users count as idle.
- A manual pause, or **Pause while on battery** in Settings.

## License

GPLv3. See [LICENSE](LICENSE).
