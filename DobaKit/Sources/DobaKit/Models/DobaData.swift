import Foundation

/// The entire persisted state, as one Codable document written to a single
/// JSON file in the App Group container. Small data, so one file is plenty and
/// keeps things easy to inspect/debug — see docs/DECISIONS.md.
///
/// `schemaVersion` is here from day one so a future migration has something to
/// branch on rather than guessing.
public struct DobaData: Codable, Sendable {
    public var schemaVersion: Int
    public var projects: [Project]
    public var tasks: [DobaTask]
    public var timeEntries: [TimeEntry]
    /// Hourly rate for earnings (nil = not set). Optional → old stores decode fine.
    public var hourlyRate: Double?
    /// Currency symbol for earnings display (e.g. "$", "₴", "€").
    public var currency: String?

    public static let currentSchemaVersion = 1

    /// Default estimate for a quick-added task with no duration given (30 min).
    public static let defaultEstimateHours = 0.5

    /// Target billable hours per work-week (week starts Sunday). The week view
    /// tracks progress toward this.
    public static let weeklyBillableTargetHours = 40.0

    /// Target billable hours per pay period (15th → 15th): 4 weeks × 40h.
    public static let monthlyBillableTargetHours = 160.0

    /// Name of the catch-all project for tasks created without one.
    public static let internalProjectName = "Internal"

    public init(
        schemaVersion: Int = DobaData.currentSchemaVersion,
        projects: [Project] = [],
        tasks: [DobaTask] = [],
        timeEntries: [TimeEntry] = [],
        hourlyRate: Double? = nil,
        currency: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.tasks = tasks
        self.timeEntries = timeEntries
        self.hourlyRate = hourlyRate
        self.currency = currency
    }

    public static let empty = DobaData()

    // MARK: - Queries (pure, nonisolated — safe to call from the widget)

    public func project(for task: DobaTask) -> Project? {
        guard let id = task.projectID else { return nil }
        return projects.first { $0.id == id }
    }

    /// Tasks scheduled for `day`, ordered timeline-first (by slot) then the
    /// floating pool (by creation order).
    public func tasks(on day: Date, calendar: Calendar = .current) -> [DobaTask] {
        let target = calendar.startOfDay(for: day)
        return tasks
            .filter { calendar.isDate($0.scheduledDate, inSameDayAs: target) }
            .sorted { lhs, rhs in
                switch (lhs.scheduledTime, rhs.scheduledTime) {
                case let (l?, r?): return l < r
                case (.some, .none): return true   // time-bound before floating
                case (.none, .some): return false
                case (.none, .none): return lhs.createdAt < rhs.createdAt
                }
            }
    }

    // MARK: - Mutations (pure)

    /// Move every unfinished (`.todo`) task dated before `today` onto `today`
    /// and mark it carried over. A time-bound task keeps its slot, shifted to
    /// today's date at the same clock time, so it stays on the timeline rather
    /// than silently dropping into the floating pool (see DECISIONS D16).
    /// `TimeEntry`s are untouched — actual-hours history stays on its own date.
    /// Returns how many tasks moved. Idempotent within a day.
    @discardableResult
    public mutating func carryOverUnfinished(asOf today: Date = Date(), calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: today)
        var moved = 0
        for i in tasks.indices {
            // Recurring tasks are scheduled by their rule, not carried forward.
            guard tasks[i].status == .todo, tasks[i].recurrence == nil,
                  calendar.startOfDay(for: tasks[i].scheduledDate) < startOfToday else { continue }
            tasks[i].scheduledDate = startOfToday
            tasks[i].isCarriedOver = true
            if let slot = tasks[i].scheduledTime {
                let hm = calendar.dateComponents([.hour, .minute], from: slot)
                tasks[i].scheduledTime = calendar.date(
                    bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: startOfToday
                )
            }
            moved += 1
        }
        return moved
    }

    // MARK: - Time tracking (pure)

    /// All currently running entries — **timers run in parallel**, one per task,
    /// so the freelancer can track several tasks at once. See DECISIONS D42.
    public var runningEntries: [TimeEntry] { timeEntries.filter { $0.end == nil } }

    /// The running entry for a specific task (nil if it isn't being timed).
    public func runningEntry(forTaskID id: UUID) -> TimeEntry? {
        timeEntries.first { $0.taskID == id && $0.end == nil }
    }

    public func isRunning(taskID id: UUID) -> Bool { runningEntry(forTaskID: id) != nil }

    /// Start timing `taskID` (does **not** stop other tasks' timers). No-op if
    /// this task is already being timed. Returns true if a timer was started.
    @discardableResult
    public mutating func startTimer(taskID: UUID, at now: Date = Date()) -> Bool {
        guard runningEntry(forTaskID: taskID) == nil else { return false }
        timeEntries.append(TimeEntry(taskID: taskID, start: now, end: nil))
        return true
    }

    /// Stop `taskID`'s timer. The worked time is logged **and burned down from
    /// the task's estimate** (the task stays todo). So "ran the timer" always
    /// means "worked that time". Other tasks' timers keep running. See D40/D42.
    @discardableResult
    public mutating func stopTimer(taskID: UUID, at now: Date = Date()) -> Bool {
        guard let index = timeEntries.firstIndex(where: { $0.taskID == taskID && $0.end == nil }) else { return false }
        let end = max(now, timeEntries[index].start)
        // Accidental tap: a timer that ran under 30s logs nothing and is discarded
        // (no entry, no burndown) — matches "≥30s rounds up" in effectiveHours.
        if end.timeIntervalSince(timeEntries[index].start) < 30 {
            timeEntries.remove(at: index)
            return true
        }
        timeEntries[index].end = end
        let worked = DobaData.effectiveHours(timeEntries[index], asOf: now)
        if let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
           let estimate = tasks[taskIndex].estimatedHours {
            tasks[taskIndex].estimatedHours = max(0, estimate - worked)
        }
        return true
    }

    /// Stop every running timer (e.g. on quit). Returns how many were stopped.
    @discardableResult
    public mutating func stopAllTimers(at now: Date = Date()) -> Int {
        runningEntries.map(\.taskID).reduce(0) { $0 + (stopTimer(taskID: $1, at: now) ? 1 : 0) }
    }

    /// Add a manual closed entry of `hours` ending at `endingAt` (for "forgot to
    /// start the timer" corrections). No-op for non-positive hours.
    public mutating func addManualEntry(taskID: UUID, hours: Double, endingAt now: Date = Date()) {
        guard hours > 0 else { return }
        timeEntries.append(TimeEntry(taskID: taskID, start: now.addingTimeInterval(-hours * 3600), end: now))
    }

    public mutating func deleteTimeEntry(id: UUID) {
        timeEntries.removeAll { $0.id == id }
    }

    /// Hours for one entry, **counted to the nearest minute** (≥30s rounds up) —
    /// the timer logs real minutes, not a 30-min minimum. A running entry ticks
    /// to `now`. See DECISIONS D24 (superseded).
    public static func effectiveHours(_ entry: TimeEntry, asOf now: Date) -> Double {
        let end = entry.end ?? now
        let seconds = max(0, end.timeIntervalSince(entry.start))
        return (seconds / 60).rounded() / 60   // → nearest minute, expressed in hours
    }

    /// Lifetime actual hours for a task — sum of its entries (30-min minimum
    /// each), with the running one ticked live to `now`. (Spans carry-overs,
    /// since a carried task keeps its id and its entries.)
    public func actualHours(forTaskID id: UUID, asOf now: Date = Date()) -> Double {
        timeEntries
            .filter { $0.taskID == id }
            .reduce(0) { $0 + DobaData.effectiveHours($1, asOf: now) }
    }

    /// A task's entries, oldest first.
    public func entries(forTaskID id: UUID) -> [TimeEntry] {
        timeEntries.filter { $0.taskID == id }.sorted { $0.start < $1.start }
    }

    /// Move a task by `days` (keeps a time-bound task's clock time on the new
    /// day). Returns true if found.
    @discardableResult
    public mutating func shiftTask(id: UUID, byDays days: Int, calendar: Calendar = .current) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              let moved = calendar.date(byAdding: .day, value: days, to: tasks[index].scheduledDate) else { return false }
        let start = calendar.startOfDay(for: moved)
        tasks[index].scheduledDate = start
        if let slot = tasks[index].scheduledTime {
            let hm = calendar.dateComponents([.hour, .minute], from: slot)
            tasks[index].scheduledTime = calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: start)
        }
        return true
    }

    /// Find (case-insensitive) or create the default "Internal" project.
    @discardableResult
    public mutating func ensureInternalProject() -> UUID {
        if let existing = projects.first(where: {
            $0.name.caseInsensitiveCompare(DobaData.internalProjectName) == .orderedSame
        }) {
            return existing.id
        }
        let project = Project(name: DobaData.internalProjectName, colorHex: Project.palette[0])
        projects.append(project)
        return project.id
    }

    /// Complete a task with the hours actually worked. Logs the hours, then:
    /// - logged **≥ estimate** (or nothing logged) → mark this task **done** in place;
    /// - logged **< estimate** → mark **today's task done** for the hours worked
    ///   (its estimate becomes that chunk) and append a fresh **continuation**
    ///   task for the remainder on the **next day**. So today keeps a "did Nh,
    ///   done" record and the leftover continues tomorrow. See DECISIONS D29.
    @discardableResult
    public mutating func completeTask(id: UUID, loggedHours: Double, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let estimate = tasks[index].estimatedHours ?? DobaData.defaultEstimateHours
        if loggedHours > 0 { addManualEntry(taskID: id, hours: loggedHours, endingAt: now) }

        // Fully covered (or nothing logged) → done in place, no split.
        guard loggedHours > 0, loggedHours < estimate else {
            tasks[index].status = .done
            return true
        }

        // Partial: today's task is done for the hours worked …
        tasks[index].status = .done
        tasks[index].estimatedHours = loggedHours

        // … and a continuation carries the remainder to the next day.
        var continuation = tasks[index]
        continuation.id = UUID()
        continuation.status = .todo
        continuation.estimatedHours = max(0, estimate - loggedHours)
        continuation.isCarriedOver = true
        continuation.createdAt = now
        continuation.linkedEventID = nil
        continuation.recurrence = nil
        continuation.recurrenceID = nil
        let nextStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: tasks[index].scheduledDate) ?? tasks[index].scheduledDate)
        continuation.scheduledDate = nextStart
        if let slot = tasks[index].scheduledTime {
            let hm = calendar.dateComponents([.hour, .minute], from: slot)
            continuation.scheduledTime = calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: nextStart)
        }
        tasks.append(continuation)
        return true
    }

    /// Put a floating task onto today's timeline: set its day to today and give
    /// it a slot rounded up to the next 30 minutes (capped at 23:30). Returns
    /// true if found.
    @discardableResult
    public mutating func scheduleOnTimeline(id: UUID, at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let today = calendar.startOfDay(for: now)
        let total = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let rounded = min(((total + 29) / 30) * 30, 23 * 60 + 30)
        tasks[index].scheduledDate = today
        tasks[index].scheduledTime = calendar.date(bySettingHour: rounded / 60, minute: rounded % 60, second: 0, of: today)
        return true
    }

    // MARK: - NL import (Phase 4, pure)

    /// Turn parsed tasks (from the Claude NL parser) into real `DobaTask`s.
    /// Resolves project names case-insensitively against existing projects and
    /// creates any that are new (assigning palette colors). Bad/absent dates
    /// fall back to today; bad times fall back to floating. Returns the number
    /// of tasks added. Pure — the app fetches the parse from Claude and hands
    /// the decoded list here.
    @discardableResult
    public mutating func addParsedTasks(_ parsed: [ParsedTask], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = calendar.timeZone

        var added = 0
        for item in parsed {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            // Day: parse "yyyy-MM-dd" → start of that day; else today.
            let day = item.scheduledDate
                .flatMap { dayFormatter.date(from: $0) }
                .map { calendar.startOfDay(for: $0) }
                ?? calendar.startOfDay(for: now)

            // Project: reuse/create by name, else default to the Internal bucket.
            let projectID = resolveOrCreateProject(named: item.project) ?? ensureInternalProject()

            // Time: "HH:mm" on the resolved day → time-bound; else floating.
            var scheduledTime: Date?
            if let raw = item.scheduledTime, let hm = Self.parseClock(raw) {
                scheduledTime = calendar.date(bySettingHour: hm.hour, minute: hm.minute, second: 0, of: day)
            }

            tasks.append(DobaTask(
                title: title,
                projectID: projectID,
                scheduledDate: day,
                scheduledTime: scheduledTime,
                estimatedHours: item.estimatedHours ?? DobaData.defaultEstimateHours,
                // Rated project always wins; otherwise use the parser's guess.
                billable: projectIsBillable(projectID) ? true : (item.billable ?? false),
                source: .parsed
            ))
            added += 1
        }
        return added
    }

    /// Parse "HH:mm" / "H:mm" into hour+minute, or nil if malformed.
    private static func parseClock(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    // MARK: - Earnings (per-project rate, global fallback)

    /// Whether a task on `projectID` should default to billable — true when the
    /// project carries an hourly rate > 0 (client work). See DECISIONS D34.
    public func projectIsBillable(_ projectID: UUID?) -> Bool {
        guard let id = projectID, let project = projects.first(where: { $0.id == id }) else { return false }
        return (project.rate ?? 0) > 0
    }

    /// Find a project by name (case-insensitive) or create it with a palette
    /// color. nil/empty name → nil. Shared by the parser and meeting conversion.
    public mutating func resolveOrCreateProject(named name: String?) -> UUID? {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        if let existing = projects.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) {
            return existing.id
        }
        let project = Project(name: n, colorHex: Project.palette[projects.count % Project.palette.count])
        projects.append(project)
        return project.id
    }

    /// Enforce the rule "every task on a rated project is billable" across the
    /// whole store (rated project → billable; other tasks left as-is so manual
    /// billable flags survive). Returns how many were corrected. See DECISIONS D39.
    @discardableResult
    public mutating func normalizeBillableFromProjects() -> Int {
        var changed = 0
        for index in tasks.indices where projectIsBillable(tasks[index].projectID) && !tasks[index].billable {
            tasks[index].billable = true
            changed += 1
        }
        return changed
    }

    /// Effective hourly rate for a task: its project's rate if set, else the
    /// global `hourlyRate`, else 0.
    public func rate(forTaskID id: UUID) -> Double {
        guard let task = tasks.first(where: { $0.id == id }) else { return hourlyRate ?? 0 }
        if let pid = task.projectID, let project = projects.first(where: { $0.id == pid }),
           let r = project.rate {
            return r
        }
        return hourlyRate ?? 0
    }

    /// Projected earnings for `day` = Σ billable tasks' estimate × their rate.
    public func projectedEarnings(on day: Date, calendar: Calendar = .current) -> Double {
        tasks(on: day, calendar: calendar)
            .filter(\.billable)
            .reduce(0) { $0 + ($1.estimatedHours ?? 0) * rate(forTaskID: $1.id) }
    }

    /// The freelancer's pay period containing `date`: the 15th of one month to
    /// the 15th of the next (end exclusive). See DECISIONS D33.
    public static func payPeriod(containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = 15
        let fifteenth = calendar.startOfDay(for: calendar.date(from: comps) ?? date)
        if calendar.component(.day, from: date) >= 15 {
            return (fifteenth, calendar.date(byAdding: .month, value: 1, to: fifteenth) ?? fifteenth)
        } else {
            return (calendar.date(byAdding: .month, value: -1, to: fifteenth) ?? fifteenth, fifteenth)
        }
    }

    /// Logged hours (30-min floored) in `[start, end)` for tasks matching
    /// `billable` — the weekly/monthly billable & overhead totals.
    public func actualHours(from start: Date, to end: Date, billable: Bool, asOf now: Date = Date()) -> Double {
        timeEntries
            .filter { $0.start >= start && $0.start < end }
            .reduce(0) { sum, entry in
                guard let task = tasks.first(where: { $0.id == entry.taskID }), task.billable == billable else { return sum }
                return sum + DobaData.effectiveHours(entry, asOf: now)
            }
    }

    /// Logged billable hours in `[start, end)`.
    public func actualBillableHours(from start: Date, to end: Date, asOf now: Date = Date()) -> Double {
        actualHours(from: start, to: end, billable: true, asOf: now)
    }

    /// Auto-close a timer that's been running absurdly long (e.g. left on
    /// overnight): cap its recorded end at `start + maxHours`. Returns true if it
    /// stopped one. Guards against the runaway 40h-session problem. See D38.
    @discardableResult
    public mutating func autoStopStaleTimer(maxHours: Double = 12, asOf now: Date = Date()) -> Int {
        var stopped = 0
        for index in timeEntries.indices where timeEntries[index].end == nil {
            if now.timeIntervalSince(timeEntries[index].start) / 3600 > maxHours {
                timeEntries[index].end = timeEntries[index].start.addingTimeInterval(maxHours * 3600)
                stopped += 1
            }
        }
        return stopped
    }

    /// A summary of logged work over a date range — for the monthly report.
    public func periodReport(from start: Date, to end: Date, asOf now: Date = Date()) -> PeriodReport {
        var billable = 0.0, overhead = 0.0, earnings = 0.0
        var byProject: [UUID?: (hours: Double, earnings: Double)] = [:]
        for entry in timeEntries where entry.start >= start && entry.start < end {
            guard let task = tasks.first(where: { $0.id == entry.taskID }) else { continue }
            let hours = DobaData.effectiveHours(entry, asOf: now)
            if task.billable {
                billable += hours
                let money = hours * rate(forTaskID: task.id)
                earnings += money
                var line = byProject[task.projectID] ?? (0, 0)
                line.hours += hours; line.earnings += money
                byProject[task.projectID] = line
            } else {
                overhead += hours
            }
        }
        let lines = byProject.map { pid, value -> PeriodReport.ProjectLine in
            let project = pid.flatMap { id in projects.first { $0.id == id } }
            return .init(name: project?.name ?? "—", colorHex: project?.colorHex,
                         hours: value.hours, earnings: value.earnings)
        }.sorted { $0.hours > $1.hours }
        return PeriodReport(billableHours: billable, overheadHours: overhead,
                            earnings: earnings, projectLines: lines)
    }

    /// Earned money for `day` = Σ (entries started that day, billable task)
    /// effective hours × that task's rate.
    public func earnedEarnings(on day: Date, asOf now: Date = Date(), calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: day)
        return timeEntries
            .filter { calendar.isDate($0.start, inSameDayAs: start) }
            .reduce(0) { sum, entry in
                guard let task = tasks.first(where: { $0.id == entry.taskID }), task.billable else { return sum }
                return sum + DobaData.effectiveHours(entry, asOf: now) * rate(forTaskID: task.id)
            }
    }

    // MARK: - Recurrence (materialize forward)

    /// Generate missing recurring-task instances from each series' latest
    /// instance up to `endDate`. Idempotent — skips days that already have an
    /// instance in the series. Returns how many were created. See DECISIONS D27.
    @discardableResult
    public mutating func materializeRecurring(through endDate: Date, calendar: Calendar = .current) -> Int {
        let limit = calendar.startOfDay(for: endDate)
        // Group recurring tasks by series id.
        var series: [UUID: [DobaTask]] = [:]
        for task in tasks where task.recurrence != nil {
            let key = task.recurrenceID ?? task.id
            series[key, default: []].append(task)
        }

        var created = 0
        for (_, instances) in series {
            guard let template = instances.max(by: { $0.scheduledDate < $1.scheduledDate }),
                  let rule = template.recurrence else { continue }
            var existing = Set(instances.map { calendar.startOfDay(for: $0.scheduledDate) })

            var day = calendar.startOfDay(for: template.scheduledDate)
            var guardCount = 0
            while guardCount < 400 {
                guardCount += 1
                guard let next = Self.nextOccurrence(after: day, rule: rule, calendar: calendar) else { break }
                day = next
                if day > limit { break }
                if existing.contains(day) { continue }
                existing.insert(day)

                var copy = template
                copy.id = UUID()
                copy.scheduledDate = day
                copy.status = .todo
                copy.isCarriedOver = false
                copy.linkedEventID = nil
                copy.createdAt = Date()
                copy.recurrenceID = template.recurrenceID ?? template.id
                if let slot = template.scheduledTime {
                    let hm = calendar.dateComponents([.hour, .minute], from: slot)
                    copy.scheduledTime = calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day)
                }
                tasks.append(copy)
                created += 1
            }
        }
        return created
    }

    private static func nextOccurrence(after day: Date, rule: RecurrenceRule, calendar: Calendar) -> Date? {
        switch rule {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: day)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: day)
        case .weekdays:
            var d = day
            for _ in 0..<7 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { return nil }
                d = next
                let wd = calendar.component(.weekday, from: d) // 1=Sun … 7=Sat
                if wd != 1 && wd != 7 { return d }
            }
            return nil
        }
    }
}
