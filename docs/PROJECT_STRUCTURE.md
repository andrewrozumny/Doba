# Doba — Project structure

Map of the repo. Update this when files/folders change.

```
Doba/
├── project.yml                     XcodeGen spec — SOURCE OF TRUTH for the project
├── Doba.xcodeproj/                 GENERATED (gitignored) — `xcodegen generate`
├── Config/
│   ├── Doba.xcconfig.example       Template: bundle prefix + Apple Team ID
│   └── Doba.xcconfig               Your local signing/identity (gitignored)
├── CLAUDE.md                       Operating rules for Claude Code (priority doc)
├── README.md                       Project intro + features (GitHub front page)
├── LICENSE                         MIT
├── screenshots/                    Images used by README + the landing page
├── .gitignore                      Xcode / SwiftPM / secrets / generated project
│
├── DobaKit/                        Shared framework: models, store, logic (no UI)
│   └── Sources/DobaKit/
│       ├── AppGroup.swift          App Group ID (read from Info.plist) + container URL
│       ├── SampleData.swift        Sample projects/tasks (now widget gallery preview only)
│       ├── Rollups.swift           PlannedRollup + DayRollup (plan vs actual, billable/overhead)
│       ├── DayLoad.swift           Day load buckets by billable hours (week-view colors) + per-day helpers
│       ├── Models/
│       │   ├── Project.swift       Project tag: id, name, colorHex
│       │   ├── DobaTask.swift      Task + TaskStatus + TaskSource (named DobaTask
│       │   │                       to avoid clashing with Swift's Task)
│       │   ├── TimeEntry.swift     Worked interval (end==nil = running); source of actual hours
│       │   ├── Meeting.swift       Transient calendar event (from EKEvent; never stored)
│       │   ├── ParsedTask.swift    JSON contract for the Claude NL parser (Phase 4)
│       │   └── DobaData.swift      Root Codable doc + pure queries, carry-over, timer, NL import
│       └── Store/
│           └── DobaStore.swift     DobaStorage (JSON load/save) + DobaStore (observable)
│
├── DobaApp/                        Menu-bar app (primary surface). Owns all writes.
│   ├── Info.plist                  LSUIElement agent app (no Dock icon)
│   ├── DobaApp.entitlements        Sandbox + App Group + calendars + network (Claude API)
│   ├── Assets.xcassets/            App icon (AppIcon — gradient squircle + checklist)
│   └── Sources/
│       ├── DobaApp.swift           @main MenuBarExtra scene; launch carry-over + diagnostics
│       ├── TodayView.swift         Panel: Day/Week modes, date nav, week load strip, quick-add, timeline, summary
│       ├── TaskDetailEditor.swift  In-panel editor: project/hours/time/billable + inline project create
│       ├── CalendarService.swift   EventKit read-only bridge: auth + today's meetings (EKEvent → Meeting)
│       ├── ClaudeClient.swift      Claude API call (raw HTTPS) → ParsedTask[]; JSON-only prompt
│       ├── Keychain.swift          Store/read the Anthropic API key (Keychain, never in repo)
│       ├── SettingsView.swift      In-panel settings: rate, currency, manage-projects, API key
│       ├── ProjectsView.swift      Manage projects: rename / recolor / per-project rate / delete
│       ├── CompleteTaskView.swift  Log-time-on-complete; rolls the remainder to tomorrow
│       ├── GlobalHotKey.swift      AppDelegate: ⌃⌥D quick-capture panel + notification setup
│       └── TimerAlert.swift        Per-task countdown → banner+sound when the timer hits the estimate
│
├── DobaWidget/                     WidgetKit extension (read-only desktop widget)
│   ├── Info.plist                  WidgetKit extension point
│   ├── DobaWidget.entitlements     App Group + sandbox (extensions are sandboxed)
│   └── Sources/
│       └── DobaWidget.swift        @main bundle + provider + entry view (reads store)
│
└── docs/
    ├── index.html                  Landing page (served by GitHub Pages from /docs)
    ├── PROJECT_STRUCTURE.md         This file
    ├── ARCHITECTURE.md              Modules, data flow
    ├── DATA_MODEL.md                v1 model + range/expansion trade-off
    ├── USING.md                     How to use the app day to day
    └── SETUP.md                     Build & run (one-time)
```
