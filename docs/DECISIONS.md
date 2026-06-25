# Doba — Decisions (ADR-lite)

Short records of non-trivial decisions and **why**. Newest at the bottom.
Anything here is settled — don't relitigate without a new entry superseding it.

---

### D1 — Native SwiftUI, not web/Tauri/Electron
A macOS-only personal tool wants tight OS integration (menu bar, interactive
widget, EventKit, dictation) and zero runtime baggage. Web stacks fight all of
that. **Settled.**

### D2 — Mac-only; no sync, no backend, no Vercel
Single user, single machine. No iPhone target, no server, no remote DB. Removes
auth, sync conflict, and hosting complexity entirely. **Settled.**

### D3 — Storage = one local JSON file via a thin `Codable` store
Data volume is tiny. A single human-readable JSON file in the App Group
container is predictable, inspectable, and trivial to debug — ideal for a first
Swift project. **SwiftData is a v2 candidate, not now.** The JSON is written
pretty-printed with sorted keys and ISO-8601 dates specifically so it's
diff-able and eyeball-able on disk.

### D4 — Calendar = EventKit, read-only; events never stored
Google Calendar is already synced into macOS Calendar.app. We read `EKEvent`s
and merge them into the today-view on the fly. No Google API / OAuth / storage.
**Settled.**

### D5 — NL parsing = Claude API
`claude-haiku-4-5-20251001` (cheap, sufficient); escalate to `claude-sonnet-4-6`
only if range parsing is weak. The system prompt forces **JSON-only** output (no
preamble, no code fences); we parse defensively. **Settled.**

### D6 — UI strictly native macOS HIG
System materials/vibrancy, SF Symbols, standard controls, `MenuBarExtra` /
WidgetKit conventions. No custom controls, no web layout patterns. **Settled.**

### D7 — Secrets never in the repo
The Claude API key lives in Keychain or a gitignored config — never hardcoded,
never committed. `.gitignore` pre-blocks common secret filenames. **Settled.**

### D8 — Three targets: DobaApp / DobaWidget / DobaKit
Shared core in DobaKit so the menu bar and widget don't duplicate models/store/
logic. **Settled.**

### D9 — Ranged tasks expand into N atomic `DobaTask`s (one per day)
A multi-day task becomes one task per day, each with its own `estimatedHours`.
Keeps rollup, check-off, carry-over, and hour accounting trivially per-day. Cost:
duplicated title across days. **Rejected (v2 candidate):** a `PlannedBlock` +
on-the-fly expansion — more normalized but pushes expansion onto every consumer.

---

### D10 — DobaKit is a framework target, not a Swift Package *(decided during Phase 0)*
Initially planned as a local SwiftPM package (static link → no embedding). Two
things changed the call:
1. This machine's Command Line Tools has a **broken `PackageDescription`** (its
   `.swiftinterface` declares a `Package.init` overload whose symbol is missing
   from the dylib), so SwiftPM manifest evaluation fails locally — I couldn't
   validate a package at all.
2. A framework target lets `xcodegen generate` run and be validated locally now,
   keeps everything in **one** project (no separate package-resolution moving
   part — gentler for a first Swift project), and the framework↔extension
   `@rpath` sharing is the standard, well-trodden setup — which is exactly the
   "embedding" the author already planned to verify in Xcode.

Trade-off accepted: the app embeds DobaKit and the widget links it via
`@rpath`; this is the one thing to confirm in Xcode (see `SETUP.md`).
Revisitable if SPM ever becomes clearly preferable.

### D11 — The task type is named `DobaTask`, not `Task` *(Phase 0)*
`Task` is Swift Concurrency's type. Naming our model `Task` would shadow it
across the whole app and produce confusing errors. `DobaTask` is unambiguous.

### D12 — Both targets are sandboxed *(Phase 0; revised during Phase 0 review)*
**Original call:** leave the main app un-sandboxed (personal/never-distributed →
full calendar + network access with no per-feature entitlements).

**Why it was reversed:** App Group containers are a **sandbox construct**. The
widget extension is *always* sandboxed (OS-enforced for `.appex`), and a
non-sandboxed app does **not** reliably resolve the same
`containerURL(forSecurityApplicationGroupIdentifier:)` path — so the app and
widget ended up reading different files (app showed empty, widget fell back to
sample). Since the shared App Group store is the core mechanism of this app, the
app must be sandboxed too for a symmetric, matching container.

**Now:** `com.apple.security.app-sandbox` is enabled on both targets, plus the
App Group on both. Cost: later phases add the entitlements they need —
`personal-information.calendars` (Phase 2) and `network.client` (Phase 4). These
are one-line entitlement additions, tracked in the ROADMAP.

*Diagnostics:* `DobaStorage.logDiagnostics(context:)` logs the resolved
container path from each process (subsystem `com.andreyrozumny.Doba`) so the two
can be compared in Console.app — see `docs/SETUP.md`.

### D13 — Swift 5 language mode for now *(Phase 0)*
`SWIFT_VERSION = 5.0`. Swift 6's strict concurrency adds friction that isn't
worth it on a first Swift project at this stage. Moving to Swift 6 mode is a
deliberate later step, not an accident.

### D14 — XcodeGen; `project.yml` committed, `.xcodeproj` gitignored *(Phase 0)*
The project is config-as-code (like `package.json`): regenerable, diffable,
transparent. `Doba.xcodeproj` is a build artifact — regenerate with
`xcodegen generate`, never hand-edit in Xcode (lost on regen). Signing &
Capabilities is the exception: its state lives in the committed `.entitlements`
files.

### D15 — App seeds the shared store; widget never falls back to sample at runtime *(Phase 0)*
Seeding is an **explicit, app-only** step (`DobaStore.seedSampleDataIfEmpty()`,
called once at launch) — the store never seeds implicitly in `init`, so the
widget can build a read-only `DobaStore` with no side effects. The widget's
`placeholder(in:)` uses sample data (gallery/loading only); its `getSnapshot` /
`getTimeline` read the **real** shared store with **no sample fallback**. An
empty widget therefore signals broken sharing instead of hiding it behind sample
content — essential for honest Phase 0 verification. All of this sample-seeding
machinery is removed in Phase 1 when real task creation arrives.

### D16 — Carried-over time-bound tasks keep their slot (shifted to today) *(Phase 1)*
When carry-over moves an unfinished time-bound task to today, it **keeps the
task on the timeline** at the same clock time (e.g. yesterday 10:30 → today
10:30), rather than dropping it into the floating pool. Rationale: a missed
appointment-like task usually still wants a slot; you can always un-pin it
manually. `done` tasks and their `TimeEntry` history are never moved — actuals
stay on their own date. Carry-over is idempotent within a day (re-running moves
nothing). *Reconsider if "missed slot → floating" turns out to feel better in
use.*

### D17 — Calendar uses EventKit *full access* (read-only intent) *(Phase 2)*
On macOS 14+ there is no read-only EventKit authorization level — to *read*
events you must request **full access** (`requestFullAccessToEvents`); write-only
can't read. So the app requests full access, declares
`NSCalendarsFullAccessUsageDescription`, and carries the
`com.apple.security.personal-information.calendars` sandbox entitlement. We still
treat the calendar as **strictly read-only**: events are never written and never
stored — `EKEvent`s are mapped to a transient `Meeting` and merged into the
today-view for display + planned-hours rollup only. The widget gets none of this
(no EventKit, no entitlement). Access is requested via an explicit "Show calendar
events" button (no surprise prompt on launch); meetings refresh on panel open and
on `.EKEventStoreChanged`.

### D18 — Time tracking: intervals are the truth; derived actuals; tasks-only billable split *(Phase 3)*
- **`TimeEntry` intervals are the source of truth**; `actualHours` is always
  *derived* (sum of a task's entries, the running one ticked live to `now`) —
  never a stored field. Honest and editable.
- **One active timer app-wide**: starting a task's timer closes any other open
  entry first. "Active" = the entry with `end == nil` (no separate flag).
- **Manual correction** = adding a closed entry of N hours (forgot-to-start) or
  deleting an entry — not editing a magic total. Keeps everything reconcilable.
- **"Spent today"** in the day rollup = entries whose `start` is today (the
  running one ticked live), independent of the task's `scheduledDate`. So a
  carried-over task's *lifetime* actual can span days, but today's rollup only
  counts today's logged time.
- **Billable vs overhead splits tasks only.** Meetings carry no billable flag
  (they're calendar events) and are reported separately as meeting hours.
- **Live UI tick** via `TimelineView(.periodic(by: 1))`, enabled only while a
  timer runs and only while the panel is open — no background polling.

### D19 — Signing Team baked into `project.yml` *(packaging)*
`DEVELOPMENT_TEAM = 4Y8L43845Q` (personal team) lives in `project.yml` so
`xcodegen generate` no longer wipes the team on every regen (which had been
forcing a re-set in Xcode each time). A Team ID is not secret — it ships inside
every signed app — so committing it is fine. Signing stays **Automatic**. Daily
use is the standalone `/Applications/Doba.app` (built via `xcodebuild`), not the
Xcode-run copy, to avoid a duplicate Launchpad entry.

### D20 — MenuBarExtra panel needs a fixed height *(bugfix)*
A `ScrollView` inside a `MenuBarExtra(.window)` has no intrinsic height and
collapses to ~0, hiding its content (symptom: tasks invisible while the summary
still rendered). The panel therefore sets an explicit
`.frame(width: 360, height: 520)`, and the scroll region fills with
`maxHeight: .infinity`. Any future scrollable menu-bar surface must be given a
concrete height the same way. (Aside: dates are stored ISO-8601 in UTC, so local
midnight appears as the previous day's date with a `Z` — not a bug.)

### D21 — NL parsing: raw-HTTPS Claude call, Keychain key, pure import *(Phase 4)*
- **No Swift SDK exists for Claude**, so `ClaudeClient` calls `POST
  https://api.anthropic.com/v1/messages` directly via `URLSession`
  (`x-api-key`, `anthropic-version: 2023-06-01`). Model
  `claude-haiku-4-5-20251001` (cheap/sufficient; bump to `claude-sonnet-4-6` if
  range parsing is weak — one-line change).
- **JSON-only contract, parsed defensively.** The system prompt forces a
  `{"tasks":[...]}` object with a fixed per-task schema and injects today's
  date so the model can resolve ranges to absolute dates; the reply is
  fence-stripped and sliced to the JSON object before decoding. No structured-
  outputs API (kept simple; candidate hardening later).
- **Ranges → N atomic tasks** (consistent with D9): the model emits one task
  object per day; `DobaData.addParsedTasks` turns the decoded list into
  `DobaTask`s (resolving/creating projects by name, parsing times) — **pure and
  tested**, the network stays in the app.
- **API key in Keychain**, entered via an in-app settings field — never in the
  repo, the JSON store, logs, or chat. Sandbox gains
  `com.apple.security.network.client` for the outbound call.
- `source = .parsed` on created tasks; macOS dictation (`fn fn`) into the field
  works for free, so voice→text→parse needs no extra code.

### D22 — Day/Week planner: navigation, rolling week, billable-load colors *(Phase 6)*
- The panel has **Day** and **Week** modes (segmented toggle). Day mode renders
  any `selectedDate` with ‹ › stepping — this covers **today / tomorrow /
  archive** in one surface (no separate archive screen); the date label taps
  back to today. Quick-add adds to the *selected* day; the editor gained a
  **Day** stepper so a task can be moved to another day ("push to tomorrow").
- **Week = rolling today…+6** (not the calendar Mon–Sun), matching the user's
  "today + 6 days" framing and keeping it forward-looking. Each day is one row.
- **Day load color = planned *billable* hours** (the freelancer's signal), via
  `DayLoad` (DobaKit, tested): `full`≥8 green, `partial`≥6 yellow, `low`≥4
  orange, `empty`<4 red. Tunable in one place.
- **Per-day calendar:** `CalendarService` now loads a window (−31…+14 days),
  grouped by day, so the week strip and archived days show meetings without a
  per-render fetch. Color counts task hours only; meetings shown separately.
- Claude's range expansion (one task/day) naturally fills the week strip — a
  "6h/day Mon–Fri" parse shows up as load across five days.

### D23 — Earnings: single global rate + currency *(Phase 6)*
`hourlyRate: Double?` + `currency: String?` on `DobaData` (optional → old stores
decode unchanged), set in Settings. Earnings shown as **earned** (actual
billable hours × rate) and **projected** (planned billable × rate) in the day
summary, plus a **week total** footer. Started global (not per-project) for
simplicity — per-project rates are a later option (needs a project-management
screen). Hidden entirely when no rate is set.

### D24 — 30-minute minimum per worked interval *(Phase 6)*
`DobaData.minEntryHours = 0.5`. When summing actual hours
(`DobaData.effectiveHours`), a **closed** entry counts at least 30 minutes (a
5-minute timer session bills as 0.5h); a **running** entry ticks exact and
rounds up only when stopped. Manual entries are floored too. Stored data stays
truthful (real start/end) — the floor is applied at summation, so it flows into
the row badge, the day rollup, and earnings.

### D25 — Calendar event → task; done tasks sink *(Phase 6)*
- A meeting row has a **+ task** action that creates a `DobaTask` from the event
  (title, slot, duration as estimate, billable, `linkedEventID = event.id`); the
  timeline then hides that meeting (dedup by `linkedEventID`) and shows the
  checkable/timeable task instead. So calls get logged; a non-work event (e.g.
  an exam) is converted then toggled **non-billable** to block time without
  counting as earnings.
- **Done tasks sink** to the bottom of the floating pool (open ones stay in
  focus); the timeline keeps clock order.
- A per-row **→** button defers a task to the next day (mirrors the editor's Day
  stepper).

### D26 — Day load by *available capacity*, not absolute 8h *(Phase 6)*
`DayLoad(billableHours:capacityHours:)` colors by the ratio of billable hours to
the day's **available capacity** = `8 − overhead tasks − meeting hours`. So a day
with a 2h exam (overhead/blocker) needs only 6 billable hours to read green;
a fully-booked day with no capacity left is `.blocked` (grey). The week strip and
the dot by the day's date both use this. Meetings already converted to tasks are
excluded from the meeting-hours term (no double counting).

### D27 — Recurring tasks: materialize forward *(Phase 6)*
`RecurrenceRule` (daily/weekdays/weekly, nil = one-off) + `recurrenceID` (series
id) on `DobaTask`. At launch (and when the panel appears) `materializeRecurring`
generates missing instances from each series' latest instance up to a **2-week
horizon**, idempotently (skips days already present). Chosen over
"complete-and-recur" so the week view is pre-filled with upcoming standups.
Carry-over **skips** recurring tasks (the rule schedules them, not the roll-over),
so missed instances stay on their own day instead of piling onto today.

### D28 — Per-project rates, project management, log-nudge, global hotkey *(Phase 6)*
- **Per-project rate:** `Project.rate` overrides the global `hourlyRate` for that
  project's billable tasks; earnings sum per task via `rate(forTaskID:)`.
- **Projects screen** (gear → Manage projects): rename, recolor (cycle palette),
  set rate, add, delete — live bindings write straight to the store.
- **Log nudge:** a billable task whose slot/day has passed with **0 logged hours**
  shows an amber `exclamationmark.bubble` so calls don't go unlogged.
- **Global hotkey ⌃⌥D** (Carbon `RegisterEventHotKey`, no dependency / no
  Accessibility) pops a floating quick-capture panel that adds a task to today.
  Standalone-app concern: needs the **Release** build (Debug's launcher shim) and
  its behavior can only be verified at runtime.

### D29 — Complete a task by logging hours; roll the remainder *(Phase 6)*
Checking a todo task opens a **Log time** step (planned estimate pre-filled; the
user overwrites with what they actually worked / reported). `completeTask` logs
the hours, then: **logged ≥ estimate (or 0) → mark done in place**; **logged <
estimate → split**: today's task is marked **done** with its estimate set to the
hours worked (so the day keeps a "did Nh, done" record), and a fresh
**continuation** task carries the remainder (`estimate − logged`) to the **next
day** (todo, flagged carried-over). *Updated 2026-06-24 from the earlier
"reduce-and-move the same task" approach — a big task (80h, log 8h) now leaves an
8h-done record today and a 72h task tomorrow.* Un-checking a done task is a plain
toggle (no prompt). The amber "no time logged" badge is tappable and opens the
same step. **Done items sink to the bottom** of both the floating pool and the
timeline.

### D30 — Creation defaults + smarter parsing *(Phase 6)*
- **No duration given → 30-min estimate** (`DobaData.defaultEstimateHours`);
  **no project given → "Internal"** (`ensureInternalProject`, case-insensitive,
  created once). Applies to quick-add, the global hotkey, and parsed tasks.
- The NL parser is now given the **list of existing project names** and told to
  match references/abbreviations/transliterations to them (e.g. "мойбиз" →
  "Helpmybiz") and return the exact existing name — fewer duplicate projects.
- The **global-hotkey panel gained the ✨ Claude button** (same parse path as the
  main quick-add).

### D31 — Floating-by-default + format hint + "to timeline" *(Phase 6)*
- Tasks are **floating by default** (no slot); a clock time is what puts a task on
  the timeline. Floating rows get a **calendar-clock button** that schedules them
  onto today's timeline at the next 30-min slot (`scheduleOnTimeline`, tested).
- The quick-add placeholder teaches the ✨ format (title, project, hours, time),
  with the full guide in a hover `.help`. Every row button has a hover tooltip
  (`.help`): complete, to-timeline, timer, move-to-next-day, log, edit.

### D32 — Billable target is weekly (40h, Sun–Sat) *(Phase 6)*
The Week view now shows the **current work week (Sunday → Saturday)** containing
today (was a rolling today+6), and its footer tracks **billable hours toward a
40h weekly target** (`weeklyBillableTargetHours`) — planned billable as the
progress bar, actual logged + earnings beneath. Per-day capacity coloring (8h/day)
stays for each row; the headline billable metric is the week, per the user's
"show billable for the week, not the day".

### D33 — Weekly bar, monthly pay period, week nav, Enter→Claude *(Phase 6)*
- **One layered week bar** (`WeekBillableBar`): empty outline when nothing
  planned · **grey** = planned billable · **green** = logged over the grey · the
  whole bar turns **pink** once logged exceeds the 40h target. Hover shows the
  numbers.
- **Monthly billable over the pay period** — the **15th → 15th** (`payPeriod`,
  end-exclusive), target **160h** (4×40), shown as `Monthly X/160h`.
  `actualBillableHours(from:to:)` sums logged billable in a range (30-min floored).
  Both tested.
- **Week navigation** — the Week view got ‹ › (this / next / last week, or a date
  range) so Fri/Sat can preview next Sunday's plan.
- **Enter sends straight to Claude** in both quick-add fields (the user finds NL
  parsing the fastest path); the hotkey falls back to a plain quick-add if parsing
  fails so nothing is lost. The model lives behind one call site (`ClaudeClient`),
  so swapping in a cheaper provider later (e.g. **DeepSeek**) won't touch the UI.

### D34 — Billable defaults to the project's rate *(Phase 6)*
A task with no explicit billable flag inherits **billable = (its project's rate > 0)**
— client projects (In4People, Libido, BTRIP…) are billable, Internal / rate-0
projects are not. Applied in `addParsedTasks` (when the parse doesn't state it)
and in the editor's project picker (changing project re-derives billable;
override the toggle after if needed). `projectIsBillable(_:)` is the helper.
Motivated by a real case: "AD-26 40ч (In4People)" had been created non-billable,
so 40h of client work fell out of the billable totals. *(One-off data fix applied
to the live store: marked AD-26 billable and logged its 40h + btrip's 4h so the
day's billable actual = 44h — those tasks had been completed before time-logging
existed, hence 0h recorded.)*

### D35 — Never lose data to a transient empty load *(Phase 6, incident-driven)*
The App Group container can intermittently fail to read at launch (more so on the
free account — we saw the shell hang on that path). The store used to fall back to
`.empty` on **any** load failure, and the next mutation would `persist()` that
empty document over the real file → **data loss**. Guards added after a real
near-miss (a launch read glitch showed an empty panel; the data survived only
because the user didn't add anything before restarting):

1. `DobaStore.loadFailed` — set when an *existing* file throws on load; while true,
   `persist()` is a **no-op** (won't overwrite the real file).
2. `reload()` keeps the current in-memory data on a read error (never drops to
   empty) and clears `loadFailed` on a clean read.
3. The panel calls `reload()` on appear → a transient glitch **self-heals**.
4. `DobaStorage.save` refuses to overwrite a non-empty file with a fully empty doc.
5. A banner tells the user to restart while `loadFailed`.

A genuinely new install (no file) still starts empty and saves normally — the
guards only fire when a file *exists* but didn't load.

### D36 — Store moved out of the App Group to the app's own folder *(Phase 6)*
Storage no longer uses the App Group container; it lives in the app's
**Application Support** folder (inside the sandbox container). App Group reads
were unreliable on the free account (caused the empty-panel incident, D35) and
only the **parked** widget needed sharing. `migrateFromAppGroupIfNeeded()` copies
an old App Group file across on first launch; the live store was also migrated
manually, and the old App Group file is left untouched as a backup. The App Group
entitlement stays (harmless). Trade-off: the widget can't read this folder, so
widget sharing stays on hold until a paid account — at which point we'd move back
to a (then-working) App Group. The save guards (D35) still apply.

### D37 — Per-task countdown alert *(Phase 6)*
Starting a task's timer schedules a local notification (**banner + sound, over all
apps**) for when the running time reaches the task's **estimate** — `TimerAlert.sync`
keyed to the single active timer (`remaining = estimate − logged`). Stopping or
switching the timer cancels/reschedules it; the panel re-syncs on appear so it
survives a relaunch. Uses `UserNotifications` with a `willPresent` delegate so the
alert shows even while Doba is the active app. Needs the one-time notification
permission. Tasks without an estimate get no alert.

### D38 — Billable / non-billable everywhere; week & month progress; safeguards *(Phase 6)*
Reorganized all the numbers around the freelancer's real goal — **40h billable/week,
160h billable/month** — with a consistent **billable (green, $) / overhead (muted)**
split everywhere:
- **Day summary:** two rows — `ПЛАН  X$ / Yh overhead` and `ФАКТ  X$ / Yh` (was a
  single combined PLANNED/ACTUAL that mixed billable + overhead — the source of the
  "44 vs 69.5" confusion).
- **Week rows:** each day shows `billable$ / overhead`; **color** = billable toward
  the daily share (8h): **past** days by what was *logged*, today/future by what's
  *planned*.
- **Week footer:** week billable/overhead (planned + tracked) + a bar toward 40h; then
  **month (15→15)** billable/overhead + a bar toward 160h. The **month bar carries
  surplus across weeks** (it's cumulative) and has a **pace tick** marking where you
  should be by date — being ahead shows green past the tick.
- **Billable = project has a rate** (D34) stays the single source; manual override
  per task.
- **Live timer shows H:MM:SS** (was decimal hours — unreadable while running).
- **Runaway-timer safeguard** (D38): `autoStopStaleTimer` caps a timer left running
  >12h (called on panel appear) so a forgotten timer can't log 40h.
- **Data fix:** the 132h billable figure was real arithmetic over inflated entries
  (40h "left-running" timer sessions + a duplicate backfill). Rebuilt the live
  store's billable log to reality — 44.5h across 3 tasks (AD-26 40h + btrip 4h +
  Weekly 0.5h); overhead entries left as-is.

### D39 — Rated project ⇒ billable, enforced store-wide *(Phase 6)*
Bug: parsed tasks kept Claude's default `billable:false` even on a rated project,
because the project-rate fallback only fired when the parser returned `nil`. Fixes:
- `addParsedTasks` — the **rated project wins** (`billable = true` regardless of the
  parser's guess; only projectless / rate-0 tasks use the parser value).
- `normalizeBillableFromProjects()` sweeps the whole store (rated project →
  billable; other tasks left as-is so manual billable flags survive). Run **at app
  launch** (in `DobaApp.init`, not just panel-appear, since a menu-bar app's panel
  may never open), on **project update** (a rate change re-flows), and after import.
- The editor's **Billable toggle is disabled (forced on)** when the project has a
  rate. A per-task override for rated projects is intentionally deferred.

### D40 — Timer burns down the estimate *(Phase 6)*
Stopping a timer **logs the worked time AND subtracts it from the task's estimate**
(floored at 0), keeping the task **todo**. So "ran the timer" always means "worked
that time", and the estimate now reads as *remaining* work (a burndown). Only **one
timer runs at a time** — starting another auto-stops & logs the first; parallel
timers aren't allowed (you can't work two tasks at once, and it would double-count).
`TimerAlert` counts only the current session against the remaining estimate; the row
badge shows the current **session** as H:MM:SS.

### D41 — Meeting→task via Claude, timeline↔floating, drag-reorder *(Phase 6)*
- **Convert meeting → task through Claude:** `convertMeeting` runs the event title
  through the parser (with known projects) to attach the right **project + billable**
  (e.g. an exam → non-billable), keeping the meeting's time/duration/`linkedEventID`.
  `addMeetingTask` + the shared `resolveOrCreateProject`.
- **Meeting badge + dedup kept:** a converted meeting stays *hidden* from the timeline
  (no duplicate, saves space); the created task carries a **calendar badge** (blue)
  so it reads as a meeting/call and still reminds you.
- **Timeline ↔ floating both ways:** floating rows have "→ timeline" (sets the next
  half-hour slot); time-bound rows have "→ floating" (`moveToFloating`, clears the slot).
- **Manual reorder of the floating pool — dropped (user request, 2026-06-25).**
  Drag-and-drop does **not** work inside the `MenuBarExtra(.window)` popover — tried
  `.draggable`/`.dropDestination`, `onDrag`/`DropDelegate`, and `List`+`.onMove`; none
  initiate a drag there. A ▲▼-button fallback worked but the user decided the default
  `createdAt` order is fine, so the whole feature (the `sortIndex` field,
  `setFloatingOrder`, the List conversion, the buttons) was removed. The pool sorts by
  `createdAt` with done tasks sinking to the bottom.

### D42 — Parallel timers, auto-stop at the limit, minute-precise logging *(Phase 6)*
- **Parallel timers** (user runs several tasks at once): `startTimer` no longer
  stops others; `runningEntries` / `isRunning(taskID:)` / `stopTimer(taskID:)` /
  `stopAllTimers`. Stopping still **burns the worked time down from the estimate**
  (D40). Reverses the earlier one-timer-at-a-time rule.
- **Auto-stop at the limit:** when a running timer reaches the task's estimate it
  **stops itself and alerts**. `TimerScheduler` (was `TimerAlert`) keeps, per running
  task, a UN notification *and* an in-app `DispatchWorkItem` that calls `stopTimer`;
  re-synced on every change. The menu-bar app stays alive, so the in-app stop fires
  even with the panel closed. `autoStopStaleTimer` caps **all** timers running >12h.
- **Minute-precise logging — supersedes D24's 30-min minimum.** `effectiveHours`
  now logs the real duration **rounded to the nearest minute** (≥30s up), no floor;
  burndown subtracts that minute-rounded amount.

### D43 — Month report tab *(Phase 6)*
A third tab (**Day / Week / Month**) shows the pay-period (15→15) report: billable
progress to 160h, **money earned**, total hours, overhead, and a **per-project
breakdown** (hours + earnings). Navigable across periods (`monthOffset`). Backed by
`DobaData.periodReport(from:to:)` + `PeriodReport`.
