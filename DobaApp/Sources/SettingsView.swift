import SwiftUI

/// In-panel settings: the Anthropic API key (Keychain) and earnings (hourly
/// rate + currency, persisted to the store via `onSaveEarnings`).
struct SettingsView: View {
    @State private var keyInput: String
    @State private var rateInput: String
    @State private var currencyInput: String
    @State private var savedTick = false

    let onSaveEarnings: (Double?, String) -> Void
    let onManageProjects: () -> Void
    let onClose: () -> Void

    init(initialRate: Double?,
         initialCurrency: String,
         onSaveEarnings: @escaping (Double?, String) -> Void,
         onManageProjects: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        _keyInput = State(initialValue: Keychain.apiKey ?? "")
        _rateInput = State(initialValue: initialRate.map(Self.format) ?? "")
        _currencyInput = State(initialValue: initialCurrency)
        self.onSaveEarnings = onSaveEarnings
        self.onManageProjects = onManageProjects
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Cancel", action: onClose).buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                Button("Save", action: save).buttonStyle(.borderless).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EARNINGS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        HStack {
                            Text("Hourly rate")
                            Spacer()
                            TextField("0", text: $rateInput)
                                .frame(width: 70).multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            TextField("$", text: $currencyInput)
                                .frame(width: 44).multilineTextAlignment(.center)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Used to show projected/earned money from billable hours. Leave blank to hide earnings.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROJECTS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Button {
                            // Persist earnings before leaving so edits aren't lost.
                            Keychain.set(keyInput)
                            onSaveEarnings(Self.parseRate(rateInput), currencyInput.trimmingCharacters(in: .whitespaces))
                            onManageProjects()
                        } label: {
                            Label("Manage projects", systemImage: "folder")
                        }
                        .buttonStyle(.borderless)
                        Text("Rename, recolor, set per-project rates, delete.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANTHROPIC API KEY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        SecureField("sk-ant-…", text: $keyInput).textFieldStyle(.roundedBorder)
                        Text("For parsing tasks (the ✨ button). Stored in your macOS Keychain — never in the project files.")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            if savedTick {
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            Spacer()
                            Button("Clear key", role: .destructive) {
                                Keychain.clear(); keyInput = ""; savedTick = false
                            }
                            .buttonStyle(.borderless).font(.caption).disabled(keyInput.isEmpty)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 520)
    }

    private func save() {
        Keychain.set(keyInput)
        onSaveEarnings(Self.parseRate(rateInput), currencyInput.trimmingCharacters(in: .whitespaces))
        savedTick = true
        onClose()
    }

    private static func format(_ rate: Double) -> String {
        rate == rate.rounded() ? String(Int(rate)) : String(rate)
    }

    private static func parseRate(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let v = Double(cleaned), v >= 0 else { return nil }
        return v
    }
}
