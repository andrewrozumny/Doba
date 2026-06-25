import Foundation

/// The **planned** side of a day: how the planned hours break down by project,
/// plus meeting time. (The plan-vs-actual and billable-vs-overhead splits arrive
/// in Phase 3 once `TimeEntry` actuals exist.)
public struct PlannedRollup: Sendable, Equatable {
    public struct ProjectLine: Identifiable, Sendable, Equatable {
        public var id: UUID?        // project id; nil = untagged ("No project")
        public var name: String
        public var colorHex: String?
        public var hours: Double
    }

    /// Per-project planned task hours, hours-descending, **zero-hour groups
    /// omitted**. (A project whose today-tasks have no estimates contributes
    /// nothing to the breakdown.)
    public var projectLines: [ProjectLine]
    public var taskHours: Double      // Σ estimatedHours of today's tasks
    public var meetingHours: Double   // Σ meeting durations
    public var meetingCount: Int

    /// Whole planned day = task estimates + meetings.
    public var total: Double { taskHours + meetingHours }
}

/// A summary of logged work over a date range (the monthly 15→15 report):
/// billable vs overhead hours, money earned, and a per-project breakdown.
public struct PeriodReport: Sendable {
    public struct ProjectLine: Identifiable, Sendable {
        public var id: String { name }
        public let name: String
        public let colorHex: String?
        public let hours: Double
        public let earnings: Double
    }
    public let billableHours: Double
    public let overheadHours: Double
    public let earnings: Double
    public let projectLines: [ProjectLine]   // billable projects, hours-descending
}

extension DobaData {
    /// Build the planned-hours rollup for `day`, folding in the given meetings.
    /// Pure — the app fetches meetings from EventKit and passes them in.
    public func plannedRollup(
        on day: Date,
        meetings: [Meeting] = [],
        calendar: Calendar = .current
    ) -> PlannedRollup {
        let todays = tasks(on: day, calendar: calendar)

        var hoursByProject: [UUID?: Double] = [:]
        for task in todays {
            hoursByProject[task.projectID, default: 0] += task.estimatedHours ?? 0
        }

        let lines: [PlannedRollup.ProjectLine] = hoursByProject
            .filter { $0.value > 0 }
            .map { projectID, hours in
                if let projectID, let project = projects.first(where: { $0.id == projectID }) {
                    return .init(id: projectID, name: project.name, colorHex: project.colorHex, hours: hours)
                }
                return .init(id: nil, name: "No project", colorHex: nil, hours: hours)
            }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.name < $1.name }

        return PlannedRollup(
            projectLines: lines,
            taskHours: todays.reduce(0) { $0 + ($1.estimatedHours ?? 0) },
            meetingHours: meetings.reduce(0) { $0 + $1.hours },
            meetingCount: meetings.count
        )
    }
}

/// The full day picture: planned breakdown + actual hours logged + the
/// billable/overhead split of both. Billable/overhead applies to **tasks only**
/// (meetings carry no billable flag and are reported separately as meeting
/// hours).
public struct DayRollup: Sendable, Equatable {
    public var planned: PlannedRollup

    /// Hours logged *today* (entries that started today; running one ticked live).
    public var actualHours: Double

    public var plannedBillable: Double
    public var plannedOverhead: Double
    public var actualBillable: Double
    public var actualOverhead: Double
}

extension DobaData {
    public func dayRollup(
        on day: Date,
        meetings: [Meeting] = [],
        asOf now: Date = Date(),
        calendar: Calendar = .current
    ) -> DayRollup {
        let planned = plannedRollup(on: day, meetings: meetings, calendar: calendar)

        // Planned billable split — over today's tasks' estimates.
        var plannedBillable = 0.0, plannedOverhead = 0.0
        for task in tasks(on: day, calendar: calendar) {
            let hours = task.estimatedHours ?? 0
            if task.billable { plannedBillable += hours } else { plannedOverhead += hours }
        }

        // Actual — entries that started today; billable per the entry's task.
        let startOfDay = calendar.startOfDay(for: day)
        var actual = 0.0, actualBillable = 0.0, actualOverhead = 0.0
        for entry in timeEntries where calendar.isDate(entry.start, inSameDayAs: startOfDay) {
            let hours = DobaData.effectiveHours(entry, asOf: now)
            actual += hours
            if tasks.first(where: { $0.id == entry.taskID })?.billable == true {
                actualBillable += hours
            } else {
                actualOverhead += hours
            }
        }

        return DayRollup(
            planned: planned,
            actualHours: actual,
            plannedBillable: plannedBillable,
            plannedOverhead: plannedOverhead,
            actualBillable: actualBillable,
            actualOverhead: actualOverhead
        )
    }
}
