import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import WidgetKit
import UserNotifications
import DobaKit

/// App delegate: owns the menu-bar status item + the panel popover, registers a
/// system-wide hotkey (⌃⌥D) for quick-capture, and wires up local notifications
/// so the per-task countdown can alert over all apps.
///
/// The panel is a manually-managed `NSStatusItem` + `NSPopover` (not SwiftUI's
/// `MenuBarExtra`) so it can be **opened from code** — e.g. the timer-finished
/// floating alert's "Открыть Doba" button calls `showPanel()`. See D47.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let quickCapture = QuickCaptureController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// Calendar bridge for the panel — owned here now that the delegate (not the
    /// SwiftUI `App`) builds the panel's view hierarchy.
    private let calendar = CalendarService()
    private let timerAlert = TimerFinishedAlertController()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        TimerScheduler.requestAuthorization()
        setUpStatusItem()
        observeTimerFinish()
        TimerScheduler.sync()   // re-arm alerts/auto-stops for any running timers
        registerHotKey()
    }

    /// Show timer alerts as a banner + sound even while Doba is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // MARK: - Menu-bar panel (status item + popover)

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true   // adapt to light/dark menu bar
            button.action = #selector(togglePanel(_:))
            button.target = self
            button.toolTip = "Doba"
        }
        statusItem = item

        // Transient = closes when you click away, matching menu-bar behavior.
        popover.behavior = .transient
        popover.animates = true
        // Auto-size to the SwiftUI content (the panel is a fixed 360×520).
        // `.preferredContentSize` makes the hosting controller report SwiftUI's
        // ideal size to the popover.
        let hosting = NSHostingController(
            rootView: TodayView()
                .environmentObject(DobaStore.shared)
                .environmentObject(calendar)
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { showPanel() }
    }

    /// Open the panel anchored under the menu-bar icon. Safe to call from code
    /// (timer auto-stop) — activates the app first so the popover shows on top.
    func showPanel() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// When a timer hits its limit and is auto-stopped, show a floating alert on
    /// the screen the user is working on — above all windows, across spaces and
    /// monitors. The menu-bar popover anchors to the status item's screen (the
    /// wrong one on a multi-display setup) and a transient popover dismisses itself
    /// when another app is frontmost, so it can't carry this. See D47.
    private func observeTimerFinish() {
        DobaStore.shared.$timerFinished
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in
                self?.timerAlert.show(notice, onOpen: { [weak self] in self?.showPanel() })
            }
            .store(in: &cancellables)
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

// MARK: - Timer-finished floating alert

/// A floating alert shown when a per-task timer hits its limit. Unlike the
/// menu-bar popover it is **not** tied to the status item's screen: it appears on
/// the display the user is working on (the one with the pointer), floats above all
/// windows, and joins every Space — so it's visible mid-call on a 2-monitor setup.
/// See DECISIONS D47.
@MainActor
private final class TimerFinishedAlertController {
    private var panel: NSPanel?

    /// Fixed panel size — matching the proven ⌃⌥D quick-capture pattern. (Sizing
    /// from `NSHostingView.fittingSize` before the view is in a window can yield a
    /// zero height → an invisible panel.)
    static let size = NSSize(width: 380, height: 150)

    /// `onOpen` is invoked when the user taps "Открыть Doba" (after the alert is
    /// dismissed) — wired to open the menu-bar panel.
    func show(_ notice: TimerFinishNotice, onOpen: @escaping () -> Void) {
        let view = TimerFinishedAlertView(
            notice: notice,
            onOpen: { [weak self] in self?.close(); onOpen() },
            onDismiss: { [weak self] in self?.close() }
        )
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(Self.size)
        positionOnActiveScreen(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating                                  // above normal windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // every Space, over full-screen apps
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false                          // stay up even when Doba isn't active
        return panel
    }

    /// Place the alert near the top-center of the screen the user is on — the one
    /// containing the pointer, falling back to the main screen.
    private func positionOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct TimerFinishedAlertView: View {
    let notice: TimerFinishNotice
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Таймер остановлен")
                    .font(.headline)
                Text("«\(notice.taskTitle)» — достигнут лимит \(hoursLabel(notice.limitHours))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Открыть Doba", action: onOpen)
                        .keyboardShortcut(.defaultAction)
                    Button("Скрыть", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 380, height: 150, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }

    private func hoursLabel(_ h: Double) -> String {
        (h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)) + "ч"
    }
}
