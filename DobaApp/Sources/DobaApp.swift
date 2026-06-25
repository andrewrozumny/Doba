import SwiftUI
import WidgetKit
import DobaKit

/// Doba's menu-bar entry point. No main window and no Dock icon (LSUIElement is
/// set in Info.plist) — the whole app lives behind the menu-bar item.
///
/// `.menuBarExtraStyle(.window)` gives a proper panel (a real SwiftUI view with
/// scrolling, lists, etc.) rather than a plain NSMenu, which is what the
/// today-view needs.
@main
struct DobaApp: App {
    @StateObject private var store = DobaStore.shared
    @StateObject private var calendar = CalendarService()
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
        MenuBarExtra("Doba", image: "MenuBarIcon") {
            TodayView()
                .environmentObject(store)
                .environmentObject(calendar)
        }
        .menuBarExtraStyle(.window)
    }
}
