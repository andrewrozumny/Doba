# Doba — a native macOS task planner & freelance timesheet

> A personal menu-bar app that turns a freelancer's messy "what am I doing today,
> and did I bill it?" into a clean day/week plan with one-tap time logging and
> natural-language task entry. Built in **native SwiftUI**, with a **Claude**
> parser doing the heavy lifting on input.

*Personal project · macOS-only · solo build (paired with Claude Code) · ~2 days.*

---

## The problem

As a freelancer I kept three things in three places: a to-do list, the calendar,
and a spreadsheet of billable hours. Nothing told me, at a glance, **"is today
full of paid work, or am I about to under-bill?"** — and logging time after the
fact was the step I always skipped.

Doba is one surface that answers that: plan the day, see the week's billable
load by color, and log time *as you complete tasks*.

---

## What it does

- **Day / Week / archive in one panel.** Step through any day (today, tomorrow,
  past). The week view shows the next 7 days, each color-coded by **available
  billable capacity** — `8h − meetings − non-billable blockers` — so a day with a
  2-hour exam only needs 6 billable hours to read "green".
- **Natural-language entry via Claude.** Type *"созвон с клиентом, Helpmybiz, 1h,
  11:30"* and the model returns structured tasks — project, estimate, time,
  billable, even expanding *"6h/day Mon–Fri"* into one task per day. It's given
  the list of existing projects so it matches abbreviations/aliases instead of
  creating duplicates.
- **Calendar, read-only.** Today's meetings merge into the timeline live via
  EventKit; a meeting can be promoted to a trackable task with one tap.
- **Time tracking that fits real billing.** A built-in timer or manual entry,
  with a **30-minute minimum increment**. Completing a task asks how long it took
  (pre-filled with the estimate); logging **less than planned rolls the
  remainder to tomorrow** automatically.
- **Rates & earnings.** Per-project hourly rates (with a global fallback) drive
  *earned* vs *projected* money, per day and per week.
- **The small things that make it stick:** recurring tasks (daily/weekdays/
  weekly), carry-over of unfinished work, a global **⌃⌥D** quick-capture from any
  app, an amber nudge on past billable tasks with no time logged, and done items
  that sink to the bottom so the open ones stay in focus.

---

## Tech stack

| Area | Choice |
|---|---|
| UI | **SwiftUI**, strict macOS HIG (`MenuBarExtra(.window)`, system materials, SF Symbols) |
| Widget | **WidgetKit** extension (`TimelineProvider`) |
| Calendar | **EventKit** (read-only, full-access on macOS 14+) |
| AI parsing | **Claude API** (`claude-haiku-4-5`) over raw `URLSession`, JSON-only contract |
| Secrets | **Keychain** (Security framework) — never in the repo |
| Global hotkey | **Carbon** `RegisterEventHotKey` (no dependency, no Accessibility prompt) |
| Storage | Local **JSON** `Codable` document in an **App Group** container |
| Project gen | **XcodeGen** — `project.yml` is the source of truth, `.xcodeproj` is generated |

**Zero third-party dependencies.**

---

## Architecture

Three targets, with a clean dependency direction:

```
DobaApp (menu bar)  ─┐
                     ├─ link → DobaKit (framework): models · store · pure logic
DobaWidget (WidgetKit)┘
```

- **`DobaKit`** holds the domain: the `Codable` models, a thin storage layer, and
  **all the logic as pure functions** — day rollups, billable-capacity buckets,
  earnings, recurrence materialization, carry-over, the 30-minute floor. No UI
  framework leaks into it, so it links cleanly into both the app and the widget.
- The storage layer is deliberately **non-actor-isolated** so the widget's
  timeline provider can read the shared store off the main thread, while the app
  drives an `@MainActor` observable store for SwiftUI.
- Because the logic is pure, it's **validated with standalone `swiftc`
  compile-and-run harnesses** (50+ assertions across dates, rollups, earnings,
  recurrence, and the scheduling math) — fast feedback without a full app build.
- Decisions are tracked **ADR-lite** in `docs/DECISIONS.md` (31 entries and
  counting), so every non-obvious choice has a "why" attached.

---

## Engineering challenges solved

A few problems that were more interesting than the feature list suggests:

**1. The widget rendered empty — and it wasn't the obvious cause.**
The desktop widget showed only its header. The suspicion was App Group sharing,
but the real culprit was the **Debug build**: Xcode ships a launcher shim
(`*.debug.dylib` + `__preview.dylib`) that the app tolerates but that makes the
**widget extension fail to launch** when the system (`chronod`) runs it
standalone — so its code never executed. I confirmed it by writing a marker from
`WidgetBundle.init` to capture exactly which container the extension resolves;
the file never appeared. **Fix: ship Release builds** (correct for a deployed app
anyway), where the extension links the framework directly and launches.

**2. App Group sharing on a free Apple account — diagnosed to a firm conclusion.**
Once the extension launched, the marker showed the smoking gun: `containerURL`
resolved, `storeFileExists = true`, but `tasksRead = -1` and the write **orphaned
into the widget's own sandbox tmp**. The `application-groups` entitlement is in
the *signature* but in **neither provisioning profile** — free Apple accounts
can't provision app groups, so the sandbox denies the extension real I/O on the
shared container. Conclusion documented: the widget needs a paid account; the
plumbing is correct, so it'll work with zero code changes once provisioned.

**3. A list that silently collapsed to nothing.**
Tasks "existed" (the summary said *Planned 6h*) but the list was blank. A
`ScrollView` inside `MenuBarExtra(.window)` has no intrinsic height and shrinks to
zero. Fix: a fixed-size panel with the scroll region expanding to fill — and the
same fixed size on every swapped sub-view so the window never jumps.

---

## Constraints & decisions worth noting

- **Single-user, Mac-only, no backend, never published** — so the simplest thing
  that works wins: one JSON file over SwiftData, read-only EventKit (events are
  never stored), and a local Claude call instead of any server.
- **Secrets never touch the repo** — the API key lives in Keychain, entered
  in-app.
- **`project.yml` is the source of truth** — the Xcode project is generated and
  git-ignored, so the build is reproducible from text.

---

## Screens to capture (shot list)

1. **Day view** — timeline (tasks + a calendar meeting) + floating pool + the
   planned/earned summary.
2. **Week view** — the 7-day capacity color strip + week earnings footer.
3. **Natural-language entry** — type a sentence, the ✨ result as structured tasks.
4. **Complete-with-time** — the log-hours step with the "rolls to tomorrow" hint.
5. **Projects** — rename / recolor / per-project rate.
6. **Global hotkey** — the ⌃⌥D quick-capture panel floating over another app.

---

*Built phase-by-phase against a written roadmap; see `docs/` for the roadmap,
architecture, data model, and decision log.*
