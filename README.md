# Doba

A personal, macOS-only task planner + freelancer timesheet. Menu-bar app plus an
interactive desktop widget, sharing one local store. Single user, never
published, no sync, no backend.

> New here? Read **`CLAUDE.md`** (operating rules) and **`docs/`** —
> `ROADMAP.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `DECISIONS.md`.

## Build

Requires **full Xcode** (not just Command Line Tools). The Xcode project is
generated from `project.yml` via [XcodeGen](https://github.com/yonyz/XcodeGen):

```sh
brew install xcodegen      # once
xcodegen generate          # produces Doba.xcodeproj (gitignored)
open Doba.xcodeproj
```

First-time signing / App Group / widget setup: **`docs/SETUP.md`**.

## Layout

- **DobaApp** — `MenuBarExtra` app (primary surface, owns all writes)
- **DobaWidget** — WidgetKit extension (read-only glance + tick)
- **DobaKit** — shared framework (models, JSON store, logic)

Status: **Phase 0 (scaffold)** — see `docs/ROADMAP.md`.
