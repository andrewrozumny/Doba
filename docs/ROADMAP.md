# Doba — Roadmap

Phased build. **Stop at each phase boundary for review** before starting the
next. Tick boxes as work lands.

---

## Phase 0 — Scaffold ✅ (awaiting review)

- [x] Three-target layout: `DobaApp`, `DobaWidget`, `DobaKit`
- [x] XcodeGen `project.yml` (source of truth); `.xcodeproj` gitignored
- [x] App Group wired in both `.entitlements` files + `AppGroup.swift`
- [x] Data models: `Project`, `DobaTask`, `TimeEntry`, `DobaData`
- [x] Thin JSON store (`DobaStorage` / `DobaStore`) with App Group + fallback
- [x] Menu-bar skeleton (`MenuBarExtra`) showing today's sample tasks
- [x] Widget skeleton (read-only) showing today's sample tasks
- [x] All docs + `CLAUDE.md` + `.gitignore`
- [x] Typecheck-validated (DobaKit / DobaApp / DobaWidget) — no full build yet
- [x] App↔widget sharing wired: both sandboxed + App Group, app seeds the shared
      store, widget reads it (no sample masking), container diagnostics logged
- [ ] **Manual (author):** install full Xcode, set signing team, verify App
      Group + widget embedding, **confirm app & widget show the same data**
      (matching `container=` paths in Console) — see `docs/SETUP.md`

## Phase 1 — Core + menu bar

- [x] Real JSON store round-trip (App Group container, tested)
- [x] Models with all four axes exercised (time / plan / billable / status)
- [x] **Store core:** add / update / delete task, toggle status, project CRUD
- [x] Carry-over of unfinished past-day tasks (pure logic + launch wiring, tested)
- [x] `MenuBarExtra` today-view editing: timeline (time-bound) + floating pool
- [x] Add (quick-add) / edit (detail editor) / check / delete task **UI**
- [x] Projects **UI**: create (inline, with color) / assign / picker
- [x] Removed Phase-0 sample seeding (real creation replaces it)
- [ ] **Manual (author):** build & run, exercise add/edit/carry-over in the panel

## Phase 2 — Calendar ✅ (awaiting review)

- [x] EventKit access (full-access request — required to read; see DECISIONS D17)
- [x] Merge today's events into the timeline (display only, never stored)
- [x] **Planned** hours rollup: task `estimatedHours` by project + meeting hours (tested)
- [x] Calendar entitlement + `NSCalendarsFullAccessUsageDescription`
- [x] Permission banner (connect / denied → Settings); refresh on change
- [ ] **Manual (author):** build & run, grant calendar access, confirm meetings
      appear on the timeline and feed the planned summary

## Phase 3 — Timer & time tracking ✅ (awaiting review)

- [x] `TimeEntry` lifecycle; one active timer app-wide (start/stop on a task) — tested
- [x] Derive `actualHours` from entries (+ live tick for the running one) — tested
- [x] Manual hours correction (add closed entry / delete entry)
- [x] Rollups: **plan vs actual**, **billable vs overhead** (`DayRollup`, tested)
- [x] UI: per-row timer + live actual badge, active-timer bar, editor Time section,
      `TimelineView` live tick, planned-vs-actual + billable/overhead summary
- [ ] **Manual (author):** build & run; start/stop timers, add/delete manual time,
      watch the live tick and the summary update

## Phase 4 — NL parsing ✅ (awaiting review)

- [x] Text field + ✨ button → Claude API → structured tasks (single + ranged)
- [x] Fill project / hours / time / billable from natural language
- [x] JSON-only system prompt; defensive parsing (fence-strip + slice)
- [x] API key in Keychain via in-app settings; `network.client` entitlement added
- [x] Parse → `DobaTask` mapping is pure DobaKit logic (tested 13/13)
- [x] Dictation works for free via field focus (`fn fn`)
- [ ] **Manual (author):** paste API key in settings (gear), try a sentence + ✨

## Phase 5 — Widget

- [ ] Interactive widget: today's plan + checkbox toggles via App Intents
- [ ] Reads the shared store; reloads after app writes
- [ ] (Timer control stays in the menu bar for now)

## Phase 6 — Polish (extensive; paused for review 2026-06-25)

**Navigation & views**
- [x] **Day / Week / Month** tabs. Day = any date (today / tomorrow / archive via ‹ ›);
      Week = current Sun–Sat work week (‹ › across weeks); Month = pay-period report.
- [x] Per-day **calendar** merged into the Day timeline + Week strip (window load)
- [x] **Day color** by billable load toward 8h/day (past = logged, today/future = planned)
- [x] **Month report tab** (D43): pay-period 15→15 — earned, total/billable/overhead
      hours, per-project breakdown, period-navigable

**Billable / earnings (the core metric)**
- [x] **billable vs overhead split everywhere** (Day/Week/Month), $-marked (D38)
- [x] Targets: **40h billable/week** (Sun–Sat) + **160h/pay-period** (15→15) with
      progress bars; month bar carries surplus + pace tick
- [x] **Per-project rates** + global fallback; **project management** UI
- [x] **billable = project has a rate**, enforced store-wide (D34/D39)
- [x] **Rates + currency** in Settings; earned/projected money

**Tasks & timeline**
- [x] Move a task to another day (editor Day stepper + per-row → button)
- [x] **Timeline ↔ floating** both ways; **done tasks sink**; edit by **tapping the title**
- [x] **Calendar event → task via Claude** (project + billable) with a meeting badge
- [x] **Recurring tasks** (daily/weekdays/weekly, materialized 2 weeks ahead)
- [x] **Creation defaults:** no duration → 30 min; no project → Internal
- [x] **Smarter parsing:** parser gets existing project names + alias matching;
      Enter sends straight to Claude
- [x] **Complete-with-time:** checking a task logs hours; partial → splits a done
      record today + a continuation tomorrow
- [x] **Log nudge** on past billable tasks with no time logged (tappable)

**Time tracking**
- [x] **Parallel timers** — one per task, run several at once (D42)
- [x] **Minute-precise logging** (≥30s rounds up; no 30-min floor) — supersedes D24
- [x] **Burndown:** stopping a timer subtracts the worked time from the estimate (D40)
- [x] **Auto-stop at the estimate** + banner/sound alert; stale-timer cap >12h (D37/D42)
- [x] Live **H:MM:SS** session timer in the row

**Robustness / infra**
- [x] **Global hotkey ⌃⌥D** → quick-capture (+ ✨ Claude)
- [x] **Data-safety guards** (never overwrite with empty; self-heal load) — D35
- [x] **Store off the App Group** → app's own folder (+ migration) — D36

**Dropped / not done**
- [~] Manual drag-reorder of the floating pool — dropped; drag-and-drop doesn't work
      in the MenuBarExtra popover, and `createdAt` order is fine (D41)
- [ ] Start timer **from the widget** (needs the widget → paid account)
- [ ] Configurable hotkey / day-target / period bounds
- [ ] Possible SwiftData migration
- [ ] **Manual (author):** keep tweaking thresholds/colors to taste

## Future / beyond v1 — ideas, not scheduled

- **Cloud storage + web app** *(idea, parked — discussed 2026-06-25)*. Keep the
  data off-Mac so a future web app can read it. The store is already one small
  self-contained JSON doc with `schemaVersion`, so this is mostly plumbing.
  Phased approach (cheapest → fullest):
  - **A.** Write the JSON into a synced cloud folder (iCloud Drive / Dropbox);
    web app pulls it via that provider's API. Requires **dropping the app
    sandbox** (no longer needed since App Group was removed) so the app can write
    outside its container.
  - **B.** *(recommended first step)* On every `persist()`, `PUT` the whole JSON
    blob to a cloud object (Supabase Storage / Cloudflare R2 / S3) behind a token
    (token → Keychain). Web app reads it; **no conflicts while the Mac is the only
    writer**. ~a day's work; doubles as an off-Mac backup.
  - **C.** Real backend (Postgres + REST/GraphQL, e.g. Supabase): Mac and web are
    both API clients. Biggest effort (Mac becomes an API client w/ auth + offline
    + sync).
  - Notes: add a top-level `updatedAt` to `DobaData` to enable last-write-wins
    once two writers exist; this **crosses the no-backend / single-user / mac-only
    decisions**, so going ahead means new DECISIONS entries.
- Data sync between the author's two Macs (same mechanism as above).
