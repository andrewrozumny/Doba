# Doba — build & run (one-time setup)

A few GUI/Xcode steps that can't be scripted. Do them once before the first
build.

## 0. Full Xcode

Building a SwiftUI app + WidgetKit extension needs **full Xcode** (Command Line
Tools alone can't). Install Xcode, then select it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version            # sanity check
```

## 1. Local signing config

Bundle IDs and your Apple Team ID come from a **gitignored** xcconfig, so nothing
personal is committed. Copy the template and fill it in:

```sh
cp Config/Doba.xcconfig.example Config/Doba.xcconfig
```

Then edit `Config/Doba.xcconfig`:

- `DOBA_BUNDLE_PREFIX` — a reverse-DNS prefix you control, e.g. `com.yourname`
  or `io.github.youruser`. It drives the app/widget bundle IDs and the App Group.
- `DOBA_TEAM_ID` — your Apple Developer Team ID (Xcode ▸ Settings ▸ Accounts).
  Leave blank to pick the team manually in *Signing & Capabilities* instead.

## 2. Generate & open the project

`Doba.xcodeproj` is generated from `project.yml` (and is gitignored).

```sh
brew install xcodegen      # once
xcodegen generate
open Doba.xcodeproj
```

> Re-run `xcodegen generate` whenever `project.yml` or `Config/Doba.xcconfig`
> changes. Don't hand-edit the project in Xcode (lost on regen) — except
> Signing & Capabilities, which writes to the committed `.entitlements` files.

## 3. Signing

For each target — **DobaApp**, **DobaWidget**, **DobaKit** — in
*Signing & Capabilities*:

- Signing is **Automatic**
- **Team** is set (from `DOBA_TEAM_ID`, or pick it here)

A free personal Apple ID is enough to build and run locally.

## 4. Where data lives

The store is a single JSON file in the app's own **Application Support** folder
(inside its sandbox container):
`~/Library/Containers/<DOBA_BUNDLE_PREFIX>.Doba/Data/Library/Application Support/Doba/doba.json`.

The App Group entitlement (`group.<DOBA_BUNDLE_PREFIX>.Doba`, substituted from the
xcconfig) is only needed by the desktop **widget**, which is parked: App Groups
don't provision on a **free** Apple account, so the widget can't share the
store there. The menu-bar app doesn't depend on it.

## 5. Build & run

- Select the **DobaApp** scheme → **Run** (⌘R)
- A checklist icon appears in the menu bar; click it for today's plan
- Open **Settings** (the gear) and paste your Anthropic API key to enable ✨
  natural-language entry — it's stored in the Keychain, never on disk or in the repo
- Grant Calendar access (read-only) if you want meetings merged into the timeline

## Changing the bundle prefix later

Edit `Config/Doba.xcconfig` and re-run `xcodegen generate`. Everything else
(bundle IDs, the App Group in both `.entitlements`, and `AppGroup.swift`, which
reads it from Info.plist at runtime) follows automatically.
