import SwiftUI
import DobaKit

/// Asks how many hours were actually worked when completing a task. Pre-fills
/// the planned estimate; the user overwrites it with what they report to the
/// client. Logging less than planned rolls the remainder to the next day
/// (handled in `DobaData.completeTask`). See DECISIONS D29.
struct CompleteTaskView: View {
    @EnvironmentObject private var store: DobaStore
    let task: DobaTask
    let onComplete: (Double) -> Void
    let onCancel: () -> Void

    @State private var hoursText: String
    @FocusState private var focused: Bool

    init(task: DobaTask, onComplete: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.task = task
        self.onComplete = onComplete
        self.onCancel = onCancel
        let planned = task.estimatedHours ?? DobaData.defaultEstimateHours
        _hoursText = State(initialValue: Self.format(planned))
    }

    private var planned: Double { task.estimatedHours ?? DobaData.defaultEstimateHours }
    private var alreadyLogged: Double { store.data.actualHours(forTaskID: task.id) }
    private var hours: Double {
        Double(hoursText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.borderless)
                Spacer()
                Text("Log time").font(.headline)
                Spacer()
                Button("Done", action: complete).buttonStyle(.borderless)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text(task.title).font(.headline)

                HStack(spacing: 10) {
                    Label("Planned \(Self.format(planned))h", systemImage: "target")
                    if alreadyLogged > 0 {
                        Label("Logged \(Self.format(alreadyLogged))h", systemImage: "stopwatch")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Worked").foregroundStyle(.secondary)
                    Button { bump(-0.5) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                    TextField("0", text: $hoursText)
                        .frame(width: 64).multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(complete)
                    Button { bump(0.5) } label: { Image(systemName: "plus.circle") }
                        .buttonStyle(.plain)
                    Text("h").foregroundStyle(.secondary)
                    Button("Planned") { hoursText = Self.format(planned) }
                        .buttonStyle(.borderless).font(.caption)
                }

                Text(hours < planned
                     ? "Less than planned — the remaining \(Self.format(max(0, planned - hours)))h rolls to tomorrow."
                     : "Covers the estimate — the task will be marked done.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: complete) {
                    Label("Log \(Self.format(hours))h & complete", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(12)
        }
        .frame(width: 360, height: 520)
        .onAppear { focused = true }
    }

    private func bump(_ delta: Double) {
        hoursText = Self.format(max(0, hours + delta))
    }

    private func complete() { onComplete(max(0, hours)) }

    private static func format(_ h: Double) -> String {
        h == h.rounded() ? String(Int(h)) : String(h)
    }
}
