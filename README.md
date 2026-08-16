# Mixly

Mixly is a macOS app that lets you control the volume of individual applications, not just the system volume as a whole — similar to Windows' per-app volume mixer.

## Features

- **System volume control** — read and set the default output device's volume.
- **Per-app volume mixing** — see every app currently producing audio and adjust its volume (or mute it) independently, without touching the others.
- **Live audio activity** — apps are flagged as "playing" in real time based on actual audio output, and the list refreshes automatically as apps start/stop making sound.
- **Helper process grouping** — auxiliary processes (e.g. browser helpers) are grouped under their parent app, so multiple processes from the same app appear as one entry.

## How it works

macOS doesn't expose a native per-app volume mixer, so Mixly builds one using **Core Audio Process Taps** (macOS 14.4+):

1. It enumerates the audio-producing processes registered with the system HAL (`kAudioHardwarePropertyProcessObjectList`) and groups them by owning application.
2. When you change an app's volume, Mixly creates a **process tap** (`ProcessTap.swift`) for that app's processes with `muteBehavior = .mutedWhenTapped`, which silences the app's original output.
3. A private aggregate device combines the tap with the system's default output device. Mixly's IO proc reads the tapped audio, applies the chosen gain, and renders it back to the real output device.
4. Setting the volume back to 100% removes the tap entirely, restoring the app's original audio path.

This means Mixly doesn't just change a volume value — it actually re-renders each app's captured audio stream at the gain you set.

## Requirements

- macOS 14.4 or later (Process Tap APIs)
- Xcode 15.4+ to build
- "Audio Capture" permission, granted on first use via **System Settings → Privacy & Security → Screen & System Audio Recording**

## Building

```bash
git clone https://github.com/edilson14/Mixly.git
cd Mixly
xcodebuild build -scheme Mixly -configuration Release
```

## Building & packaging a DMG

```bash
./build_and_distribute.sh YOUR_TEAM_ID
```

See [DISTRIBUTION.md](DISTRIBUTION.md) for the full build, signing, and notarization workflow.

## Project structure

| File | Purpose |
|---|---|
| `AudioKitController.swift` | Discovers audio processes, groups them by app, and manages taps |
| `ProcessTap.swift` | Wraps `AudioHardwareCreateProcessTap` and the aggregate device used to re-render audio with gain |
| `CoreAudioManager.swift` | Reads/sets the system output device's volume |
| `AudioKitAppView.swift` | Per-app mixer UI (list, sliders, mute) |
| `SystemVolumeView.swift` | System volume UI |
| `ContentView.swift` | Root view combining system + per-app controls |

## License

MIT — see [LICENSE](LICENSE).
