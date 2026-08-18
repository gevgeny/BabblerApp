# Installing Babbler

## Quick install (build from source)

```sh
./scripts/install.sh
```

Builds Release with ad-hoc signing, replaces `/Applications/Babbler.app`, and
relaunches.

## Install a prebuilt archive on another Mac

```sh
unzip Babbler-v1.0-stable.zip
xattr -dr com.apple.quarantine Babbler.app     # ad-hoc signed, not notarised
cp -R Babbler.app /Applications/
open /Applications/Babbler.app
```

## Permissions — both are required

Babbler needs **two separate** grants in
System Settings → Privacy & Security. Granting only one leaves the app in a
confusing half-working state.

| Permission | Needed for | Symptom if missing |
| --- | --- | --- |
| **Input Monitoring** | Seeing which keys you type (`NSEvent` global `.keyDown` monitor) | Action key flips the layout, and swapping *selected* text works, but the last typed **word** is never swapped |
| **Accessibility** | Posting the synthetic keystrokes that rewrite the text | Nothing is replaced at all |

The app prompts for whichever is missing on launch.

### After every rebuild — re-grant both

The project is signed **ad hoc** (`CODE_SIGN_IDENTITY="-"`), because the
original team certificate `S6G53UGWX8` is not available. Every build produces a
different code signature, and macOS ties TCC grants to the signature. An
existing grant therefore goes stale and silently stops working even though the
checkbox still looks ticked.

After each reinstall, in **both** Input Monitoring and Accessibility:

1. Select Babbler
2. Click **–** to remove it
3. Click **+** and add `/Applications/Babbler.app`

Merely unticking and re-ticking is not enough — remove and re-add.

## Verifying it works

1. Switch to the English layout
2. Type `ghbdtn`
3. Press Option

You should get `привет`, with the system layout switched to Russian.
Shift+Option does the same for the whole line.

## Troubleshooting

- **Nothing happens on Option** — check Input Monitoring first; that is the most
  common cause.
- **Only selected text is swapped** — Input Monitoring is missing or stale.
- **App disappears after sleep** — check `~/Library/Application Support/Babbler/Crashes/`.
- **Duplicate icons in Launchpad** — stale Launch Services entries:
  ```sh
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u /path/to/stale/Babbler.app
  ```
