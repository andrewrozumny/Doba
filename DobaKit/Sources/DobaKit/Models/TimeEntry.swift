import Foundation

/// A single worked interval against a task. The source of truth for *actual*
/// hours — the task itself never stores `actualHours`, it's summed from these.
///
/// `end == nil` means "the timer is running right now". The app enforces at
/// most one such open entry at a time (one active timer); that rule lives in
/// the store, not here. (Timer logic lands in Phase 3.)
public struct TimeEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var start: Date
    public var end: Date?

    public init(id: UUID = UUID(), taskID: UUID, start: Date, end: Date? = nil) {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
    }

    /// True while this entry is the live, running timer.
    public var isRunning: Bool { end == nil }

    /// Duration in hours for a *closed* entry; nil while still running
    /// (the live tick is computed in the UI against the current time).
    public var hours: Double? {
        guard let end else { return nil }
        return end.timeIntervalSince(start) / 3600
    }
}
