# Doba — Worklog

Append-only, dated. Newest entries at the bottom of each day. After every
meaningful change: what was done, which files, what's left.

---

## 2026-06-23 — Phase 0: Scaffold

**Done:**

- Established the three-target layout and the XcodeGen workflow.
  - `project.yml` — source of truth for `Doba.xcodeproj` (generated, gitignored).
  - `DobaKit` is a **framework** (not an SPM package — decided mid-scaffold; see
    DECISIONS), embedded by the app, linked by the widget.
- **DobaKit** (`DobaKit/Sources/DobaKit/`):
  - `AppGroup.swift` — single source for the App Group ID + container URL.
  - `Models/Project.swift`, `Models/DobaTask.swift`, `Models/TimeEntry.swift`,
    `Models/DobaData.swift` (root Codable doc + pure day/project queries).
  - `Store/DobaStore.swift` — `DobaStorage` (nonisolated JSON load/save, App
    Group container with Application Support fallback) + `@MainActor DobaStore`
    (observable, seeds sample data on first run, `toggleStatus` smoke test).
  - `SampleData.swift` — Phase 0 dummy projects/tasks.
- **DobaApp** (`DobaApp/Sources/`):
  - `DobaApp.swift` — `MenuBarExtra` agent app (`LSUIElement`), `.window` style.
  - `TodayView.swift` — today's tasks split into Timeline + Floating; checkbox
    toggles status and calls `WidgetCenter.reloadAllTimelines()`.
  - `Info.plist`, `DobaApp.entitlements` (App Group; app intentionally not
    sandboxed — see DECISIONS).
- **DobaWidget** (`DobaWidget/Sources/`):
  - `DobaWidget.swift` — `@main` WidgetBundle + `StaticConfiguration` +
    `TimelineProvider` reading the shared store (sample-data fallback), entry
    view listing today's tasks. Read-only; App Intents interactivity is Phase 5.
  - `Info.plist` (WidgetKit extension point), `DobaWidget.entitlements`.
- Docs: ROADMAP, PROJECT_STRUCTURE, ARCHITECTURE, DATA_MODEL, DECISIONS, SETUP
  (manual Xcode checklist), this WORKLOG; `CLAUDE.md`; `.gitignore`.

**Validation (no full Xcode on this machine — Command Line Tools only):**

- `xcodegen generate` succeeds — spec is valid.
- `swiftc -typecheck` against the macOS SDK: DobaKit module, DobaApp, and
  DobaWidget (`-parse-as-library`) all clean. Not yet a real `xcodebuild`.

**Left for the author (manual, can't be automated):** see `docs/SETUP.md` —
install full Xcode, set signing team, verify App Group provisioning + widget
embedding, first build & run.

**Suggested commit boundary:** one commit, "Phase 0: scaffold (3 targets, store,
menu bar + widget skeletons, docs)".

---

## 2026-06-24 — Phase 0 review: fix app↔widget data sharing

Review found: menu bar showed **no** tasks, widget showed the 3 sample tasks —
i.e. they were reading different stores, and the widget's sample fallback hid it.

**Root cause:** the main app was **not sandboxed**, but App Group containers are
a sandbox construct and the widget extension is always sandboxed — so the two
processes didn't resolve the same `containerURL`. (Reverses the original D12.)

**Changes:**

- `DobaApp/DobaApp.entitlements` — **enabled App Sandbox** (kept App Group) so
  the app and widget share one container. (DECISIONS D12 revised.)
- `DobaKit/Store/DobaStore.swift`:
  - `DobaStorage.logDiagnostics(context:)` — logs the resolved App Group
    container + file path per process (subsystem `com.andreyrozumny.Doba`), so
    DobaApp vs DobaWidget paths can be compared in Console.app.
  - `DobaStore.init` no longer seeds implicitly (pure load). Added explicit
    **app-only** `seedSampleDataIfEmpty()` (logs diagnostics, seeds the shared
    store only when empty) and a `reload()`.
- `DobaApp/Sources/DobaApp.swift` — on launch: `seedSampleDataIfEmpty()` then
  `WidgetCenter.reloadAllTimelines()`.
- `DobaWidget/Sources/DobaWidget.swift` — `getSnapshot`/`getTimeline` now read
  the **real** shared store with **no sample fallback** (empty ⇒ shows empty, so
  broken sharing is visible); `placeholder(in:)` keeps sample. (DECISIONS D15.)
- Docs: DECISIONS (D12 revised, D15 added), SETUP (sandbox + Console.app
  verification + clean-slate), PROJECT_STRUCTURE.

**Validation:** `swiftc -emit-module`/`-typecheck` at `-swift-version 5` for
DobaKit / DobaApp / DobaWidget — all clean. (`xcodegen generate` re-run after the
entitlement change is in the manual steps; still no full `xcodebuild` here.)

**Expected after rerun:** both menu bar and widget show the same 3 tasks; ticking
in the app reflects in the widget; Console shows identical `container=` paths
with `sharing=true`.

---

## 2026-06-24 — Phase 1 (start): store core + carry-over

Context noted: development stays on a **free** Apple account for the coming
months; only the widget (Phase 5) needs the App Group, so this doesn't block the
menu-bar work. Architecture kept release-ready.

**Done (DobaKit — pure logic, runnable without full Xcode):**

- `DobaData.carryOverUnfinished(asOf:)` — moves unfinished past-day tasks to
  today, flags `isCarriedOver`, keeps time-bound tasks on the timeline (slot
  shifted to today's date); leaves `done` tasks + `TimeEntry`s on their date;
  idempotent within a day. (DECISIONS D16.)
- `DobaStore` mutations: `addTask` / `updateTask` / `deleteTask` /
  `toggleStatus`, `addProject` / `updateProject` / `deleteProject` (deleting a
  project untags its tasks rather than deleting them), and
  `carryOverUnfinished()` wrapper. Replaced the Phase-0 "smoke test" framing.
- `DobaApp.init` launch sequence: carry-over → seed-if-empty → reload widget.

**Validation:** built DobaKit + a behavioral test harness with `swiftc` and
**ran** it — 10/10 checks pass (carry-over count, done-task untouched, slot
preserved at 10:30, idempotency, timeline ordering, JSON round-trip). Plus
`-typecheck` clean for all three targets at `-swift-version 5`.

**Left (next):** the menu-bar **UI** — task add/edit form, project create/
assign/color, wiring CRUD into the today-view. Paused here for a UX decision on
how quick-add should work in the menu-bar panel.

**Suggested commit boundary:** "Phase 1 core: store CRUD + carry-over (tested)".

---

## 2026-06-24 — Phase 1 (cont.): menu-bar UI

UX chosen: **hybrid** quick-add + per-row detail editor.

**Done:**

- `DobaApp/Sources/TodayView.swift` — rewritten: one-line **quick-add**
  (title → floating task, Enter), Timeline + Floating sections, each row with a
  checkbox, metadata badges (project color, hours, billable, carried-over) and a
  **pencil** that opens the editor. Editor is shown by swapping panel content
  (sheets/popovers are awkward in `MenuBarExtra`). Empty state via
  `ContentUnavailableView`. Every mutation calls `reloadAllTimelines()`.
- `DobaApp/Sources/TaskDetailEditor.swift` — new in-panel editor for the four
  axes: title, **project** (picker + inline create with a color swatch),
  **hours** (parsed text), **scheduled time** (toggle + `DatePicker`, off =
  floating), **billable**. Edits a local `draft`; Save/Delete write through the
  store, Cancel discards. Includes a small preset color palette.
- `DobaKit/Store/DobaStore.swift` — removed Phase-0 `seedSampleDataIfEmpty`;
  `DobaApp.init` now does diagnostics log + carry-over only. `SampleData` is now
  used solely by the widget's gallery placeholder.

**Validation:** `-typecheck` clean for DobaKit / DobaApp / DobaWidget at
`-swift-version 5`; `xcodegen generate` re-run (new editor file picked up). No
full `xcodebuild` here — needs the author's Xcode.

**Left for the author:** build & run; try quick-add, the pencil editor, project
create, time on/off, delete, and carry-over (make a task, leave it undone, relaunch
next day). This is the **Phase 1 review boundary** — stopping for review.

**Suggested commit boundary:** "Phase 1 UI: quick-add + detail editor + projects".

---

## 2026-06-24 — Phase 2: Calendar (EventKit read-only) + planned rollup

**Done:**

- `DobaKit/Models/Meeting.swift` — transient calendar event (id/title/start/end
  + `hours`); never persisted. DobaKit stays EventKit-free.
- `DobaKit/Rollups.swift` — `PlannedRollup` + `DobaData.plannedRollup(on:meetings:)`:
  task `estimatedHours` by project (zero-hour groups omitted, hours-desc) +
  meeting hours + totals. Pure → **tested by running** (9/9: task/meeting/total
  hours, project ordering, untagged/zero handling, empty day).
- `DobaApp/Sources/CalendarService.swift` — `@MainActor` EventKit bridge:
  `authorizationStatus`, `requestFullAccessToEvents`, fetch today's non-all-day
  events → `[Meeting]`, refresh on `.EKEventStoreChanged`. Read-only; nothing
  stored.
- `DobaApp/Sources/TodayView.swift` — meetings merged into the **Timeline**
  (sorted with time-bound tasks; read-only `MeetingRow`), a **calendar banner**
  (connect button when undecided, "Settings" when off), and a **PLANNED** summary
  (total + per-project chips + meeting count/hours).
- Entitlement `com.apple.security.personal-information.calendars` +
  `NSCalendarsFullAccessUsageDescription`. (DECISIONS D17.)
- `DobaApp` injects `CalendarService` alongside the store.

**Validation:** rollup ran green (9/9); `-typecheck` clean for all three targets
at `-swift-version 5` (incl. the EventKit calls); `xcodegen generate` re-run.
EventKit auth/fetch itself needs the author's Mac (real calendar + permission).

**Left for the author:** build & run, click **Show calendar events**, grant
access, confirm today's meetings show on the timeline and feed the planned
summary. **Phase 2 review boundary — stopping.**

**Suggested commit boundary:** "Phase 2: EventKit read-only calendar + planned-hours rollup".

---

## 2026-06-24 — Phase 3: Timer & time tracking

**Done (DobaKit — pure, ran & tested: 15/15):**

- `DobaData` time tracking: `activeEntry`, `startTimer` (closes any other open
  entry — single active timer), `stopActiveTimer`, `addManualEntry`,
  `deleteTimeEntry`, derived `actualHours(forTaskID:asOf:)` (live for the running
  one), `entries(forTaskID:)`.
- `Rollups.swift`: `DayRollup` + `dayRollup(on:meetings:asOf:)` — planned (reuses
  `plannedRollup`) + actual hours today (entries started today, running ticked
  live) + billable/overhead split of both (tasks only; meetings separate).
  (DECISIONS D18.)
- `DobaStore`: `isTiming`, `toggleTimer`, `stopActiveTimer`, `addManualTime`,
  `deleteTimeEntry`.
- Test coverage: single-active enforcement + auto-close, manual add, live tick,
  delete, planned/actual + billable/overhead splits.

**Done (DobaApp):**

- `TodayView`: per-row **timer toggle** (play/stop) + live **actual-hours** badge;
  an **active-timer bar** (running task + `H:MM:SS` + stop); the list live-ticks
  via `TimelineView(.periodic(by: 1))` only while a timer runs; day summary now
  shows **PLANNED vs ACTUAL** and **Billable/Overhead** (actual/planned).
- `TaskDetailEditor`: **Time** section — actual total, Start/Stop, add manual
  time (hours → closed entry), and the task's entry list with per-entry delete.
  Renamed the estimate field label to "Estimate" to disambiguate from actuals.

**Validation:** rollup/timer ran green (15/15); `-typecheck` clean for all three
targets at `-swift-version 5`. No new files (only edits), so no project regen
needed. Full `xcodebuild`/live timing needs the author's Xcode.

**Left for the author:** build & run; start/stop timers (watch the bar tick),
add/delete manual time in the editor, confirm the PLANNED-vs-ACTUAL and
Billable/Overhead summary updates. **Phase 3 review boundary — stopping.**

**Suggested commit boundary:** "Phase 3: timer, derived actual hours, plan-vs-actual + billable/overhead".

---

## 2026-06-24 — Packaging: app icon + standalone deploy

User (a web dev, not an Xcode user) wanted a real app they can just launch, plus
a custom icon; Launchpad was showing two "Doba" entries (the `/Applications`
copy + the Xcode/DerivedData build copy).

- **Signing team baked into `project.yml`** (`DEVELOPMENT_TEAM = 4Y8L43845Q`,
  personal team) so `xcodegen generate` stops wiping the team each time. (D19.)
- **App icon added**: `DobaApp/Assets.xcassets/AppIcon.appiconset` (gradient
  squircle + white checklist glyph), generated via an AppKit script + `sips`.
  Wired in `project.yml` (asset catalog source + `ASSETCATALOG_COMPILER_APPICON_NAME`).
- **Built via `xcodebuild`** (full Xcode 26.5 is now installed) and copied the
  signed `Doba.app` to `/Applications`; verified `CFBundleIconName=AppIcon`.
- **De-duplicated Launchpad**: unregistered the DerivedData copies from
  LaunchServices, refreshed icon cache; only `/Applications/Doba.app` remains.

Guidance for the user is in `docs/USING.md` (launch from /Applications, not Xcode).

---

## 2026-06-24 — Phase 4: NL parsing (Claude API)

**Done (DobaKit — pure, tested 13/13):**

- `Models/ParsedTask.swift` — the JSON contract (`ParsedTask` + `ParsedTaskList`
  wrapper `{"tasks":[...]}`).
- `Project.palette` — shared preset colors (used by the parser + the editor).
- `DobaData.addParsedTasks(_:now:)` — resolve/create projects by name
  (case-insensitive), parse `yyyy-MM-dd` dates (→ today on miss) and `HH:mm`
  times (→ floating on miss), set `billable`, `source = .parsed`; ranges arrive
  as N objects. `DobaStore.importParsedTasks` wraps + persists.
- Tested: reuse vs create projects, range expansion, bad time/date fallbacks,
  empty-title skip, wrapper decode.

**Done (DobaApp):**

- `Keychain.swift` — store/read/clear the Anthropic API key (generic-password
  item; never in repo/store/logs).
- `ClaudeClient.swift` — raw `URLSession` call to `/v1/messages`
  (`claude-haiku-4-5-20251001`), JSON-only system prompt with today's date,
  defensive JSON extraction, typed `ParseError` messages. (DECISIONS D21.)
- `SettingsView.swift` — in-panel API-key field (SecureField → Keychain).
- `TodayView` — gear → Settings; quick-add row gains a **✨** button that parses
  the typed text via Claude (spinner while running, inline error on failure),
  Enter still does the plain quick-add.
- Entitlement `com.apple.security.network.client` for the outbound HTTPS call.

**Validation:** import logic ran green (13/13); `-typecheck` clean for all three
targets; `xcodebuild` BUILD SUCCEEDED; deployed to /Applications (network
entitlement verified in the signed app). The live API call itself needs the
author's key — can't be exercised here.

**Left for the author:** open settings (gear), paste your Anthropic API key,
then type e.g. *"подготовить эстимейт для Acme, 2ч, оплачиваемо"* and tap ✨.
**Phase 4 review boundary — stopping.**

**Suggested commit boundary:** "Phase 4: NL task parsing via Claude API (Keychain key, pure import)".

---

## 2026-06-24 — Widget investigation (empty widget) → free-account App Group limit

User: widget shows only the header, no tasks. Root-caused with a temp diagnostic
(`DobaStorage.writeDiagnostics`, called from `DobaWidgetBundle.init`):

1. **Debug build broke widget launch.** The appex contained
   `DobaWidget.debug.dylib` + `__preview.dylib` (Xcode's debug/preview shim);
   the extension crashed on launch when the system (chronod) ran it, so its code
   never executed. **Fix: build/deploy Release** — the widget then links DobaKit
   directly and launches. Going forward, standalone deploys use Release.
2. **App Group not provisioned for the extension (free account).** Once the
   Release widget launched, the diagnostic showed: `containerURL` resolves to the
   Group Container, `storeFileExists=true`, but `tasksRead=-1` and the write
   orphaned into the widget's own sandbox tmp — i.e. **no read/write access**.
   The `application-groups` entitlement is in both signatures but in **neither
   provisioning profile** (free accounts can't register app groups). The app
   works (owns its container); the sandboxed widget is denied.

**Conclusion:** the widget can't share data until a **paid** Apple Developer
account provisions the app group. No code workaround (App Groups are the only
app↔widget channel; widgets are always sandboxed). Widget parked; menu-bar app
is the product surface. The plumbing is correct, so a paid account → widget works
with no code change. (TEMP `writeDiagnostics` left in place; strip when the widget
is revisited.)

---

## 2026-06-24 — Phase 6 (start): Day/Week planner + archive + load colors

User wanted: see the planned week (per-day hours, incl. Claude's range splits),
today/tomorrow, an archive of past days, and day-load coloring by billable hours.

**Done (DobaKit — pure, tested 11/11):**

- `DayLoad.swift` — `DayLoad(billableHours:)` buckets (`full`≥8 / `partial`≥6 /
  `low`≥4 / `empty`<4) + `plannedBillableHours(on:)` / `plannedTaskHours(on:)`.

**Done (DobaApp):**

- `CalendarService` — now loads a **window** (−31…+14 days) into
  `meetingsByDay`; `meetings(on:)` for any day (week strip + archive).
- `TodayView` — rebuilt as a panel with **Day/Week** segmented toggle:
  - **Day**: any `selectedDate` with ‹ › stepping (today/tomorrow/archive); date
    label taps to today; quick-add adds to the selected day; summary per day.
  - **Week**: today…+6 rows, each with a billable-load color bar (green/yellow/
    orange/red), `Xh billable · Yh total · N mtg`; tap a day → opens it.
- `TaskDetailEditor` — added a **Day** stepper to move a task to another day.
- (DECISIONS D22.)

**Validation:** DayLoad ran green (11/11); `-typecheck` clean all targets;
Release `xcodebuild` SUCCEEDED; deployed to /Applications. Look/feel needs the
author's eyes (can't render here).

**Left (Phase 6):** rates/earnings, global hotkey, project management/colors +
delete-project UI, recurring tasks. **Stopping for review of the planner.**

**Suggested commit boundary:** "Phase 6: Day/Week planner with billable-load colors + archive".

---

## 2026-06-24 — Phase 6 (cont.): earnings, 30-min floor, event→task, defer, done-sink

**Done (DobaKit — pure, tested 11/11):**

- `DobaData.hourlyRate` / `currency` (optional → old stores decode unchanged).
- `DobaData.minEntryHours = 0.5` + `effectiveHours(_:asOf:)`: closed entries
  bill ≥30 min, running ticks exact. Wired into `actualHours` + `dayRollup`.
  (DECISIONS D24.)
- `DobaTask.linkedEventID` (link a task to the calendar event it came from).
- `DobaData.shiftTask(id:byDays:)` (move a task, keeping its clock time).
- Tests: backward-compat decode, round-trips, shiftTask, the 30-min floor, and
  earnings math.

**Done (DobaApp):**

- `DobaStore`: `setEarnings(rate:currency:)`, `moveTask(_:byDays:)`.
- `SettingsView`: Hourly rate + currency fields (→ store); key section kept.
- `TodayView`:
  - earnings in the day summary (earned/projected) + a **week total** footer;
  - **+ task** on meeting rows → `convertMeeting` (dedup via `linkedEventID`);
  - per-row **→** = move to next day; **done tasks sink** in the floating pool.
- (DECISIONS D23 / D24 / D25.)

**Validation:** DobaKit ran green (11/11); `-typecheck` clean all targets;
Release `xcodebuild` SUCCEEDED; deployed. Visuals need the author's eyes.

**Left (Phase 6 ideas):** day capacity (events reduce the 8h target — the "exam
blocks 2h" case), per-project rates + project management UI, global hotkey,
recurring tasks. **Stopping for review.**

**Suggested commit boundary:** "Phase 6: earnings + 30-min floor + event→task + defer + done-sink".

---

## 2026-06-24 — Phase 6 (cont.): the "do all five" batch

User asked for all five backlog ideas at once.

**Done (DobaKit — pure, tested 14/14):**

- **Capacity colors** (D26): `DayLoad(billableHours:capacityHours:)` + `.blocked`;
  `dayCapacity = 8 − overhead − meetingHours`; `plannedOverheadHours`.
- **Per-project earnings** (D28): `Project.rate`; `rate(forTaskID:)`,
  `projectedEarnings(on:)`, `earnedEarnings(on:asOf:)` (global fallback).
- **Recurrence** (D27): `RecurrenceRule` + `recurrenceID` on `DobaTask`;
  `materializeRecurring(through:)` (idempotent, 2-week horizon); carry-over now
  skips recurring tasks.
- Tests: capacity buckets + math, per-project earnings, daily/weekdays
  materialization + idempotency, carry-over skip.

**Done (DobaApp):**

- `GlobalHotKey.swift`: `AppDelegate` (Carbon ⌃⌥D) + floating quick-capture panel.
- `ProjectsView.swift`: manage projects (name/color/rate/add/delete) via gear.
- Week strip + day dot use **capacity** colors over **non-converted** meetings.
- `TodayView`: capacity dot by the date; per-project earnings in day summary +
  week footer; **log-nudge** badge; `repeat` badge; **edit** tooltip; recurrence
  materialize on panel appear.
- `TaskDetailEditor`: **Repeat** picker (seeds `recurrenceID`, materializes on
  save); per-entry hours now show the 30-min-floored value.
- Removed the app-side temp `writeDiagnostics` call (widget's still present, parked).

**Validation:** DobaKit 14/14 green; `-typecheck` clean; Release SUCCEEDED;
deployed. **Needs the author's runtime check** — especially the global hotkey
(panel focus/registration can't be verified headless) and the projects/recurrence
screens.

**Suggested commit boundary:** "Phase 6: capacity colors + per-project rates + projects UI + recurrence + log-nudge + global hotkey".

---

## 2026-06-24 — Phase 6 (cont.): complete-with-time, defaults, smarter parse

**Done (DobaKit — pure, tested 13/13):**

- `completeTask(id:loggedHours:)` (D29): logs hours, then done if ≥ estimate, else
  reduces the estimate and rolls the task to tomorrow.
- Creation defaults (D30): `defaultEstimateHours = 0.5`; `ensureInternalProject()`;
  `addParsedTasks` now defaults missing estimate→0.5 and missing project→Internal.
- Tests: parse defaults, Internal reuse (case-insensitive), completeTask full +
  partial (reduce + move + cumulative finish).

**Done (DobaApp):**

- `CompleteTaskView.swift`: log-time step (planned pre-filled, ± steppers,
  "Planned" reset, explains the roll-to-tomorrow). Wired to the checkbox: todo→done
  opens it; done→todo is a plain toggle; the amber log-nudge badge opens it too.
- `DobaStore.addQuickTask` (defaults) used by quick-add + hotkey;
  `DobaStore.completeTask`.
- `ClaudeClient.parse` takes `knownProjects` and the system prompt matches
  references/aliases (e.g. "мойбиз"→"Helpmybiz") to existing names.
- Global-hotkey panel gained the **✨** button (parse path).
- Done items sink in the **timeline** too (was pool-only).

Note: projects already in the store (Internal, Helpmybiz, Libido 30, BTRIP 25,
In4People 25, Musictrade) — nothing to seed.

**Validation:** DobaKit 13/13 green; `-typecheck` clean; Release SUCCEEDED;
deployed. Runtime check still on the author (esp. the complete-with-time UX).

**Suggested commit boundary:** "Phase 6: complete-with-time + creation defaults + project-aware parsing + hotkey ✨".

---

## 2026-06-24 — Phase 6 (cont.): format hint, floating→timeline, tooltips

- `DobaData.scheduleOnTimeline(id:at:)` (tested 6/6) — sets today + next 30-min
  slot; floating rows get a **calendar-clock** button to use it.
- Quick-add placeholder now teaches the ✨ format; full guide in a hover `.help`;
  hotkey placeholder matched. **Tooltips** (`.help`) on every row button incl. the
  checkbox. (DECISIONS D31.)
- `-typecheck` clean; Release SUCCEEDED; deployed.

**Suggested commit boundary:** "Phase 6: floating→timeline button + quick-add format hint + tooltips".

---

## 2026-06-24 — Phase 6 (cont.): split-on-partial + weekly billable target

Two user-driven corrections (tested 16/16):

- **Partial completion now splits** instead of moving the task (D29 updated):
  logging 8h of an 80h task leaves an **8h-done record today** and a **72h
  continuation tomorrow** (carried-over flag, keeps the slot). Full coverage or 0
  logged → done in place.
- **Weekly billable target** (D32): Week view switched to the **current Sun–Sat
  work week**; footer shows a progress bar toward **40h** (`weeklyBillableTargetHours`)
  with logged + earnings beneath.

`-typecheck` clean; Release SUCCEEDED; deployed. Also wrote `docs/PORTFOLIO.md`
(case study).

**Suggested commit boundary:** "Phase 6: split-on-partial completion + weekly 40h billable target".

---

## 2026-06-24 — Phase 6 (cont.): layered week bar, monthly pay period, week nav, Enter→Claude

Tested 6/6 (DobaKit: pay period + range billable sum):

- **`WeekBillableBar`** — single layered bar (outline / grey planned / green
  logged / pink over-target).
- **Monthly billable** over the **15th→15th pay period** (`payPeriod`,
  `actualBillableHours(from:to:)`), `Monthly X/160h`. Constants
  `weeklyBillableTargetHours = 40`, `monthlyBillableTargetHours = 160`.
- **Week navigation** (`weekOffset`) — ‹ this/next/last week ›.
- **Enter → Claude** in the panel and the hotkey (hotkey falls back to quick-add
  on parse failure). `addQuickTask` dropped from the panel (Enter now parses).
- (DECISIONS D33.)

`-typecheck` clean; Release SUCCEEDED; deployed.

**Suggested commit boundary:** "Phase 6: layered week bar + monthly pay-period total + week nav + Enter-to-Claude".

---

## 2026-06-24 — Phase 6 (cont.): billable defaults to project rate + data fix

User noticed today's billable didn't match reality. Root cause (from inspecting
the store): "AD-26 40ч (In4People)" was **non-billable** and two done tasks
(AD-26, btrip) had **0h logged** — completed before the time-log dialog existed.

- **Billable-by-rate** (D34, tested): `projectIsBillable(_:)`; `addParsedTasks`
  inherits billable from the project's rate; the editor re-derives it on project
  change.
- **Live-store one-off fix** (user-approved): marked AD-26 billable, logged 40h +
  btrip 4h dated today → day billable actual = 44h. (Patched the JSON with the app
  closed, then relaunched.)

Note: the day summary's **total** ACTUAL now reads high (it sums all logged time
incl. the backfill); the meaningful figure is the green billable bar / billable
line. `-typecheck` clean; Release SUCCEEDED; deployed.

(Shell got flaky reading the App Group container during verification — the patch
script's own output confirmed the write; not a data problem.)

**Suggested commit boundary:** "Phase 6: billable inherits project rate".

---

## 2026-06-25 — Incident + fix: empty panel after a transient load glitch

User opened the app on a new day and saw **no tasks** (yesterday + today blank).
Read the store file directly: **fully intact** (14 tasks, 10 entries) — a display
issue, not data loss. Restarting the app (reloads from disk) fixed it. Backed the
store up to scratchpad as a precaution.

Root cause: the App Group read can intermittently fail at launch; `DobaStore` fell
back to `.empty`, and the next mutation would have persisted empty over the real
file. **Data-safety guards added (D35):** `loadFailed` flag blocks saves after a
failed load; `reload()` never drops to empty on a read error; panel `reload()`s on
appear to self-heal; `save` refuses empty-over-non-empty; a banner prompts restart.

`-typecheck` clean; Release SUCCEEDED; deployed. Verified live store still 275
lines / 14 tasks / 10 entries after redeploy.

**Suggested commit boundary:** "Guard against data loss from a transient empty store load (D35)".

---

## 2026-06-25 — Store off App Group + per-task countdown alert

- **Store relocated** (D36): `storeDirectory()` now → the app's Application Support
  (no App Group). `migrateFromAppGroupIfNeeded()` copies old data on first launch;
  also migrated the live store manually (App Group → `~/Library/Containers/
  com.andreyrozumny.Doba/Data/Library/Application Support/Doba/doba.json`), old
  App Group file kept as backup. Verified: 15 tasks / 10 entries in the new path.
- **Countdown alert** (D37): `TimerAlert.swift` — starting a task timer schedules a
  banner+sound notification for when the running time hits the estimate; synced at
  toggle sites + panel appear. `AppDelegate` requests notification auth + presents
  alerts while active.

`-typecheck` clean; Release SUCCEEDED; deployed. (Author: grant the notification
permission on first prompt; start a timer on an estimated task to test the alert.)

**Suggested commit boundary:** "Store in Application Support (off App Group) + per-task countdown alert".

---

## 2026-06-25 — Billable/overhead everywhere + week/month progress (D38)

User wanted billable vs non-billable surfaced consistently and flagged two bugs
(Planned 44 / Actual 69.5 mixed buckets; month showing 132h).

**Done (DobaKit — pure, tested 7/7):** `actualHours(from:to:billable:)` (+ overhead
variant), `autoStopStaleTimer(maxHours:)` (caps >12h runaway timers).

**Done (DobaApp):**
- Day summary → `ПЛАН X$/Yh` + `ФАКТ X$/Yh` (green $ billable / muted overhead);
  dropped the combined PLANNED/ACTUAL + `summaryStat`.
- Week rows → `billable$ / overhead`; color via `dayLoad` (past=logged,
  today/future=planned, vs 8h daily share).
- Week footer → week billable/overhead (planned+tracked) + 40h bar; **month 15→15**
  billable/overhead + 160h bar with a **pace tick** (carries surplus across weeks).
- Live timer badge → **H:MM:SS** (was decimal); `autoStopStaleTimer` on panel appear.
- (DECISIONS D38.)

**Data fix:** 132h was real math over inflated entries (40h left-running sessions +
my duplicate backfill). Rebuilt the live store's billable log to 44.5h / 3 tasks.
**Verified:** week & month billable = 44.5h, overhead 20.25h, 3 billable tasks.

`-typecheck` clean; Release SUCCEEDED; deployed. (Note: a timer is currently running
on a non-billable task — overhead ticks live; auto-stops if left >12h.)

**Suggested commit boundary:** "Billable/overhead split everywhere + week/month progress bars + H:MM:SS timer + runaway-timer guard".

---

## 2026-06-25 — Billable enforcement (D39) + timer burndown (D40)

User: a BTRIP task (rated project) came out non-billable; and stopping a timer
should log + reduce the estimate.

**Billable enforcement (D39, tested 6/6):** rated project now *wins* over the
parser's billable guess; `normalizeBillableFromProjects()` sweeps the store and runs
at **launch** (`DobaApp.init`), on project update, and after import; editor toggle
disabled when the project has a rate. Verified: 0 rated-project-but-non-billable
tasks after relaunch (fixed BTRIP "Отображение окна витрати" + Libido).

**Timer burndown (D40, tested 9/9):** `stopActiveTimer` logs the worked time AND
subtracts it from the task's estimate (floored at 0), task stays todo. One active
timer at a time (start another → auto-stops & logs the first). `TimerAlert` counts
only the current session vs the remaining estimate; row badge shows the session
H:MM:SS (was total).

`-typecheck` clean; Release SUCCEEDED; deployed.

**Suggested commit boundary:** "Enforce rated-project billable + timer burndown of the estimate".

---

## 2026-06-25 — Meeting→Claude, timeline↔floating, drag-reorder, meeting badge (D41)

- **Meeting → task via Claude:** `convertMeeting` now parses the title (known projects)
  → project + billable; keeps the meeting's time/duration/link. New
  `DobaStore.addMeetingTask` + `DobaData.resolveOrCreateProject` (also refactored
  `addParsedTasks` to use it).
- **Meeting badge:** converted meeting stays hidden (dedup, no wasted space); the task
  shows a blue **calendar badge** so it still reads as a meeting.
- **Timeline ↔ floating:** added "→ floating" (`moveToFloating`) on time-bound rows,
  complementing "→ timeline" on floating rows.
- **Drag-reorder floating:** `DobaTask.sortIndex` + `setFloatingOrder`; rows are
  `.draggable`/`.dropDestination`; pool sorts by sortIndex (done still sinks).

`-typecheck` clean; Release SUCCEEDED; deployed. (Drag-and-drop + the async meeting
conversion need the author's runtime check.)

**Suggested commit boundary:** "Meeting→task via Claude + meeting badge + timeline↔floating + drag-reorder floating".

---

## 2026-06-25 — Parallel timers, auto-stop, minute logging, Month tab; reorder dropped

- **Reorder dropped** (user): removed `sortIndex`, `setFloatingOrder`, List/.onMove,
  ▲▼ buttons; floating pool back to `createdAt` order (D41 updated). DnD can't work
  in the MenuBarExtra popover.
- **Parallel timers** (D42, tested 19/19): `startTimer` doesn't stop others;
  `runningEntries`/`isRunning`/`stopTimer(taskID:)`/`stopAllTimers`. UI shows a live
  per-task session H:MM:SS; `dayContainer` ticks if any timer runs.
- **Auto-stop at the estimate + alert:** `TimerScheduler` (renamed from `TimerAlert`)
  — per running task a UN notification + an in-app `DispatchWorkItem` that stops it;
  re-synced on every change and at launch. `autoStopStaleTimer` caps all >12h.
- **Minute-precise logging — D24 superseded:** `effectiveHours` rounds to the nearest
  minute (≥30s up), no 30-min floor; burndown subtracts that.
- **Month tab** (D43): Day/Week/**Month** — pay-period report (billable/160h, earned,
  total hours, overhead, per-project), period-navigable. `periodReport`/`PeriodReport`.
- **Data cleanup** (user-directed): deleted the stray ~0 Fiver entry; moved
  "complete btrip 92" → Internal (non-billable); set "Разобраться с ошибкой" = 3h Wed
  + 3h Thu; "Doba" = 8h Wed. Verified week/month = 41.6h billable / 26h overhead.

`-typecheck` clean all targets; Release SUCCEEDED; deployed.

**Suggested commit boundary:** "Parallel timers + auto-stop at estimate + minute-precise logging + Month report tab".

---

## 2026-06-25 — Edit-via-title; Phase 6 paused for review

- Removed the per-row pencil button; **tapping the task title** now opens the editor
  (cleaner rows).
- User is happy with the current state and **paused Phase 6** ("пока на этом хватит,
  может вернёмся"). Docs (ROADMAP + WORKLOG + DECISIONS D1–D43) brought current.
- Author asked for a commit on `main` (no push — they push via GitKraken). This is a
  one-off override of the usual "manual git only" rule, at the author's explicit
  request; committed the session's work, did **not** push.

**Suggested commit boundary:** "Phase 6: tap-title to edit; docs current".

---

## 2026-06-24 — Bugfix: empty task list + empty widget

User reported: tasks don't appear in the menu bar, widget empty — but "Planned 6h"
showed. Inspected the store: **7 tasks present** (3 leftover samples + 4 the user
added), all scheduled for today (the `…T21:00:00Z` values are local midnight in
EEST/UTC+3 — adding/saving works fine). Two real bugs:

- **Menu-bar list collapsed to ~0 height.** `ScrollView` inside a `MenuBarExtra`
  window has no intrinsic height and shrinks to nothing, so rows were invisible
  while the (non-scrolling) summary still showed. Fix: fixed panel size
  `.frame(width: 360, height: 520)` and let the scroll region fill via
  `maxHeight: .infinity`. (DECISIONS D20.)
- **Widget App Group was `$(TeamIdentifierPrefix)`** (got mangled via Xcode's
  capabilities UI), so the widget read a different/invalid container → empty.
  Restored to `group.com.andreyrozumny.Doba` to match the app.

Also added carry-over to the panel's `onAppear` (rolls tasks to today when opened
on a new day, not only at launch). App Group **does** provision on the free
account (store lives in `~/Library/Group Containers/group.com.andreyrozumny.Doba/`).
Rebuilt + redeployed to /Applications; de-duplicated the build copy again.

Note: 3 sample tasks (Acme…, Update personal site) still linger in the store from
early seeding — user can delete them in-app, or we wipe on request.
