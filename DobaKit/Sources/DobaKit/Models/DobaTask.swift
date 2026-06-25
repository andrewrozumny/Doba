import Foundation

/// Status axis: just todo / done for v1.
public enum TaskStatus: String, Codable, Sendable {
    case todo
    case done
}

/// Where the task came from — useful for later analytics and for trusting
/// parsed fields less than hand-entered ones.
public enum TaskSource: String, Codable, Sendable {
    case manual    // typed in by hand
    case dictated  // macOS dictation into the text field
    case parsed    // produced by the Claude NL parser (Phase 4)
}

/// How a task repeats. nil on a task = one-off.
public enum RecurrenceRule: String, Codable, Sendable, CaseIterable {
    case daily      // every day
    case weekdays   // Mon–Fri
    case weekly     // same weekday each week

    public var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        }
    }
}

/// The atomic unit of work, always scoped to **one concrete day**.
///
/// Named `DobaTask` (not `Task`) on purpose: `Task` is Swift Concurrency's
/// type, and shadowing it across the whole app is a recipe for confusing
/// errors. See docs/DECISIONS.md.
///
/// The four independent axes from the spec, kept as separate fields (never
/// collapsed into one flag):
///   1. Time-binding — `scheduledTime` (nil = floating pool, set = timeline slot)
///   2. Plan vs fact — `estimatedHours` here; *actual* hours are derived from
///      `TimeEntry`, never stored on the task.
///   3. Billable      — `billable`
///   4. Status        — `status`
public struct DobaTask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var projectID: UUID?

    /// The day this task lives on. Normalize to `startOfDay` before storing so
    /// day-equality comparisons are trivial.
    public var scheduledDate: Date

    /// nil → floating ("just needs doing today"), shown in the pool.
    /// set → pinned to a slot, shown on the timeline next to meetings.
    public var scheduledTime: Date?

    /// Planned hours. Actual hours are summed from `TimeEntry` — not here.
    public var estimatedHours: Double?

    /// True = paid work; false = important-but-overhead.
    public var billable: Bool

    public var status: TaskStatus

    /// Set when the task was auto-rolled forward from an earlier, unfinished day.
    public var isCarriedOver: Bool

    public var notes: String?
    public var source: TaskSource
    public var createdAt: Date
    /// If this task was created from a calendar event, its `EKEvent` id — so the
    /// timeline hides the original meeting and shows the (checkable) task instead.
    public var linkedEventID: String?
    /// Recurrence rule (nil = one-off) and the series id shared by all instances
    /// of a recurring task. See DECISIONS D27.
    public var recurrence: RecurrenceRule?
    public var recurrenceID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        projectID: UUID? = nil,
        scheduledDate: Date,
        scheduledTime: Date? = nil,
        estimatedHours: Double? = nil,
        billable: Bool = false,
        status: TaskStatus = .todo,
        isCarriedOver: Bool = false,
        notes: String? = nil,
        source: TaskSource = .manual,
        createdAt: Date = Date(),
        linkedEventID: String? = nil,
        recurrence: RecurrenceRule? = nil,
        recurrenceID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.estimatedHours = estimatedHours
        self.billable = billable
        self.status = status
        self.isCarriedOver = isCarriedOver
        self.notes = notes
        self.source = source
        self.createdAt = createdAt
        self.linkedEventID = linkedEventID
        self.recurrence = recurrence
        self.recurrenceID = recurrenceID
    }

    /// Convenience: true when this task belongs in the timeline (has a slot)
    /// rather than the floating pool.
    public var isTimeBound: Bool { scheduledTime != nil }
}
