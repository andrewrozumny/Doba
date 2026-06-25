import Foundation

/// Dummy content for the Phase 0 skeleton, so the menu bar and the widget have
/// something real to render before any data-entry UI exists. Seeded into a
/// fresh store on first run. Will be removed once Phase 1 brings real task
/// creation.
public enum SampleData {
    public static func makeSeed(today: Date = Date(), calendar: Calendar = .current) -> DobaData {
        let day = calendar.startOfDay(for: today)

        let acme = Project(name: "Acme", colorHex: "#4F8EF7")
        let internalProj = Project(name: "Internal", colorHex: "#9B59B6")

        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let tasks: [DobaTask] = [
            // Time-bound (timeline) — billable client work.
            DobaTask(
                title: "Acme: ship invoice API",
                projectID: acme.id,
                scheduledDate: day,
                scheduledTime: at(10, 0),
                estimatedHours: 3,
                billable: true
            ),
            // Floating pool — billable, no fixed slot.
            DobaTask(
                title: "Acme: write release notes",
                projectID: acme.id,
                scheduledDate: day,
                estimatedHours: 1,
                billable: true
            ),
            // Floating pool — overhead (not billable), carried over from before.
            DobaTask(
                title: "Update personal site",
                projectID: internalProj.id,
                scheduledDate: day,
                estimatedHours: 2,
                billable: false,
                isCarriedOver: true
            )
        ]

        return DobaData(
            projects: [acme, internalProj],
            tasks: tasks,
            timeEntries: []
        )
    }
}
