# Doba

**A tiny day planner & freelance timesheet for macOS that lives in your menu bar.**

*доба (ua) — one full day, dawn to dawn.*

I made it for myself so I'd stop losing track of time. **Free and open source** —
everything stays on your Mac: no cloud, no accounts, no backend.

🖥️ A visual tour (UK / EN): open [`docs/presentation.html`](docs/presentation.html) in a browser.

---

## What it does

- **Day · Week · Month** — a plan for today, a color-coded week overview, and a
  monthly report. Step through days, weeks and periods; past days are an archive.
- **Billable vs overhead** — every task is billable (its project has a rate) or
  overhead; both are shown everywhere. Goals: **40h/week** and **160h per pay
  period (15→15)**; earnings come from per-project rates.
- **Natural-language entry (Claude)** — type *“call with client, Acme, 1h, 11:30”*
  and the AI fills in project, hours, time, billable. Ranges (*“6h/day Mon–Fri”*)
  expand into per-day tasks. The model returns JSON only; parsed defensively.
- **Parallel timers** — run timers on several tasks at once. They count real
  minutes, **burn down from the estimate**, and **auto-stop at the limit** with a
  sound + a notification over all apps.
- **Calendar (read-only)** — system-calendar meetings (EventKit) merge into the
  timeline; turn any meeting into a task in one click (project & billable via Claude).
- **Recurring, deferral, nudges** — recurring tasks (daily / weekdays / weekly),
  defer to tomorrow, carry-over of unfinished work, and a gentle nudge to log time.
- **Global hotkey ⌃⌥D** — a quick-capture field pops up from any app: type a task,
  hit Enter, and it's in your plan (or parsed by Claude).
- **Monthly report (15→15)** — a dedicated tab: how much you earned and worked over
  the pay period, a per-project breakdown, progress to 160h. Periods are navigable.

Compact, native **360×520** menu-bar panel — strict macOS HIG, system materials, SF Symbols.

## Privacy

Everything is **local**: one JSON file in the app's container. No sync, no
backend, no analytics. The only network call is the optional Claude parse; the
**API key lives in the macOS Keychain**, never in the repo or the data file.

## Tech

Native and **dependency-free**, with a clean, tested core.

`SwiftUI` · `WidgetKit` · `EventKit` · `Claude API` (raw URLSession) · `Keychain` ·
`Carbon` hotkey · `UserNotifications` · `XcodeGen` · local JSON store

**Three targets:**

- **DobaApp** — the `MenuBarExtra` app (primary surface, owns all writes)
- **DobaWidget** — a WidgetKit extension (read-only glance)
- **DobaKit** — shared framework: models, JSON store, and all logic as **pure,
  tested functions** (validated with standalone `swiftc` test harnesses)

## Build

Requires **full Xcode** (not just Command Line Tools). The Xcode project is
generated from `project.yml` via [XcodeGen](https://github.com/yonyz/XcodeGen):

```sh
brew install xcodegen      # once
xcodegen generate          # produces Doba.xcodeproj (gitignored)
open Doba.xcodeproj         # then Run (⌘R)
```

First run: paste an Anthropic API key in Settings (the gear) to enable ✨ parsing,
and grant calendar access if you want meetings merged. See **`docs/SETUP.md`**.

## Docs

`docs/` holds the full story: `ROADMAP.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`,
`PROJECT_STRUCTURE.md`, `DECISIONS.md` (ADR-lite, D1–D43), `WORKLOG.md`, and
`presentation.html`. `CLAUDE.md` is the operating-rules file.

---

*Personal project, built in a few days. Mac-only, private, no cloud. Free & open source.*
