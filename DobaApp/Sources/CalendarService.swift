import Foundation
import Combine
import EventKit
import os
import DobaKit

/// Read-only bridge to the system Calendar via EventKit. Loads a **window** of
/// days (past for the archive, future for the week view), maps events to DobaKit
/// `Meeting`s grouped by day, and republishes on calendar changes. Nothing is
/// ever written or stored.
///
/// On macOS 14+, *reading* events requires **full access** — there is no
/// read-only level. Hence `requestFullAccessToEvents` +
/// `NSCalendarsFullAccessUsageDescription`.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorization: EKAuthorizationStatus
    /// Today's non-all-day meetings, keyed by start-of-day.
    @Published private(set) var meetingsByDay: [Date: [Meeting]] = [:]

    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.andreyrozumny.Doba", category: "calendar")
    private var changeObserver: NSObjectProtocol?

    private let pastDays = 31
    private let futureDays = 14

    var hasAccess: Bool { authorization == .fullAccess }

    init() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    /// Meetings for a given day (empty if none / outside the loaded window).
    func meetings(on day: Date, calendar: Calendar = .current) -> [Meeting] {
        meetingsByDay[calendar.startOfDay(for: day)] ?? []
    }

    /// Prompt for full access (once), then load. Safe to call again later.
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription)")
        }
        authorization = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    /// Refresh the whole window from the store. No-op (and clears) without access.
    func reload(now: Date = Date(), calendar: Calendar = .current) {
        guard hasAccess else {
            meetingsByDay = [:]
            return
        }
        let start = calendar.date(byAdding: .day, value: -pastDays, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: pastDays + futureDays + 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var grouped: [Date: [Meeting]] = [:]
        for event in store.events(matching: predicate) where !event.isAllDay {
            let meeting = Meeting(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: (event.title?.isEmpty == false ? event.title : nil) ?? "(No title)",
                start: event.startDate,
                end: event.endDate
            )
            grouped[calendar.startOfDay(for: event.startDate), default: []].append(meeting)
        }
        for key in grouped.keys { grouped[key]?.sort { $0.start < $1.start } }
        meetingsByDay = grouped
    }
}
