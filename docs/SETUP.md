# Doba — One-time manual setup (author)

These steps need full Xcode and the GUI — they can't be automated. Do them once
before the first build. Check each off.

## 0. Install full Xcode

This machine currently has only **Command Line Tools**, which cannot build a
SwiftUI app + widget. Install **Xcode** from the App Store, then point the
toolchain at it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version            # sanity check
```

- [ ] Full Xcode installed and selected

## 1. Generate & open the project

`Doba.xcodeproj` is generated from `project.yml` (and is gitignored).

```sh
xcodegen generate
open Doba.xcodeproj
```

- [ ] Project opens with three targets: **DobaApp**, **DobaWidget**, **DobaKit**

> Re-run `xcodegen generate` whenever `project.yml` changes. Don't hand-edit the
> project in Xcode (changes are lost on regen) — except Signing & Capabilities,
> which writes to the committed `.entitlements` files.

## 2. Signing

For each target — **DobaApp**, **DobaWidget**, **DobaKit** — in
*Signing & Capabilities*:

- [ ] Signing is **Automatic**
- [ ] **Team** = your Apple ID / developer team (currently blank on purpose)

A free personal Apple ID works for local running. Note: **App Groups may not
provision on a free account** — see step 3.

## 3. App Group + Sandbox (the shared store)

**Both** targets are sandboxed and carry the App Group — that symmetry is what
makes them resolve the *same* container (App Group containers are a sandbox
feature; a non-sandboxed app won't reliably share one). The entitlements already
declare `com.apple.security.app-sandbox` + `group.com.andreyrozumny.Doba`. Verify
Xcode picks them up:

- [ ] **DobaApp** → Signing & Capabilities shows **App Sandbox** and **App
      Groups** with `group.com.andreyrozumny.Doba` checked
- [ ] **DobaWidget** → **App Sandbox** + **App Groups**, **same** group ID

If a capability/row is missing: **+ Capability → App Sandbox** and **App
Groups**, then add `group.com.andreyrozumny.Doba` (must match exactly on both
targets **and** `AppGroup.identifier` in
`DobaKit/Sources/DobaKit/AppGroup.swift`).

> If App Groups won't provision (can happen on free accounts): both targets fall
> back to their own per-sandbox `Application Support/Doba/` and won't share. The
> diagnostics in step 5 tell you exactly which case you're in.

## 4. Embedding (verify — this is the framework wiring)

- [ ] **DobaApp → General → Frameworks, Libraries, and Embedded Content:**
      `DobaKit.framework` = **Embed & Sign**
- [ ] **DobaApp** embeds **DobaWidget.appex** (shows under embedded content /
      Build Phases → *Embed Foundation Extensions* / *Embed App Extensions*)
- [ ] **DobaWidget → General:** `DobaKit.framework` = **Do Not Embed**
      (linked only — the app supplies the embedded copy via `@rpath`)

## 5. Build, run & verify sharing

- [ ] Select the **DobaApp** scheme → **Run** (⌘R)
- [ ] A **checklist** icon appears in the menu bar; clicking it shows today's
      three sample tasks (Timeline + Floating sections). On first launch the app
      **seeds** the shared store.
- [ ] Ticking a checkbox persists (toggle survives quitting/reopening)

**Confirm the container resolves to the same path in both processes.** Each logs
its resolution on launch (subsystem `com.andreyrozumny.Doba`, category `store`):

- In **Console.app**, search `com.andreyrozumny.Doba` and look for two lines:
  `[DobaApp] … container=… sharing=true` and `[DobaWidget] … container=…`.
- [ ] Both `container=` paths are **identical** and `sharing=true`
      (a `~/Library/Group Containers/<TeamID>.group.com.andreyrozumny.Doba/…`
      path). The app line also prints when run from Xcode's debug console.

> `sharing=false` / `container=<nil>` on either line = the App Group isn't
> provisioning (free-account limitation). Then they read different files: the app
> shows its seeded tasks, the widget shows empty. Fix by provisioning the group
> (paid Apple Developer account or a configured group on your team).

## 6. Add the widget

- [ ] Right-click the desktop → **Edit Widgets** (or open Notification Center →
      Edit Widgets), find **Doba → Today**, add it
- [ ] It shows the **same three tasks** the menu bar shows (it's reading the
      shared store now, not sample data)
- [ ] Tick a checkbox in the menu bar → the widget reflects it (the app calls
      `reloadAllTimelines()` after each write)

## Clean slate (if a stale store confuses verification)

If earlier runs left a store with old-dated tasks, delete it and relaunch — the
app reseeds today's sample. The exact file path is in the step-5 log line
(`file=…`). Typical sandboxed location:
`~/Library/Group Containers/<TeamID>.group.com.andreyrozumny.Doba/doba.json`.

## Notes

- Bundle IDs use `com.andreyrozumny.*` placeholders. To change them, edit
  `project.yml` (and keep the App Group ID in sync across the two `.entitlements`
  files + `AppGroup.swift`), then `xcodegen generate`.
