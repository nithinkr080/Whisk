# Whisk

A fast, free window switcher for macOS: press a shortcut, see live previews of every window across all your Spaces, and jump to one. Free forever: no subscriptions, no accounts, no tracking.

Native Swift (SwiftUI + AppKit), macOS 14 or later.

**Website: [nithinkr080.github.io/Whisk](https://nithinkr080.github.io/Whisk/)**

![Whisk's Liquid Glass design](docs/liquid-glass.jpg)

## Features

- **⌥ Tab** switches between all windows, **⌥ ⇧ Tab** goes backwards, **⌥ `** switches between windows of the current app. The hold key can be ⌥, ⌃ or ⌘ (⌘ replaces the system app switcher).
- Hold the key to keep the panel open and release it to switch. A quick tap jumps straight to your previous window without showing the panel.
- **Works across Spaces and fullscreen apps**: pick a window in a fullscreen app (or on another desktop) and Whisk takes you there.
- **Live previews** of every window, including ones on other Spaces and minimized ones.
- While the panel is open: arrow keys, Return, Esc, **Q** quit app, **W** close window, **M** minimize, **H** hide app, plus mouse hover and click. Hovering a tile shows close / minimize / fullscreen buttons.
- **Two designs**: the classic panel, and an experimental **Liquid Glass** design (macOS 26+) where one glass shape flows from window to window, with a Clear ↔ Frosted slider.
- Filters for minimized, hidden, fullscreen and other-Space windows, a per-screen option, an excluded-apps list, light / dark / system theme, three tile sizes, and launch at login.

| Preferences | Appearance, with live preview |
| --- | --- |
| ![General preferences](docs/preferences-general.png) | ![Appearance preferences](docs/preferences-appearance.png) |

The Liquid Glass selection moving between windows:

![Selection gliding between windows](docs/liquid-glass-moving.jpg)

## Install

### Download (easiest)

Grab **Whisk-x.y.z.dmg** (or the `.zip`) from the [Releases page](https://github.com/nithinkr080/Whisk/releases/latest), open it, and drag **Whisk** into **Applications**. It runs on both Apple Silicon and Intel Macs (macOS 14+).

Whisk is not notarized by Apple (that needs a paid developer account), so macOS shows a warning the first time you open it:

> **"Whisk" Not Opened** — Apple could not verify "Whisk" is free of malware that may harm your Mac or compromise your privacy.

This is expected for any app that isn't notarized. Whisk is open source, so you can read the code or [build it yourself](#build-from-source). To open it:

1. Click **Done** (not "Move to Bin").
2. Open the Apple menu → **System Settings → Privacy & Security**.
3. Scroll down to **Security**. You will see *"Whisk" was blocked…*. Click **Open Anyway**.
4. Confirm with Touch ID or your password, then click **Open**.
5. Whisk asks for **Accessibility** and **Screen Recording**. Turn both on in Privacy & Security, then open Whisk again.

You only do this once.

**No "Open Anyway" button?** Try opening Whisk once more, then look again: macOS only shows it for about an hour after a blocked launch.

**Says "damaged and can't be opened"?** Run this once in Terminal, then open Whisk again:

```bash
xattr -dr com.apple.quarantine /Applications/Whisk.app
```

(On macOS 14 and older you can also right-click **Whisk** → **Open** → **Open**.)

### Build from source

You need Xcode (or the Xcode command line tools) with a macOS 14+ SDK:

```bash
git clone https://github.com/nithinkr080/Whisk.git
cd Whisk
./build.sh                      # builds build/Whisk.app
open build/Whisk.app
```

`Scripts/package_release.sh <version>` builds a universal app and produces the `.zip` and `.dmg` that are attached to releases.

Whisk lives in the menu bar and has no Dock icon. Open **Preferences** from the menu bar icon. Copy it to `/Applications` if you want "Launch at login" to stick.

### Permissions

On first launch Whisk asks for two macOS permissions (System Settings → Privacy & Security). The Permissions page in Preferences shows their status and links to the right place.

| Permission | Why it is needed |
| --- | --- |
| Accessibility | Detects the keyboard shortcut; raises, closes and minimizes windows |
| Screen Recording | Live window previews (without it you get app icons only) |

Whisk does not record or store your screen, and it makes no network connections. Previews stay in memory and are discarded when the app quits.

The build is signed ad hoc, so macOS asks you to confirm it the first time (System Settings → Privacy & Security → Open Anyway), and after you rebuild you may need to re-enable the permissions (remove the old Whisk entry and add it again if it looks stuck).

## Things to know

- **It uses private macOS APIs** (a handful of SkyLight / CoreGraphics / Accessibility calls) to find windows on other Spaces and to focus a specific window. That is how every window switcher of this kind works, but it means Whisk cannot be sold on the Mac App Store, and a future macOS update could break parts of it.
- The Liquid Glass design needs macOS 26 or later. Older systems get a frosted-material fallback.
- Windows on other Spaces are discovered with a heuristic, so you may occasionally see a stray window.

## Project layout

| File | Role |
| --- | --- |
| `HotKeyManager.swift` | Global keyboard handling (CGEventTap) |
| `SwitcherController.swift` | The switching session and the floating panel |
| `SwitcherView.swift`, `SwitcherModel.swift` | Classic and Liquid Glass SwiftUI views, tile layout |
| `WindowProvider.swift` | Window discovery and focus / close / minimize actions |
| `Spaces.swift` | Spaces and fullscreen detection |
| `ThumbnailService.swift` | Window thumbnails |
| `PrivateAPIs.swift` | The private symbols in one place |
| `Settings.swift`, `PreferencesView.swift`, `Permissions.swift`, `AppDelegate.swift` | Preferences, onboarding, menu bar |
| `Preview.swift`, `PerfFlags.swift` | Developer aids (see below) |

### Developer aids

The binary has a few hidden modes for testing without driving your screen, for example `--list`, `--prefs-shot <prefix>`, `--liquid-shot <prefix>` and `--real-perf <report>` (frame pacing on your real windows). Run them through `open -n -W build/Whisk.app --args …` so they use the app's own permissions. Set `defaults write io.github.nithinkr080.whisk debugLog -bool true` to log window switches to `~/Library/Logs/Whisk.log`.

## Acknowledgements

Inspired by [AltTab](https://github.com/lwouis/alt-tab-macos) and other macOS window switchers. Whisk is an independent project written from scratch and is not affiliated with or endorsed by AltTab.

## License

[MIT](LICENSE)
