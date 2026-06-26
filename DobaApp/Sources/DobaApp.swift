import SwiftUI
import WidgetKit
import DobaKit

/// Doba's menu-bar entry point. No main window and no Dock icon (LSUIElement is
/// set in Info.plist) — the whole app lives behind the menu-bar item.
///
/// The menu-bar status item and its panel popover are built and owned by
/// `AppDelegate` (not a SwiftUI `MenuBarExtra`) so the panel can be **opened
/// from code** — e.g. popped open when a timer auto-stops. This scene is just an
/// empty `Settings` placeholder to satisfy SwiftUI's `App`; for this LSUIElement
/// agent app it never shows a window. See DECISIONS D47.
@main
struct DobaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Launch sequence (app is the only writer):
        //  1. log how the shared store resolves (App Group vs fallback),
        //  2. roll unfinished past-day tasks onto today,
        //  3. generate recurring-task instances for the next two weeks,
        //  4. nudge the widget to re-read the shared store.
        DobaStorage.logDiagnostics(context: "DobaApp")
        DobaStore.shared.normalizeBillable()   // rated project ⇒ billable, store-wide
        DobaStore.shared.carryOverUnfinished()
        DobaStore.shared.materializeRecurring(through: DobaApp.recurrenceHorizon())
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Two weeks out — enough to fill the week view plus buffer.
    static func recurrenceHorizon() -> Date {
        Calendar.current.date(byAdding: .day, value: 13, to: Date()) ?? Date()
    }

    var body: some Scene {
        // The real UI is the AppDelegate-owned status item + popover; this empty
        // Settings scene exists only because `App` requires a `Scene`.
        Settings { EmptyView() }
    }
}
