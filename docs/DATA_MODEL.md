# Doba — Data model (v1)

Everything persists as one Codable document (`DobaData`) in a single JSON file
in the App Group container. Source files: `DobaKit/Sources/DobaKit/Models/`.

## Types

### `Project`
A lightweight tag. Optional on a task.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `name` | `String` | |
| `colorHex` | `String` | `"#RRGGBB"`; turned into a `Color` in the UI layer only |

### `DobaTask`
The atomic unit of work, always scoped to **one concrete day**. Named
`DobaTask` (not `Task`) to avoid shadowing Swift Concurrency's `Task`.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `title` | `String` | |
| `projectID` | `UUID?` | |
| `scheduledDate` | `Date` | the day; normalize to `startOfDay` |
| `scheduledTime` | `Date?` | **nil = floating pool**, set = pinned to a timeline slot |
| `estimatedHours` | `Double?` | planned hours |
| `billable` | `Bool` | true = paid, false = overhead |
| `status` | `TaskStatus` | `.todo` / `.done` |
| `isCarriedOver` | `Bool` | set when auto-rolled from an earlier day |
| `notes` | `String?` | |
| `source` | `TaskSource` | `.manual` / `.dictated` / `.parsed` |
| `createdAt` | `Date` | |

> **`actualHours` is NOT stored on the task.** It is derived from `TimeEntry`.

The **four independent axes** (kept as separate fields, never merged into one
flag): 1) time-binding (`scheduledTime`), 2) plan-vs-fact (`estimatedHours` here
+ actuals from `TimeEntry`), 3) billable (`billable`), 4) status (`status`).

### `TimeEntry`
A worked interval. The **source of truth for actual hours**.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `taskID` | `UUID` | |
| `start` | `Date` | |
| `end` | `Date?` | **nil = the timer is running right now** |

- A task's `actualHours` = sum of its closed entries' durations (+ live tick for
  any running one).
- **One active timer app-wide**: at most one entry with `end == nil`. Starting a
  new timer closes the open one first. "Which timer is active" is derived from
  the open entry — no separate flag.

### `DobaData` (root)
`schemaVersion` (Int, starts at 1) + `projects` + `tasks` + `timeEntries`.
Holds pure query helpers (`tasks(on:)`, `project(for:)`) so the widget can read
them off the main thread.

## Day rollups

- **Planned** = Σ `estimatedHours` of today's tasks (by project) + Σ duration of
  today's calendar events.
- **Spent** = Σ actual hours from today's `TimeEntry`s.
- **Billable vs overhead** = the same hours (planned and actual) split by the
  `billable` flag.

## Carry-over

On launch / day change: every `DobaTask` with `scheduledDate < today &&
status == .todo` → set `scheduledDate = today`, `isCarriedOver = true`.
`TimeEntry`s of past days are left untouched — actual-hours history stays on its
own date.

## Trade-off: ranged tasks → N atomic tasks

A multi-day task ("6h/day Mon–Fri") is **expanded into N atomic `DobaTask`s,
one per day**, each with its own `estimatedHours`.

- **Why:** rollups, check-off, carry-over, and hour accounting all stay trivial
  and per-day. The cost is a duplicated title across days.
- **Rejected alternative (candidate for v2):** a `PlannedBlock` describing the
  range + on-the-fly expansion. More normalized, but every consumer would have
  to expand it.

Meetings are **not** part of this model — they're `EKEvent`s from EventKit,
merged into the today-view for display and rollup hours only.
