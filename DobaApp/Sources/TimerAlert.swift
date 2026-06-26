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
    /// Held while any countdown is armed so App Nap can't throttle the main-queue
    /// auto-stop timer — otherwise a backgrounded Doba may fire the in-app stop
    /// (and the panel/alert) late while the system notification arrives on time.
    /// `…AllowingIdleSystemSleep` keeps the Mac free to sleep normally. See D47.
    private static var activityToken: NSObjectProtocol?

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
            // Besides stopping, announce it so the panel pops open with a banner —
            // the system notification alone is easy to miss mid-call. See D47.
            let taskID = task.id
            let limit = estimate
            let work = DispatchWorkItem {
                if let t = DobaStore.shared.data.tasks.first(where: { $0.id == taskID }) {
                    DobaStore.shared.stopTimer(t)
                    DobaStore.shared.announceTimerFinished(taskID: t.id, taskTitle: t.title, limitHours: limit)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                stops[taskID] = nil
                sync()
            }
            stops[taskID] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
        }

        updateAppNapAssertion(active: !stops.isEmpty)
    }

    /// Begin/end the App Nap assertion to match whether any countdown is armed.
    private static func updateAppNapAssertion(active: Bool) {
        if active, activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Per-task timer countdown is running"
            )
        } else if !active, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    private static func hoursLabel(_ h: Double) -> String {
        (h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)) + "ч"
    }
}
