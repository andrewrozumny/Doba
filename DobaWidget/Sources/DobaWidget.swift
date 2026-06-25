import WidgetKit
import SwiftUI
import DobaKit

/// The widget bundle entry point. One widget for now; App-Intent-powered
/// checkbox toggling arrives in Phase 5.
@main
struct DobaWidgetBundle: WidgetBundle {
    // TEMP DIAGNOSTIC: runs the instant the extension process launches, so we
    // capture the container the widget resolves even if WidgetKit never calls
    // getTimeline. Remove once the widget is confirmed working.
    init() {
        DobaStorage.writeDiagnostics(context: "DobaWidgetLaunch")
    }

    var body: some Widget {
        DobaTodayWidget()
    }
}

struct DobaTodayWidget: Widget {
    let kind = "DobaTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DobaTimelineProvider()) { entry in
            DobaWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your plan for today at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct DobaEntry: TimelineEntry {
    let date: Date
    let tasks: [DobaTask]
    let projects: [Project]

    func project(for task: DobaTask) -> Project? {
        guard let id = task.projectID else { return nil }
        return projects.first { $0.id == id }
    }
}

struct DobaTimelineProvider: TimelineProvider {
    /// Gallery/loading placeholder ONLY — sample data, never the live store.
    func placeholder(in context: Context) -> DobaEntry {
        Self.entry(from: SampleData.makeSeed())
    }

    /// Reads the real shared store. No sample fallback here on purpose — if the
    /// store is empty (e.g. App Group not shared), the widget shows empty so a
    /// broken share is visible instead of being masked by sample data.
    func getSnapshot(in context: Context, completion: @escaping (DobaEntry) -> Void) {
        completion(Self.entry(from: Self.loadSharedStore()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DobaEntry>) -> Void) {
        DobaStorage.logDiagnostics(context: "DobaWidget")
        DobaStorage.writeDiagnostics(context: "DobaWidget")
        // One entry; the app pushes fresh data via reloadAllTimelines() after
        // every write, and `.atEnd` lets WidgetKit refresh us around day-roll.
        let timeline = Timeline(entries: [Self.entry(from: Self.loadSharedStore())], policy: .atEnd)
        completion(timeline)
    }

    /// The real shared store, or an empty document if there's nothing to read.
    /// Deliberately does NOT fall back to sample data — that would hide whether
    /// app↔widget sharing actually works (the whole point of Phase 0 verification).
    private static func loadSharedStore() -> DobaData {
        ((try? DobaStorage.load()) ?? nil) ?? .empty
    }

    private static func entry(from data: DobaData, now: Date = Date()) -> DobaEntry {
        DobaEntry(date: now, tasks: data.tasks(on: now), projects: data.projects)
    }
}

// MARK: - View

struct DobaWidgetView: View {
    var entry: DobaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.tasks.isEmpty {
                Spacer()
                Text("Nothing scheduled")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(5)) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.status == .done ? Color.accentColor : Color.secondary)
                        Text(task.title)
                            .lineLimit(1)
                            .strikethrough(task.status == .done)
                            .foregroundStyle(task.status == .done ? .secondary : .primary)
                        Spacer(minLength: 0)
                        if let slot = task.scheduledTime {
                            Text(slot, format: .dateTime.hour().minute())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                if entry.tasks.count > 5 {
                    Text("+\(entry.tasks.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
