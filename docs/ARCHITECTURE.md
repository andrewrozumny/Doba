# Doba — Architecture

Three targets in one Xcode project (generated from `project.yml`).

## Targets

| Target | Type | Role |
|---|---|---|
| **DobaApp** | macOS app (`MenuBarExtra`, `LSUIElement`) | Primary surface. All the heavy logic: input, parsing, task management, calendar reads, carry-over, rollups. **The only writer** to the store. |
| **DobaWidget** | WidgetKit extension (`.appex`) | Lightweight "glance + tick" surface. **Reads only.** From Phase 5, toggles checkboxes via App Intents. Never manages data. |
| **DobaKit** | Framework | Shared core: models, JSON store, business logic. Linked into both above so nothing is duplicated. UI-framework-free (no SwiftUI import) so it stays linkable from the extension. |

DobaKit is a **framework**, embedded into the app (`Contents/Frameworks/`) and
linked by the widget, which finds it at runtime via `@rpath`
(`@executable_path/../../../../Frameworks`). The widget `.appex` is embedded into
the app's `Contents/PlugIns/`.

## Shared data via App Group

Both targets share one container, identified by a single constant
(`AppGroup.identifier`) that must match both `.entitlements` files. The store is
**one JSON file** (`doba.json`) in that container.

If the App Group isn't provisioned yet, `DobaStorage` falls back to a per-app
`Application Support/Doba/` directory so the app still runs — but then the app
and widget do **not** share data. Real sharing requires the App Group enabled in
Xcode (see `SETUP.md`).

## Data flow

```
                  ┌─────────────────────────────────────────────┐
   user input ───▶│ DobaApp (menu bar)                          │
   dictation      │  parse / create / edit / check / timer       │
   Claude API ───▶│  carry-over, rollups                         │
   EventKit  ────▶│  (calendar events: read-only, display only)  │
                  └───────────────┬─────────────────────────────┘
                                  │ write
                                  ▼
                  ┌─────────────────────────────────────────────┐
                  │ DobaKit store  →  doba.json (App Group)      │
                  └───────────────┬─────────────────────────────┘
                       read       │       read
              ┌───────────────────┘        └──────────────────┐
              ▼                                                ▼
   ┌────────────────────┐                         ┌────────────────────────┐
   │ DobaApp today-view │                         │ DobaWidget (read-only) │
   └────────────────────┘                         └────────────────────────┘

   After any write, the app calls WidgetCenter.shared.reloadAllTimelines()
   so the widget re-reads the file and redraws.
```

## Boundaries / rules

- **DobaKit imports no UI framework.** Color-from-hex, views, etc. live in the
  app/widget targets. This keeps the core safe to link into the sandboxed
  extension and easy to reason about.
- **Calendar events are never persisted.** They're `EKEvent`s merged into the
  today-view at display time only (Phase 2).
- **One writer.** The app writes; the widget reads. (Phase 5 widget toggles are
  the deliberate, narrow exception, done through App Intents.)
- **Actual hours are derived,** never stored on the task — summed from
  `TimeEntry` records (Phase 3).
