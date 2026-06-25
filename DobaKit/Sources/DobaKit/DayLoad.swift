import Foundation

/// How "booked" a day is, by **billable** planned hours relative to the day's
/// available capacity. 8 billable hours is the full-day target; meetings and
/// non-billable blockers (e.g. an exam) reduce the available capacity, so a day
/// with a 2h block needs only 6 billable hours to read as full. The UI maps
/// these to colors (full→green, partial→yellow, low→orange, empty→red,
/// blocked→grey). See DECISIONS D26.
public enum DayLoad: Sendable, Equatable {
    case full       // billable >= capacity
    case partial    // >= 75% of capacity
    case low        // >= 50% of capacity
    case empty      // below 50%
    case blocked    // no capacity left (fully taken by meetings/blockers)

    /// A normal full working day's billable target.
    public static let fullDayHours = 8.0

    /// Color bucket from billable hours against the day's available capacity.
    public init(billableHours: Double, capacityHours: Double) {
        guard capacityHours > 0 else { self = .blocked; return }
        let ratio = billableHours / capacityHours
        switch ratio {
        case 1...:        self = .full
        case 0.75..<1:    self = .partial
        case 0.5..<0.75:  self = .low
        default:          self = .empty
        }
    }
}

public extension DobaData {
    /// Sum of `estimatedHours` for **billable** tasks on `day`.
    func plannedBillableHours(on day: Date, calendar: Calendar = .current) -> Double {
        tasks(on: day, calendar: calendar)
            .filter(\.billable)
            .reduce(0) { $0 + ($1.estimatedHours ?? 0) }
    }

    /// Sum of `estimatedHours` for **non-billable** (overhead/blocker) tasks on `day`.
    func plannedOverheadHours(on day: Date, calendar: Calendar = .current) -> Double {
        tasks(on: day, calendar: calendar)
            .filter { !$0.billable }
            .reduce(0) { $0 + ($1.estimatedHours ?? 0) }
    }

    /// Sum of `estimatedHours` for all tasks on `day` (billable + overhead).
    func plannedTaskHours(on day: Date, calendar: Calendar = .current) -> Double {
        tasks(on: day, calendar: calendar).reduce(0) { $0 + ($1.estimatedHours ?? 0) }
    }

    /// Available billable capacity for the day = full day minus overhead tasks
    /// and `meetingHours` (pass the day's non-converted meeting hours).
    func dayCapacity(on day: Date, meetingHours: Double, calendar: Calendar = .current) -> Double {
        max(0, DayLoad.fullDayHours - plannedOverheadHours(on: day, calendar: calendar) - meetingHours)
    }
}
