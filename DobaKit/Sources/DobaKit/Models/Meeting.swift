import Foundation

/// A calendar event surfaced **read-only** for display + planned-hours rollup.
/// Never persisted — the app builds these on the fly from EventKit `EKEvent`s
/// and merges them into the today-view. DobaKit stays EventKit-free (the app
/// owns the `EKEvent → Meeting` mapping), which keeps the core widget-linkable.
///
/// All-day events are excluded by the mapper — they aren't timeline slots and
/// shouldn't inflate the day's planned hours.
public struct Meeting: Identifiable, Hashable, Sendable {
    public let id: String      // EKEvent.eventIdentifier
    public var title: String
    public var start: Date
    public var end: Date

    public init(id: String, title: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }

    /// Duration in hours (never negative).
    public var hours: Double {
        max(0, end.timeIntervalSince(start)) / 3600
    }
}
