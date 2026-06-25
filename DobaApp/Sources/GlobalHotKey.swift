import AppKit
import SwiftUI
import Carbon.HIToolbox
import WidgetKit
import UserNotifications
import DobaKit

/// App delegate: registers a system-wide hotkey (⌃⌥D) for quick-capture, and
/// wires up local notifications so the per-task countdown can alert over all apps.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let quickCapture = QuickCaptureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        TimerScheduler.requestAuthorization()
        TimerScheduler.sync()   // re-arm alerts/auto-stops for any running timers
        registerHotKey()
    }

    /// Show timer alerts as a banner + sound even while Doba is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in delegate.quickCapture.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let hotKeyID = EventHotKeyID(signature: 0x444F4241 /* "DOBA" */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

/// Owns a floating quick-capture panel shown by the global hotkey.
@MainActor
private final class QuickCaptureController {
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private func show() {
        let view = QuickCaptureView(
            onParse: { [weak self] text in await self?.parse(text) },
            onCancel: { [weak self] in self?.panel?.orderOut(nil) }
        )
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 70),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        return panel
    }

    /// Enter / ✨ — send the text to Claude and import the parsed tasks. If the
    /// parse fails (no key, offline, empty), fall back to a plain quick-add so
    /// nothing typed is lost.
    private func parse(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { panel?.orderOut(nil); return }
        let names = DobaStore.shared.data.projects.map(\.name)
        if let parsed = try? await ClaudeClient.parse(trimmed, knownProjects: names), !parsed.isEmpty {
            DobaStore.shared.importParsedTasks(parsed)
        } else {
            DobaStore.shared.addQuickTask(title: trimmed)
        }
        WidgetCenter.shared.reloadAllTimelines()
        panel?.orderOut(nil)
    }
}

private struct QuickCaptureView: View {
    @State private var text = ""
    @State private var isParsing = false
    @FocusState private var focused: Bool
    let onParse: (String) async -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(.secondary)
            TextField("Задача, проект, 2h, 14:00 — Enter отправит в ✨", text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .disabled(isParsing)
                .onSubmit(runParse)
            if isParsing {
                ProgressView().controlSize(.small)
            } else {
                Button(action: runParse) { Image(systemName: "sparkles").font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Parse with Claude")
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 480, height: 70)
        .background(.ultraThinMaterial)
        .onAppear { focused = true }
        .onExitCommand(perform: onCancel)
    }

    private func runParse() {
        let snapshot = text
        guard !snapshot.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isParsing = true
        Task { await onParse(snapshot); isParsing = false }
    }
}
