# Babbler

A lightweight macOS menu bar app for fast switching between English and Russian keyboard layouts. If you accidentally typed in the wrong layout, Babbler fixes it instantly — no need to retype.

## How it works

**Typed text** — press the action key (Option by default) and Babbler deletes what you just typed and retypes it in the other layout:

```
Ghbdtn -> Option -> Привет
Руддщ  -> Option -> Hello
```

**Selected text** — select text and press the action key. Babbler translates the selection in place.

## Features

- Runs in the menu bar, shows the current input language
- Translates last typed word or selected text on action key press
- Configurable action key (Option, Right Option, Control, Right Control)
- Per-app default input language (auto-switches when you focus an app)
- Detects secure input mode and shows a warning
- Writes local crash logs for uncaught exceptions and fatal signals

## Requirements

- macOS
- Both English and Russian input sources must be enabled in System Settings
- Accessibility permission (the app prompts on first launch)

## Download

Prebuilt app archives are published in the [bin](./bin) folder.

## Build

### Xcode

1. Open `Babbler.xcodeproj` in Xcode
2. Build the `Babbler` scheme
3. Run the app

### Package a zip

Use the packaging script to build a release archive and create `bin/Babbler vX.Y.Z.zip`:

```sh
./scripts/package_app.sh
```

If your system is not using the full Xcode app as the active developer directory:

```sh
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" ./scripts/package_app.sh
```

## Setup

1. Build Babbler in Xcode or package it with `./scripts/package_app.sh`
2. Launch Babbler — it appears in the menu bar
3. Grant Accessibility access when prompted
4. (Optional) Open Settings from the menu bar icon to configure the action key and per-app input languages

## Crash Logging

Babbler installs local crash logging on launch.

- Uncaught `NSException` crashes are logged
- Fatal signals like `SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGTRAP`, `SIGFPE`, and `SIGILL` are logged
- Logs include the timestamp, app version, and stack trace
- Crash logs are written to `~/Library/Application Support/Babbler/Crashes`
