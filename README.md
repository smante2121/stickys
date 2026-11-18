# Stickys

i love the mac native stickies app but i wanted to more customizations and a liquid glass option and other features like bulleted lists. it also doesnt show an icon in the doc

## Build & run

Requires Xcode 26+.

```sh
scripts/build.sh run        # build (Debug) and launch
scripts/build.sh install    # build (Release) into ~/Applications and launch
```

Or open `Stickys.xcodeproj` in Xcode and press ⌘R. New `.swift` files added under `Sources/` are picked up automatically.

## Where things live

- Code: `Sources/` — `App/` (startup, menus), `Notes/` (data + saving), `Windows/`, `Views/`
- Your notes: `~/Library/Application Support/Stickys/` — `notes.json` + one `.rtfd` per note
- Deleted notes are moved to the Trash.
