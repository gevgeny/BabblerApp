# Handoff: implement automatic layout switching in Babbler

## Context

Babbler is a macOS menu bar app (Swift/SwiftUI + AppKit, Xcode project, no SPM
deps) that switches typed text between the English and Russian keyboard
layouts. Today the correction is **manual**: you type `ghbdtn`, press the action
key (Option), and it becomes `привет`.

Repo: `gevgeny/BabblerApp`
Working branch: `nickvlasovprogress-improved-journey`
Frozen known-good baseline: tag **`v1.0-stable`** (commit `573960b`)

The branch is 7 commits ahead of `origin/master` and has never been pushed.
Everything below `v1.0-stable` is verified working on the user's machine.

## Your task

Implement the MVP described in **`docs/AUTO_SWITCH_PLAN.md`**. Read that file
first — it is the spec. It covers dictionaries, the decision rule, undo, the
settings UI, edge cases, and a four-phase breakdown.

In short: on a word boundary, decide whether the word that was just typed is
gibberish in the current layout but a real word in the other one, and if so
correct it automatically — Punto Switcher / Caramba Switcher behaviour.

## What is already in place

The plumbing is done; this is mostly a decision layer on top of it.

- `KeyDictionary.swift` — EN↔RU character maps
- `KeyboardUtils.translateText` — converts a string between layouts
- `KeyboardUtils.replaceTypedText` — deletes and retypes a recorded keystroke run
- `AppDelegate.wordRecord` / `.text` — buffer of the word being typed
- `AppDelegate.handleGlobalSystemEvent` — already detects word boundaries
- `AppDelegate.beginSwitch(_:)` — the whole swap path, with watchdogs

The hook point is the word-boundary branch in `handleGlobalSystemEvent`
(around line 219, `isWordBreak`). A positive decision should route into the
existing `beginSwitch(wordRecord)` so the auto correction behaves exactly like a
manual action-key press.

## Hard-won context — do not rediscover this

**Two separate permissions are required, and this is the single biggest trap.**
- **Input Monitoring** (`kIOHIDRequestTypeListenEvent`) — needed by
  `NSEvent.addGlobalMonitorForEvents` to receive `.keyDown`/`.keyUp`.
  Not needed for `.flagsChanged`.
- **Accessibility** (`AXIsProcessTrusted`) — needed to post synthetic keystrokes.

If Input Monitoring is missing, the app looks half-alive: the action key is
detected and the layout flips, and swapping *selected* text works, but no
keystroke is ever recorded so the last-typed-word swap silently never fires.
`AppDelegate.hasPrivileges()` now checks both.

**Ad-hoc signing invalidates permissions on every rebuild.** The team
certificate `S6G53UGWX8` is unavailable, so builds use
`CODE_SIGN_IDENTITY="-"`. Each build changes the signature and macOS silently
stops honouring the existing TCC grant even though the checkbox still appears
ticked. After **every** reinstall the user must remove and re-add
`/Applications/Babbler.app` in **both** Input Monitoring and Accessibility.
Tell them this each time; do not let them chase a phantom bug.

**`isWaitingForSwitch` gates all event handling.** `handleGlobalSystemEvent`
returns early while it is set. It used to be cleared only by the input-source-
changed distributed notification, so one missed notification latched it on
forever and killed the app until restart. It is now released by watchdog timers
(0.5 s to force the replacement, 2 s to force the release). It is deliberately
left set *during* the synthetic replay so the posted CGEvents are not recorded
back into `wordRecord`. **Preserve this invariant** — auto-switch runs through
the same path, so any new code that sets it must guarantee a release.

**Carbon TIS APIs are not thread-safe.** `TISCopyCurrentKeyboardInputSource`,
`TISSelectInputSource`, and `String(describing: TISInputSource)` must run on the
main thread. Use `MainActor.run` when dispatching from a `Task`. The global
event monitor delivers on a background thread and already hops to main.

**`InputSourceUtils.inputSources` is `nil`** until `initInputSources()` runs in
`finishApplicationSetup()`. Anything validating saved preferences against
available sources must guard the `nil` case or it will wipe saved data.

**Do not use `killall` or `pkill`** in this environment — they are blocked. Find
the PID with `ps aux | grep -i "[B]abbler.app"` and `kill <pid>`.

## Build, install, test loop

```sh
./scripts/install.sh          # build + kill old instance + install + launch
```

Then have the user re-grant both permissions (see above), and verify:
1. English layout, type `ghbdtn`, press Option → `привет`
2. Shift+Option swaps the whole line
3. Selecting text and pressing Option still works
4. It still works after several swaps in a row

Crash logs: `~/Library/Application Support/Babbler/Crashes/`
Prefs: `defaults read eugene.Babbler`

## Ground rules

- Indent with **2 spaces**, not tabs; follow each file's existing style.
- Default the auto-switch preference to **off**, so upgrading changes nothing
  until the user opts in.
- Be conservative in the decision rule. A false positive that mangles correct
  text is far worse than a missed correction.
- Work incrementally against `v1.0-stable` and keep it buildable — the user
  relies on this app daily.
- Commit per phase with the `Co-authored-by: Copilot App
  <223556219+Copilot@users.noreply.github.com>` trailer.

## Suggested first steps

1. Read `docs/AUTO_SWITCH_PLAN.md` and `docs/INSTALL.md`.
2. Read `Babbler/AppDelegate.swift`, `Babbler/KeyboardUtils.swift`,
   `Babbler/KeyDictionary.swift`.
3. Confirm the dictionary sources and licensing with the user before bundling
   several MB of word lists into the repo.
4. Start with Phase 2 (the pure decision function) behind a stub dictionary — it
   is unit-testable with no permissions, no UI, and no rebuild loop.
