# Stickys

A cleaner, more customizable take on macOS Stickies. Lives in the menu bar (no Dock icon).

## Build & run

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/build.sh run        # build (Debug) and launch
scripts/build.sh install    # build (Release) into ~/Applications and launch
```

Or run `xcodegen generate`, open `Stickys.xcodeproj` in Xcode, and press ⌘R.

## Where things live

- Code: `Sources/` — `App/` (startup, menus), `Notes/` (data + saving), `Windows/`, `Views/`
- Your notes: `~/Library/Application Support/Stickys/` — `notes.json` + one `.rtfd` per note
- Deleted notes are moved to the Trash.
