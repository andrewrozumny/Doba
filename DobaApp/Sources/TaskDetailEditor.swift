import SwiftUI
import WidgetKit
import DobaKit

/// In-panel editor for a task's four axes: project / hours / time / billable
/// (plus title and delete). Edits a local `draft` copy so Cancel discards;
/// Save / Delete write through the store and dismiss back to the list.
struct TaskDetailEditor: View {
    @EnvironmentObject private var store: DobaStore

    @State private var draft: DobaTask
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var hoursText: String

    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectColor = ProjectPalette.hexes[0]
    @State private var manualHoursText = ""

    /// Called to return to the list (after Save / Delete / Cancel).
    let onClose: () -> Void

    init(task: DobaTask, onClose: @escaping () -> Void) {
        _draft = State(initialValue: task)
        _hasTime = State(initialValue: task.scheduledTime != nil)
        _time = State(initialValue: task.scheduledTime ?? defaultSlot(on: task.scheduledDate))
        _hoursText = State(initialValue: task.estimatedHours.map(formatHours) ?? "")
        self.onClose = onClose
    }

    private var trimmedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Save/Cancel stay pinned at the top so they're always reachable,
            // regardless of how tall the form gets.
            toolbar
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)

                    LabeledContent("Day") {
                        HStack(spacing: 6) {
                            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.borderless)
                            Text(dayLabel(draft.scheduledDate))
                                .font(.callout).frame(minWidth: 96)
                            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.borderless)
                        }
                    }

                    projectField

                    LabeledContent("Estimate") {
                        HStack(spacing: 4) {
                            TextField("—", text: $hoursText)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            Text("h").foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Scheduled time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.field)
                            .labelsHidden()
                    }

                    // On a rated project, billable is forced on (the rule);
                    // otherwise it's a manual toggle.
                    Toggle("Billable", isOn: Binding(
                        get: { store.data.projectIsBillable(draft.projectID) || draft.billable },
                        set: { draft.billable = $0 }
                    ))
                    .disabled(store.data.projectIsBillable(draft.projectID))
                    .help(store.data.projectIsBillable(draft.projectID) ? "Проект со ставкой — всегда billable" : "")

                    LabeledContent("Repeat") {
                        Picker("", selection: recurrenceBinding) {
                            Text("Never").tag(RecurrenceRule?.none)
                            ForEach(RecurrenceRule.allCases, id: \.self) { rule in
                                Text(rule.label).tag(RecurrenceRule?.some(rule))
                            }
                        }
                        .labelsHidden()
                    }

                    Divider()
                    timeSection

                    Divider()
                    Button(role: .destructive, action: delete) {
                        Label("Delete Task", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Same fixed size as the list, so switching list <-> editor never makes
        // the MenuBarExtra window jump/resize.
        .frame(width: 360, height: 520)
    }

    // MARK: - Time tracking section

    private var isTiming: Bool { store.isTiming(draft) }
    private var entries: [TimeEntry] { store.data.entries(forTaskID: draft.id) }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIME").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.data.actualHours(forTaskID: draft.id), format: .number)h actual")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    store.toggleTimer(for: draft)
                    TimerScheduler.sync()
                    WidgetCenter.shared.reloadAllTimelines()
                } label: {
                    Label(isTiming ? "Stop timer" : "Start timer",
                          systemImage: isTiming ? "stop.circle.fill" : "play.circle")
                }
                .tint(isTiming ? .red : .accentColor)

                Spacer()

                // Manual correction: add a closed entry of N hours.
                TextField("0.5", text: $manualHoursText)
                    .frame(width: 48)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("h").foregroundStyle(.secondary)
                Button("Add", action: addManualTime)
                    .disabled(parseHours(manualHoursText) == nil)
            }

            if !entries.isEmpty {
                ForEach(entries) { entry in
                    HStack {
                        if let end = entry.end {
                            Text("\(entry.start, format: .dateTime.hour().minute()) – \(end, format: .dateTime.hour().minute())")
                                .font(.caption.monospacedDigit())
                            Spacer()
                            Text("\(DobaData.effectiveHours(entry, asOf: end), format: .number)h")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(entry.start, format: .dateTime.hour().minute()) – running")
                                .font(.caption.monospacedDigit()).foregroundStyle(.red)
                            Spacer()
                        }
                        Button {
                            store.deleteTimeEntry(entry)
                            WidgetCenter.shared.reloadAllTimelines()
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func addManualTime() {
        guard let hours = parseHours(manualHoursText) else { return }
        store.addManualTime(to: draft, hours: hours)
        WidgetCenter.shared.reloadAllTimelines()
        manualHoursText = ""
    }

    private func shiftDay(_ days: Int) {
        let cal = Calendar.current
        if let d = cal.date(byAdding: .day, value: days, to: draft.scheduledDate) {
            draft.scheduledDate = cal.startOfDay(for: d)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onClose).buttonStyle(.borderless)
            Spacer()
            Text("Edit Task").font(.headline)
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.borderless)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
        }
    }

    // MARK: - Project picker + inline create

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Project", selection: projectBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.data.projects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    withAnimation { showingNewProject.toggle() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New project")
            }

            if showingNewProject {
                HStack(spacing: 8) {
                    TextField("New project", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                    ForEach(ProjectPalette.hexes, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle().strokeBorder(.primary, lineWidth: newProjectColor == hex ? 2 : 0)
                            )
                            .onTapGesture { newProjectColor = hex }
                    }
                    Button("Add", action: addProject)
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var projectBinding: Binding<UUID?> {
        Binding(get: { draft.projectID }, set: { newID in
            draft.projectID = newID
            // Billable follows the project's rate (client project → billable).
            draft.billable = store.data.projectIsBillable(newID)
        })
    }

    private var recurrenceBinding: Binding<RecurrenceRule?> {
        Binding(get: { draft.recurrence }, set: { draft.recurrence = $0 })
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = Project(name: name, colorHex: newProjectColor)
        store.addProject(project)
        draft.projectID = project.id
        newProjectName = ""
        showingNewProject = false
    }

    // MARK: - Commit

    private func save() {
        var task = draft
        task.title = trimmedTitle
        task.estimatedHours = parseHours(hoursText)
        task.scheduledTime = hasTime ? merge(time: time, into: task.scheduledDate) : nil
        // A newly-recurring task seeds its own series id.
        if task.recurrence != nil, task.recurrenceID == nil { task.recurrenceID = task.id }
        store.updateTask(task)
        if task.recurrence != nil {
            store.materializeRecurring(through: DobaApp.recurrenceHorizon())
        }
        WidgetCenter.shared.reloadAllTimelines()
        onClose()
    }

    private func delete() {
        store.deleteTask(draft)
        WidgetCenter.shared.reloadAllTimelines()
        onClose()
    }
}

/// Preset colors offered when creating a project inline.
enum ProjectPalette {
    static let hexes = ["#4F8EF7", "#9B59B6", "#2ECC71", "#E67E22", "#E74C3C", "#1ABC9C"]
}

// File-level helpers (usable from `init`, before `self` exists).

private func defaultSlot(on day: Date) -> Date {
    Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
}

private func formatHours(_ hours: Double) -> String {
    hours == hours.rounded() ? String(Int(hours)) : String(hours)
}

private func parseHours(_ text: String) -> Double? {
    let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
    return value
}

/// Combine the clock time the user picked with the task's day.
private func merge(time: Date, into day: Date) -> Date {
    let cal = Calendar.current
    let hm = cal.dateComponents([.hour, .minute], from: time)
    return cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0,
                    of: cal.startOfDay(for: day)) ?? day
}
