import Foundation

#if canImport(os)
import os
#endif

/// Low-level persistence: load/save the whole `DobaData` document as one JSON
/// file. Deliberately plain and synchronous — the dataset is tiny. Lives
/// outside the main-actor `DobaStore` so the widget's timeline provider (which
/// runs off the main thread) can read it directly without touching UI state.
public enum DobaStorage {
    private static let fileName = "doba.json"

    private static let logger = Logger(subsystem: "com.andreyrozumny.Doba", category: "store")

    /// Directory holding the JSON file: the app's own **Application Support**
    /// folder (for the sandboxed app, that's inside its container). The App Group
    /// container was dropped — it's unreliable on a free Apple account and only
    /// the (parked) widget needed sharing. See DECISIONS D36.
    public static func storeDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Doba", isDirectory: true)
    }

    public static func fileURL() -> URL {
        storeDirectory().appendingPathComponent(fileName)
    }

    /// The pre-D36 location (App Group container) — kept only to migrate old data.
    private static func legacyAppGroupFileURL() -> URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    /// One-time move: if there's no store in the app's own folder yet but an old
    /// App Group file exists, copy it across. Safe to call repeatedly. D36.
    public static func migrateFromAppGroupIfNeeded() {
        let target = fileURL()
        guard !FileManager.default.fileExists(atPath: target.path),
              let legacy = legacyAppGroupFileURL(),
              FileManager.default.fileExists(atPath: legacy.path) else { return }
        do {
            try FileManager.default.createDirectory(at: storeDirectory(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: legacy, to: target)
            logger.notice("Migrated store from App Group to Application Support.")
        } catch {
            logger.error("Store migration from App Group failed: \(error.localizedDescription)")
        }
    }

    /// Log how the store resolves in THIS process, so DobaApp and DobaWidget can
    /// be compared. Open Console.app and filter on subsystem
    /// `com.andreyrozumny.Doba` (category `store`); when running the app from
    /// Xcode it also prints to the debug console. `context` names the caller.
    /// If `container=<nil>` here, the App Group isn't resolving and the two
    /// processes are reading different files.
    public static func logDiagnostics(context: String) {
        let container = AppGroup.containerURL
        let containerPath = container?.path ?? "<nil — App Group not resolving>"
        logger.notice("[\(context, privacy: .public)] appGroup=\(AppGroup.identifier, privacy: .public) container=\(containerPath, privacy: .public) sharing=\(container != nil, privacy: .public) file=\(fileURL().path, privacy: .public)")
    }

    /// TEMP DIAGNOSTIC (Phase 5 widget debugging): write a marker into whatever
    /// directory THIS process resolves as the store directory, recording the
    /// App Group container it sees and whether the store file is visible. By
    /// inspecting where the file lands (shared Group container vs the process's
    /// own sandbox) we learn whether the widget extension actually shares the
    /// app's container. Remove once the widget is confirmed working.
    public static func writeDiagnostics(context: String) {
        let dir = storeDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var taskCount = -1
        if let loaded = (try? load()) ?? nil { taskCount = loaded.tasks.count }
        let info = """
        context=\(context)
        appGroupID=\(AppGroup.identifier)
        containerURL=\(AppGroup.containerURL?.path ?? "<nil>")
        storeDir=\(dir.path)
        storeFileExists=\(FileManager.default.fileExists(atPath: fileURL().path))
        tasksRead=\(taskCount)
        """
        try? info.write(to: dir.appendingPathComponent("\(context)-diag.txt"),
                        atomically: true, encoding: .utf8)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Human-readable on disk — easy to inspect/debug, which is the whole
        // reason we chose a JSON file over an opaque store.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Load the document. Returns `nil` if there's simply no file yet (caller
    /// decides whether to seed). Throws only on a *corrupt* file so real
    /// problems aren't silently swallowed.
    public static func load() throws -> DobaData? {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try makeDecoder().decode(DobaData.self, from: data)
    }

    public static func save(_ data: DobaData) throws {
        // Safety net: never clobber a non-empty store with a completely empty
        // document (e.g. if something tried to save while the store was in a
        // failed-load empty state). See DECISIONS D35.
        if data.tasks.isEmpty, data.projects.isEmpty, data.timeEntries.isEmpty,
           let existing = try? Data(contentsOf: fileURL()), existing.count > 40 {
            logger.error("Refusing to overwrite existing store with an empty document.")
            return
        }
        let dir = storeDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoded = try makeEncoder().encode(data)
        // Atomic write so a crash mid-save can't leave a half-written file.
        try encoded.write(to: fileURL(), options: .atomic)
    }
}

/// The app-facing, observable store. Owns the in-memory `DobaData` and persists
/// on every mutation. `@MainActor` because it drives SwiftUI.
///
/// Scope note: in Phase 0 this only loads/seeds and offers a single `toggle`
/// to smoke-test the read→write→reload loop. Real task CRUD, carry-over,
/// rollups, timer, etc. arrive in later phases.
@MainActor
public final class DobaStore: ObservableObject {
    public static let shared = DobaStore()

    private let logger = Logger(subsystem: "com.andreyrozumny.Doba", category: "store")

    @Published public private(set) var data: DobaData

    /// True when the store file **exists but couldn't be read/decoded** at launch
    /// (a transient App Group read glitch). While true we refuse to persist, so an
    /// empty fallback can't overwrite the real data. See DECISIONS D35.
    @Published public private(set) var loadFailed = false

    /// Load what's on disk. A genuinely-missing file is fine (start empty); a file
    /// that exists but won't read is held as a *failure* — we don't persist over it.
    public init() {
        DobaStorage.migrateFromAppGroupIfNeeded()
        do {
            self.data = try DobaStorage.load() ?? .empty
        } catch {
            self.data = .empty
            self.loadFailed = true
            logger.error("Store load failed at launch — holding off on saves to protect existing data: \(error.localizedDescription)")
        }
    }

    /// Re-read from disk. On success, refresh and clear the failure flag. On a
    /// read error (existing file unreadable), **keep current in-memory data** —
    /// never fall back to empty, which could later be persisted over good data.
    public func reload() {
        do {
            if let loaded = try DobaStorage.load() {
                data = loaded
                loadFailed = false
            }
            // nil → no file yet; keep whatever we have.
        } catch {
            logger.error("Store reload failed — keeping current in-memory data.")
        }
    }

    // MARK: - Read helpers (delegate to the pure queries on DobaData)

    public func project(for task: DobaTask) -> Project? {
        data.project(for: task)
    }

    /// Tasks scheduled for the given day (defaults to today).
    public func tasks(on day: Date = Date(), calendar: Calendar = .current) -> [DobaTask] {
        data.tasks(on: day, calendar: calendar)
    }

    // MARK: - Day roll

    /// Carry unfinished past-day tasks onto today. Call at launch (and on a
    /// day change). Persists only if something actually moved.
    @discardableResult
    public func carryOverUnfinished(asOf today: Date = Date()) -> Int {
        let moved = data.carryOverUnfinished(asOf: today)
        if moved > 0 {
            persist()
            logger.notice("Carried over \(moved) unfinished task(s) to today.")
        }
        return moved
    }

    // MARK: - Task mutations

    public func addTask(_ task: DobaTask) {
        data.tasks.append(task)
        persist()
    }

    /// Quick-add a bare task: defaults to a 30-min estimate and the Internal
    /// project when none is given. Used by quick-add and the global hotkey.
    public func addQuickTask(title: String, on day: Date = Date()) {
        let projectID = data.ensureInternalProject()
        data.tasks.append(DobaTask(
            title: title,
            projectID: projectID,
            scheduledDate: Calendar.current.startOfDay(for: day),
            estimatedHours: DobaData.defaultEstimateHours
        ))
        persist()
    }

    /// Mark a task complete with the hours worked (logs them; rolls the
    /// remainder to tomorrow if it's less than the estimate). See DECISIONS D29.
    public func completeTask(_ task: DobaTask, loggedHours: Double, now: Date = Date()) {
        if data.completeTask(id: task.id, loggedHours: loggedHours, now: now) { persist() }
    }

    /// Replace a task by id (no-op if it's gone).
    public func updateTask(_ task: DobaTask) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[index] = task
        persist()
    }

    public func deleteTask(_ task: DobaTask) {
        data.tasks.removeAll { $0.id == task.id }
        // Drop any time entries pointing at it (TimeEntry lands in Phase 3;
        // harmless to guard now).
        data.timeEntries.removeAll { $0.taskID == task.id }
        persist()
    }

    /// Flip a task between todo/done.
    public func toggleStatus(_ task: DobaTask) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[index].status = data.tasks[index].status == .done ? .todo : .done
        persist()
    }

    // MARK: - Project mutations

    public func addProject(_ project: Project) {
        data.projects.append(project)
        persist()
    }

    public func updateProject(_ project: Project) {
        guard let index = data.projects.firstIndex(where: { $0.id == project.id }) else { return }
        data.projects[index] = project
        data.normalizeBillableFromProjects()   // a rate change can flip tasks to billable
        persist()
    }

    /// Enforce "rated project ⇒ billable" across all tasks; persists if anything
    /// changed. Call at launch / panel appear.
    @discardableResult
    public func normalizeBillable() -> Int {
        let changed = data.normalizeBillableFromProjects()
        if changed > 0 { persist() }
        return changed
    }

    /// Delete a project; tasks that referenced it survive, just untagged.
    public func deleteProject(_ project: Project) {
        data.projects.removeAll { $0.id == project.id }
        for index in data.tasks.indices where data.tasks[index].projectID == project.id {
            data.tasks[index].projectID = nil
        }
        persist()
    }

    // MARK: - Time tracking

    /// True when `task` has a running timer (timers run in parallel).
    public func isTiming(_ task: DobaTask) -> Bool {
        data.isRunning(taskID: task.id)
    }

    /// Start or stop this task's timer (independent of other tasks' timers).
    public func toggleTimer(for task: DobaTask, at now: Date = Date()) {
        if data.isRunning(taskID: task.id) {
            data.stopTimer(taskID: task.id, at: now)
        } else {
            data.startTimer(taskID: task.id, at: now)
        }
        persist()
    }

    /// Stop one task's timer (used by the auto-stop-at-limit scheduler).
    public func stopTimer(_ task: DobaTask, at now: Date = Date()) {
        if data.stopTimer(taskID: task.id, at: now) { persist() }
    }

    public func stopAllTimers(at now: Date = Date()) {
        if data.stopAllTimers(at: now) > 0 { persist() }
    }

    /// Close timers left running too long (call at launch / panel appear).
    @discardableResult
    public func autoStopStaleTimer(maxHours: Double = 12) -> Int {
        let stopped = data.autoStopStaleTimer(maxHours: maxHours)
        if stopped > 0 { persist() }
        return stopped
    }

    /// Add a manual closed entry (forgot-to-start correction).
    public func addManualTime(to task: DobaTask, hours: Double, endingAt now: Date = Date()) {
        data.addManualEntry(taskID: task.id, hours: hours, endingAt: now)
        persist()
    }

    public func deleteTimeEntry(_ entry: TimeEntry) {
        data.deleteTimeEntry(id: entry.id)
        persist()
    }

    // MARK: - NL import (Phase 4)

    /// Add tasks produced by the Claude NL parser; returns how many were added.
    @discardableResult
    public func importParsedTasks(_ parsed: [ParsedTask], now: Date = Date()) -> Int {
        let added = data.addParsedTasks(parsed, now: now)
        data.normalizeBillableFromProjects()
        if added > 0 { persist() }
        return added
    }

    // MARK: - Earnings settings & moving

    public func setEarnings(rate: Double?, currency: String) {
        data.hourlyRate = rate
        data.currency = currency.trimmingCharacters(in: .whitespaces).isEmpty ? nil : currency
        persist()
    }

    /// Move a task forward/back by `days` (e.g. +1 = push to next day).
    public func moveTask(_ task: DobaTask, byDays days: Int) {
        if data.shiftTask(id: task.id, byDays: days) { persist() }
    }

    /// Put a floating task onto today's timeline (next half-hour slot).
    public func scheduleToday(_ task: DobaTask, at now: Date = Date()) {
        if data.scheduleOnTimeline(id: task.id, at: now) { persist() }
    }

    /// Reverse: drop a task's slot so it goes back to the floating pool.
    public func moveToFloating(_ task: DobaTask) {
        guard let i = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[i].scheduledTime = nil
        persist()
    }

    /// Create a task from a calendar meeting. Project + billable come from the
    /// (Claude-parsed) title; time/duration/link come from the meeting.
    public func addMeetingTask(title: String, projectName: String?, parsedBillable: Bool?,
                               start: Date, hours: Double, eventID: String) {
        let projectID = data.resolveOrCreateProject(named: projectName)
        let billable = data.projectIsBillable(projectID) ? true : (parsedBillable ?? false)
        data.tasks.append(DobaTask(
            title: title, projectID: projectID,
            scheduledDate: Calendar.current.startOfDay(for: start), scheduledTime: start,
            estimatedHours: hours, billable: billable, linkedEventID: eventID))
        persist()
    }

    /// Fill in recurring-task instances up to `endDate` (call at launch).
    @discardableResult
    public func materializeRecurring(through endDate: Date) -> Int {
        let created = data.materializeRecurring(through: endDate)
        if created > 0 { persist() }
        return created
    }

    private func persist() {
        // Don't write while the store didn't load cleanly — protects the file
        // from being overwritten with a transient empty state.
        guard !loadFailed else {
            logger.error("Skipping save — store didn't load cleanly; not overwriting existing data.")
            return
        }
        do {
            try DobaStorage.save(data)
        } catch {
            // No UI for errors yet; surface in the log so it's not invisible.
            logger.error("Failed to save store: \(error.localizedDescription)")
        }
    }
}
