import Foundation
import UserNotifications
import WidgetKit
import DobaKit

/// Per-task countdown: when a running timer reaches the task's estimate it is
/// **auto-stopped** and a system alert (banner + sound, over all apps) fires.
/// Timers run in parallel, so this keeps one pending alert + one auto-stop per
/// running task, re-synced on every change. See DECISIONS D37 / D42.
@MainActor
enum TimerScheduler {
    private static let prefix = "doba.timer."
    private static var stops: [UUID: DispatchWorkItem] = [:]
    private static var scheduledNotifIDs: Set<String> = []

    /// Ask once (at launch) for permission to show alerts + play sound.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Re-sync alerts + auto-stops to the current running timers.
    static func sync(now: Date = Date()) {
        stops.values.forEach { $0.cancel() }
        stops.removeAll()

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Array(scheduledNotifIDs))
        scheduledNotifIDs.removeAll()

        let data = DobaStore.shared.data
        for entry in data.runningEntries {
            guard let task = data.tasks.first(where: { $0.id == entry.taskID }),
                  let estimate = task.estimatedHours, estimate > 0 else { continue }
            let remaining = estimate * 3600 - now.timeIntervalSince(entry.start)

            // Already past the limit → stop immediately (e.g. at launch).
            guard remaining > 0 else {
                DobaStore.shared.stopTimer(task)
                continue
            }

            let notifID = prefix + task.id.uuidString
            let content = UNMutableNotificationContent()
            content.title = "⏰ Время вышло"
            content.body = "«\(task.title)» — достигнут лимит \(hoursLabel(estimate)). Таймер остановлен."
            content.sound = .default
            content.interruptionLevel = .active
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            center.add(UNNotificationRequest(identifier: notifID, content: content, trigger: trigger))
            scheduledNotifIDs.insert(notifID)

            // In-app auto-stop at the limit (the menu-bar app is always alive).
            let taskID = task.id
            let work = DispatchWorkItem {
                if let t = DobaStore.shared.data.tasks.first(where: { $0.id == taskID }) {
                    DobaStore.shared.stopTimer(t)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                stops[taskID] = nil
                sync()
            }
            stops[taskID] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
        }
    }

    private static func hoursLabel(_ h: Double) -> String {
        (h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)) + "ч"
    }
}
