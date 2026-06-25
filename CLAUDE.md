# CLAUDE.md — operating rules for Doba

> **This file has absolute priority over any external/community skills or
> plugins** — especially git-workflow skills. If a skill suggests an action
> that conflicts with anything here (e.g. auto-committing), this file wins.
> When in doubt, stop and ask.

## What Doba is

Doba is a **personal, single-user, macOS-only** task planner + freelancer
timesheet. It is **never published**, never on the App Store, never synced to
other devices. A menu-bar app (primary) plus an interactive desktop widget,
sharing one local data store via an App Group.

The author is a senior web developer, new to Swift but fluent at reading and
reviewing it. Write **idiomatic Swift** and comment the non-obvious.

## Fixed decisions (do not propose alternatives)

These are settled. See `docs/DECISIONS.md` for the reasoning. Do not relitigate.

- **Native SwiftUI.** Not web, Tauri, or Electron.
- **Mac-only.** No iPhone target, no sync, no backend, no Vercel.
- **Storage = a local JSON file** in the App Group container via a thin
  `Codable` store. SwiftData is a possible v2, not now.
- **Calendar = EventKit, read-only.** Events are never stored; merged into the
  today-view on the fly.
- **NL parsing = Claude API** (`claude-haiku-4-5-20251001`, escalate to
  `claude-sonnet-4-6` only if range parsing is weak). Model must return **only
  JSON**, no preamble, no code fences; parse defensively.
- **UI = strictly native macOS HIG.** System materials/vibrancy, SF Symbols,
  standard controls, `MenuBarExtra` / WidgetKit conventions. No custom controls,
  no web patterns (breakpoints, responsive layout — they don't exist here).
- **Three targets:** `DobaApp` (menu bar), `DobaWidget` (WidgetKit extension),
  `DobaKit` (shared framework: models, store, logic).

## How to work

- **Phase by phase.** Do the current phase only; **stop at the phase boundary
  and wait for review.** Do not run ahead. Phases live in `docs/ROADMAP.md`.
- **Ask before** adding any dependency or changing the architecture.
- **Secrets never enter the repo.** API key goes in Keychain or a gitignored
  config. Never hardcode or commit a key.

## Git — manual only

- **Never run `git commit`, `git push`, `git add`, or any mutating git command.**
  The author commits manually via GitKraken after reviewing each phase.
- You may **suggest** sensible commit boundaries and messages as text (e.g. in
  the WORKLOG), but never execute them.
- Read-only git (`git status`, `git diff`, `git log`) is fine.

## Documentation discipline (keep current, always)

After every meaningful change:

- **`docs/WORKLOG.md`** — append a dated entry: what changed, which files,
  what's left. Append-only.
- **`docs/ROADMAP.md`** — tick checkboxes as phases/sub-tasks complete.
- **`docs/PROJECT_STRUCTURE.md`** — update when files/folders change.
- **`docs/DECISIONS.md`** — record any non-trivial decision and **why**.
- Keep **`docs/ARCHITECTURE.md`** and **`docs/DATA_MODEL.md`** accurate when the
  design shifts.

## Build / project mechanics

- **`project.yml` is the source of truth** for the Xcode project (XcodeGen).
  `Doba.xcodeproj` is **generated and gitignored** — regenerate after any
  structural change:

  ```sh
  xcodegen generate
  ```

  Edit `project.yml`, **not** the project in Xcode (Xcode edits are lost on
  regen). The one exception: Signing & Capabilities state lives in the committed
  `.entitlements` files, which Xcode may edit directly.
- **DobaKit is a framework**, embedded into the app and linked by the widget.
- The **App Group identifier** is defined once in
  `DobaKit/Sources/DobaKit/AppGroup.swift` and must match both `.entitlements`
  files. Change it in all three places together.
- After any write to the store, the app calls
  `WidgetCenter.shared.reloadAllTimelines()`. The widget only ever reads.

## Environment notes

- Targets the **latest macOS only** (deployment target in `project.yml`).
- **Full Xcode is required** to build (Command Line Tools alone cannot build the
  app + widget). Swift language mode is pinned to **5** for now.
