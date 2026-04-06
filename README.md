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

## Requirements

- macOS
- Both English and Russian input sources must be enabled in System Settings
- Accessibility permission (the app prompts on first launch)

## Setup

1. Open the project in Xcode and build
2. Launch Babbler — it appears in the menu bar
3. Grant Accessibility access when prompted
4. (Optional) Open Settings from the menu bar icon to configure the action key and per-app input languages
