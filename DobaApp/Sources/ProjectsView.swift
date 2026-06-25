import SwiftUI
import DobaKit

/// Manage projects: rename, recolor (tap the swatch to cycle the palette), set a
/// per-project hourly rate (overrides the global rate), add, delete. Edits write
/// straight through to the store.
struct ProjectsView: View {
    @EnvironmentObject private var store: DobaStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Done", action: onClose).buttonStyle(.borderless).keyboardShortcut(.defaultAction)
                Spacer()
                Text("Projects").font(.headline)
                Spacer()
                Button(action: addProject) { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add project")
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()

            if store.data.projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "folder",
                    description: Text("Add one with +, or they're created automatically when you tag a task.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        HStack {
                            Spacer()
                            Text("rate").font(.caption2).foregroundStyle(.secondary).frame(width: 60)
                            Spacer().frame(width: 26)
                        }
                        ForEach(store.data.projects) { project in row(project) }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 360, height: 520)
    }

    private func row(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Button { cycleColor(project) } label: {
                Circle().fill(Color(hex: project.colorHex) ?? .gray).frame(width: 14, height: 14)
            }
            .buttonStyle(.plain).help("Change color")

            TextField("Name", text: nameBinding(project)).textFieldStyle(.roundedBorder)

            TextField("—", text: rateBinding(project))
                .frame(width: 60).multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .help("Per-project hourly rate (overrides the global rate)")

            Button(role: .destructive) { store.deleteProject(project) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain).foregroundStyle(.red).help("Delete project")
        }
    }

    // MARK: - Live bindings

    private func nameBinding(_ p: Project) -> Binding<String> {
        Binding(get: { p.name }, set: { var x = p; x.name = $0; store.updateProject(x) })
    }

    private func rateBinding(_ p: Project) -> Binding<String> {
        Binding(
            get: { p.rate.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "" },
            set: {
                var x = p
                let cleaned = $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                x.rate = (cleaned.isEmpty ? nil : Double(cleaned)).flatMap { $0 >= 0 ? $0 : nil }
                store.updateProject(x)
            }
        )
    }

    private func cycleColor(_ p: Project) {
        let palette = Project.palette
        let idx = palette.firstIndex(of: p.colorHex) ?? -1
        var x = p
        x.colorHex = palette[(idx + 1) % palette.count]
        store.updateProject(x)
    }

    private func addProject() {
        let color = Project.palette[store.data.projects.count % Project.palette.count]
        store.addProject(Project(name: "New project", colorHex: color))
    }
}
