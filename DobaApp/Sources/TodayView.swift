import SwiftUI
import AppKit
import WidgetKit
import EventKit
import DobaKit

private enum PanelMode { case day, week, month }

/// The menu-bar panel: a Day view (any date — today / tomorrow / archive, with
/// ‹ › navigation) and a Week view (today…+6, each day color-coded by billable
/// load). Task entry (quick-add + ✨ Claude parse), calendar meetings, timer,
/// and a planned-vs-actual summary live in the Day view.
struct TodayView: View {
    @EnvironmentObject private var store: DobaStore
    @EnvironmentObject private var calendar: CalendarService

    @State private var mode: PanelMode = .day
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0    // 0 = this week, +1 = next, −1 = last
    @State private var monthOffset = 0   // pay periods from the current one
    @State private var newTitle = ""
    @State private var editingTaskID: DobaTask.ID?
    @State private var showingSettings = false
    @State private var showingProjects = false
    @State private var completingTaskID: DobaTask.ID?
    @State private var isParsing = false
    @State private var parseError: String?

    private var dayTasks: [DobaTask] { store.tasks(on: selectedDate) }

    /// Floating pool with done tasks sunk to the bottom so the open ones stay
    /// in focus.
    private var pool: [DobaTask] {
        dayTasks.filter { !$0.isTimeBound }.sorted { a, b in
            if (a.status == .done) != (b.status == .done) { return a.status != .done }
            return a.createdAt < b.createdAt
        }
    }

    /// Calendar meetings for `day`, minus any already converted to tasks.
    private func nonConvertedMeetings(on day: Date) -> [Meeting] {
        let linked = Set(store.tasks(on: day).compactMap(\.linkedEventID))
        return calendar.meetings(on: day).filter { !linked.contains($0.id) }
    }

    private var meetings: [Meeting] { nonConvertedMeetings(on: selectedDate) }

    private var timelineItems: [TimelineItem] {
        let taskItems = dayTasks.filter(\.isTimeBound).map(TimelineItem.task)
        let meetingItems = meetings.map(TimelineItem.meeting)
        return (taskItems + meetingItems).sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }   // completed items sink to the bottom
            return a.sortKey < b.sortKey
        }
    }

    private var isEmptyDay: Bool { dayTasks.isEmpty && meetings.isEmpty }

    private var editingTask: DobaTask? {
        guard let id = editingTaskID else { return nil }
        return store.data.tasks.first { $0.id == id }
    }

    private var completingTask: DobaTask? {
        guard let id = completingTaskID else { return nil }
        return store.data.tasks.first { $0.id == id }
    }

    var body: some View {
        if let task = completingTask {
            CompleteTaskView(task: task) { hours in
                store.completeTask(task, loggedHours: hours)
                reloadWidget()
                completingTaskID = nil
            } onCancel: {
                completingTaskID = nil
            }
        } else if showingProjects {
            ProjectsView { showingProjects = false }
        } else if showingSettings {
            SettingsView(
                initialRate: store.data.hourlyRate,
                initialCurrency: store.data.currency ?? "$",
                onSaveEarnings: { rate, currency in store.setEarnings(rate: rate, currency: currency) },
                onManageProjects: { showingSettings = false; showingProjects = true },
                onClose: { showingSettings = false }
            )
        } else if let task = editingTask {
            TaskDetailEditor(task: task) { editingTaskID = nil }
        } else {
            panel
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Divider()
            if store.loadFailed {
                Label("Данные не прочитались. Перезапусти Doba (Quit → открыть снова) — данные на диске целы.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            switch mode {
            case .week: weekView
            case .month: monthView
            case .day: dayContainer
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 520)
        .onAppear {
            // Re-read from disk first: heals a transient read glitch that may
            // have left us with an empty/stale store.
            store.reload()
            store.normalizeBillable()    // rated project ⇒ billable (fixes any drift)
            store.autoStopStaleTimer()   // close a timer left running overnight
            let carried = store.carryOverUnfinished()
            let made = store.materializeRecurring(through: DobaApp.recurrenceHorizon())
            if carried > 0 || made > 0 { reloadWidget() }
            calendar.reload()
            TimerScheduler.sync()   // re-arm countdowns / auto-stops
        }
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("", selection: $mode) {
                    Text("Day").tag(PanelMode.day)
                    Text("Week").tag(PanelMode.week)
                    Text("Month").tag(PanelMode.month)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings — rate, projects, API key")
            }
            if mode == .day {
                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Spacer()
                    Button { selectedDate = Calendar.current.startOfDay(for: Date()) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(loadColor(selectedDayLoad)).frame(width: 8, height: 8)
                            Text(dateLabel(selectedDate)).font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Jump to today")
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Day view (live-ticking while a timer runs)

    @ViewBuilder private var dayContainer: some View {
        if !store.data.runningEntries.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in dayBody(now: context.date) }
        } else {
            dayBody(now: Date())
        }
    }

    private func dayBody(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            quickAdd
            calendarBanner
            Divider()
            if isEmptyDay {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "checklist",
                    description: Text("No tasks or meetings for this day. Add one above.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !timelineItems.isEmpty { timelineSection(now: now) }
                        if !pool.isEmpty { floatingSection(now: now) }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                daySummary(now: now)
            }
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                TextField("Задача, проект, 2h, 14:00 — Enter отправит в ✨", text: $newTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(parseWithClaude)
                    .disabled(isParsing)
                    .help("""
                        Напиши и жми ✨ — Claude разложит:
                        • Название — обязательно
                        • Проект — напр. Helpmybiz (без проекта → Internal)
                        • Часы — «2h», «30 мин» (без указания → 0.5h)
                        • Время — «14:00» ставит на таймлайн; без времени → флоатинг
                        Примеры:
                        «Созвон с клиентом, Helpmybiz, 1h, 11:30»
                        «Поправить баг, In4People, 2h»  (флоатинг)
                        Enter без ✨ = задача на сегодня (Internal, 0.5h, флоатинг).
                        """)
                if isParsing {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: parseWithClaude) { Image(systemName: "sparkles") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.purple)
                        .help("Parse with Claude — fills project, hours, time, billable; expands ranges")
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let parseError {
                Text(parseError)
                    .font(.caption2).foregroundStyle(.red)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var calendarBanner: some View {
        Divider()
        Group {
            switch calendar.authorization {
            case .notDetermined:
                Button { Task { await calendar.requestAccess() } } label: {
                    Label("Connect calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderless)
            case .fullAccess:
                HStack(spacing: 6) {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text(meetings.isEmpty ? "No meetings this day" : "\(meetings.count) meeting(s)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { calendar.reload() }.buttonStyle(.borderless).font(.caption)
                }
            default:
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
                    Text("Calendar access is off").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings", action: openCalendarSettings).buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func timelineSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Timeline")
            ForEach(timelineItems) { item in
                switch item {
                case .task(let task): taskRow(task, now: now)
                case .meeting(let meeting): MeetingRow(meeting: meeting) { convertMeeting(meeting) }
                }
            }
        }
    }

    private func floatingSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Floating")
            ForEach(pool) { taskRow($0, now: now) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12)
    }

    private func taskRow(_ task: DobaTask, now: Date) -> some View {
        let actual = store.data.actualHours(forTaskID: task.id, asOf: now)
        let runningElapsed = store.data.runningEntry(forTaskID: task.id).map { now.timeIntervalSince($0.start) }
        return TaskRow(
            task: task,
            project: store.project(for: task),
            actualHours: actual,
            runningElapsed: runningElapsed,
            isTiming: store.isTiming(task),
            needsLog: needsLog(task, actualHours: actual, now: now),
            onToggleStatus: {
                // Done → todo is a plain toggle; todo → done asks for logged time.
                if task.status == .done {
                    store.toggleStatus(task); reloadWidget()
                } else {
                    completingTaskID = task.id
                }
            },
            onToggleTimer: { store.toggleTimer(for: task); TimerScheduler.sync(); reloadWidget() },
            onDefer: { store.moveTask(task, byDays: 1); reloadWidget() },
            onSchedule: task.isTimeBound ? nil : { store.scheduleToday(task); reloadWidget() },
            onUnschedule: task.isTimeBound ? { store.moveToFloating(task); reloadWidget() } : nil,
            onLog: { completingTaskID = task.id },
            onEdit: { editingTaskID = task.id }
        )
    }

    /// A billable task whose time slot (or whole day) has passed with nothing
    /// logged — nudge the user to log it so calls/meetings don't slip by.
    private func needsLog(_ task: DobaTask, actualHours: Double, now: Date) -> Bool {
        guard task.billable, actualHours == 0 else { return false }
        let cal = Calendar.current
        let dayPassed = cal.startOfDay(for: task.scheduledDate) < cal.startOfDay(for: now)
        let slotPassed = task.scheduledTime.map { $0 < now } ?? false
        return dayPassed || slotPassed
    }

    /// Turn a meeting into a task — run the title through Claude to attach the
    /// right project + billable, keeping the meeting's time/duration/link.
    private func convertMeeting(_ m: Meeting) {
        Task {
            let names = store.data.projects.map(\.name)
            let parsed = try? await ClaudeClient.parse(m.title, knownProjects: names)
            let first = parsed?.first
            store.addMeetingTask(
                title: m.title,
                projectName: first?.project,
                parsedBillable: first?.billable,
                start: m.start,
                hours: m.hours,
                eventID: m.id
            )
            reloadWidget()
        }
    }

    private func daySummary(now: Date) -> some View {
        let r = store.data.dayRollup(on: selectedDate, meetings: meetings, asOf: now)
        return VStack(alignment: .leading, spacing: 4) {
            splitRow("ПЛАН", billable: r.plannedBillable, overhead: r.plannedOverhead)
            splitRow("ФАКТ", billable: r.actualBillable, overhead: r.actualOverhead)

            if !r.planned.projectLines.isEmpty || r.planned.meetingCount > 0 {
                HStack(spacing: 10) {
                    ForEach(r.planned.projectLines.prefix(3)) { line in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(line.colorHex.flatMap(Color.init(hex:)) ?? Color.secondary)
                                .frame(width: 7, height: 7)
                            Text("\(line.name) \(Self.hours(line.hours))h")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if r.planned.meetingCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.caption2)
                            Text("\(r.planned.meetingCount)").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            let projected = store.data.projectedEarnings(on: selectedDate)
            let earned = store.data.earnedEarnings(on: selectedDate, asOf: now)
            if projected > 0 || earned > 0 {
                Text("Заработок \(money(earned)) / \(money(projected))")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// "ПЛАН  6$ / 2h overhead" — billable (green, with $) then overhead (muted).
    private func splitRow(_ label: String, billable: Double, overhead: Double) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Image(systemName: "dollarsign.circle.fill").font(.caption2).foregroundStyle(.green)
            Text("\(Self.hours(billable))h").font(.callout.weight(.semibold)).foregroundStyle(.green)
            Text("/ \(Self.hours(overhead))h").font(.caption).foregroundStyle(.secondary)
            Text("overhead").font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private func money(_ amount: Double) -> String {
        (store.data.currency ?? "$") + amount.formatted(.number.precision(.fractionLength(0)))
    }


    // MARK: - Week view

    /// Start (Sunday) of the week being shown — current week shifted by `weekOffset`.
    private var weekStart: Date {
        var cal = Calendar.current
        cal.firstWeekday = 1   // Sunday
        let today = cal.startOfDay(for: Date())
        let base = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: base) ?? base
    }

    /// The shown work week, **Sunday → Saturday**.
    private var weekDays: [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekRangeLabel: String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        default:
            let end = weekDays.last ?? weekStart
            return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }

    /// Color bucket for a day, by **billable** hours toward the daily share of
    /// the weekly goal (40/5 = 8h): **past** days judged by what was *logged*
    /// (did you hit it?), today/future by what's *planned* (booked enough?).
    private func dayLoad(_ day: Date) -> DayLoad {
        let cal = Calendar.current
        let billable = cal.startOfDay(for: day) < cal.startOfDay(for: Date())
            ? store.data.dayRollup(on: day).actualBillable
            : store.data.plannedBillableHours(on: day)
        return DayLoad(billableHours: billable, capacityHours: DobaData.weeklyBillableTargetHours / 5)
    }

    private var selectedDayLoad: DayLoad { dayLoad(selectedDate) }

    private var weekView: some View {
        VStack(spacing: 0) {
            weekNav
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(weekDays, id: \.self) { day in weekRow(day) }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            weekFooter
        }
    }

    private var weekNav: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).help("Previous week")
            Spacer()
            Button { weekOffset = 0 } label: {
                Text(weekRangeLabel).font(.subheadline.weight(weekOffset == 0 ? .semibold : .regular))
            }
            .buttonStyle(.plain).help("Back to this week")
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).help("Next week")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// Week + month billable/overhead totals with layered progress bars. The
    /// month bar (15th→15th, /160h) carries surplus across weeks; its tick marks
    /// where you "should be" by date, so being ahead shows the green past the tick.
    private var weekFooter: some View {
        let cal = Calendar.current
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let pBill = weekDays.reduce(0.0) { $0 + store.data.plannedBillableHours(on: $1) }
        let pOver = weekDays.reduce(0.0) { $0 + store.data.plannedOverheadHours(on: $1) }
        let tBill = store.data.actualHours(from: weekStart, to: weekEnd, billable: true)
        let tOver = store.data.actualHours(from: weekStart, to: weekEnd, billable: false)
        let weekTarget = DobaData.weeklyBillableTargetHours

        let (ps, pe) = DobaData.payPeriod(containing: Date())
        let mBill = store.data.actualBillableHours(from: ps, to: pe)
        let mOver = store.data.actualHours(from: ps, to: pe, billable: false)
        let monthTarget = DobaData.monthlyBillableTargetHours
        let span = pe.timeIntervalSince(ps)
        let pace = span > 0 ? min(max(Date().timeIntervalSince(ps) / span, 0), 1) : 0
        let earned = weekDays.reduce(0.0) { $0 + store.data.earnedEarnings(on: $1) }

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("НЕДЕЛЯ").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("трек \(Self.hours(tBill))$/\(Self.hours(tOver)) · план \(Self.hours(pBill))$/\(Self.hours(pOver))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            WeekBillableBar(planned: pBill, logged: tBill, target: weekTarget)
            Text("\(Self.hours(tBill)) / \(Int(weekTarget))h billable")
                .font(.caption2).foregroundStyle(.green)

            Divider().padding(.vertical, 2)

            HStack {
                Text("МЕСЯЦ 15→15").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("трек \(Self.hours(mBill))$/\(Self.hours(mOver))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            WeekBillableBar(planned: 0, logged: mBill, target: monthTarget, pace: pace)
            HStack {
                Text("\(Self.hours(mBill)) / \(Int(monthTarget))h billable")
                    .font(.caption2).foregroundStyle(.green)
                Spacer()
                if earned > 0 { Text(money(earned)).font(.caption2).foregroundStyle(.green) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private static func hours(_ h: Double) -> String {
        h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)
    }

    private func weekRow(_ day: Date) -> some View {
        let cal = Calendar.current
        let isPast = cal.startOfDay(for: day) < cal.startOfDay(for: Date())
        let isToday = cal.isDateInToday(day)
        let r = store.data.dayRollup(on: day, meetings: nonConvertedMeetings(on: day))
        // Past rows show what was logged; today/future show what's planned.
        let bill = isPast ? r.actualBillable : r.plannedBillable
        let over = isPast ? r.actualOverhead : r.plannedOverhead
        return Button {
            selectedDate = cal.startOfDay(for: day)
            mode = .day
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(loadColor(dayLoad(day)))
                    .frame(width: 5, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLabel(day))
                        .font(.subheadline.weight(isToday ? .bold : .regular))
                    HStack(spacing: 5) {
                        Image(systemName: "dollarsign.circle.fill").font(.caption2).foregroundStyle(.green)
                        Text("\(Self.hours(bill))h").foregroundStyle(.green)
                        Text("/ \(Self.hours(over))h").foregroundStyle(.secondary)
                        if r.planned.meetingCount > 0 {
                            Text("· \(r.planned.meetingCount) mtg").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isToday ? Color.accentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadColor(_ load: DayLoad) -> Color {
        switch load {
        case .full: return .green
        case .partial: return .yellow
        case .low: return .orange
        case .empty: return .red
        case .blocked: return .gray
        }
    }

    // MARK: - Month report

    private var monthView: some View {
        let cal = Calendar.current
        let ref = cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        let (ps, pe) = DobaData.payPeriod(containing: ref)
        let report = store.data.periodReport(from: ps, to: pe)
        let target = DobaData.monthlyBillableTargetHours
        let cur = store.data.currency ?? "$"
        return VStack(spacing: 0) {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).help("Previous period")
                Spacer()
                Button { monthOffset = 0 } label: {
                    Text("\(ps.formatted(.dateTime.day().month(.abbreviated))) – \(pe.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.subheadline.weight(monthOffset == 0 ? .semibold : .regular))
                }
                .buttonStyle(.plain).help("Current pay period")
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).help("Next period")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("BILLABLE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Self.hours(report.billableHours)) / \(Int(target))h").font(.callout.monospacedDigit())
                        }
                        WeekBillableBar(planned: 0, logged: report.billableHours, target: target)
                    }
                    HStack(spacing: 18) {
                        monthStat("Заработано", cur + report.earnings.formatted(.number.precision(.fractionLength(0))), .green)
                        monthStat("Всего часов", "\(Self.hours(report.billableHours + report.overheadHours))h", .primary)
                        monthStat("Overhead", "\(Self.hours(report.overheadHours))h", .secondary)
                    }
                    if !report.projectLines.isEmpty {
                        Divider()
                        Text("ПО ПРОЕКТАМ").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(report.projectLines) { line in
                            HStack(spacing: 8) {
                                Circle().fill(line.colorHex.flatMap(Color.init(hex:)) ?? Color.secondary)
                                    .frame(width: 8, height: 8)
                                Text(line.name)
                                Spacer()
                                Text("\(Self.hours(line.hours))h").foregroundStyle(.secondary).monospacedDigit()
                                Text(cur + line.earnings.formatted(.number.precision(.fractionLength(0))))
                                    .foregroundStyle(.green).monospacedDigit()
                            }
                            .font(.caption)
                        }
                    } else {
                        Text("Нет затреканного времени за период")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func monthStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit Doba") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions / helpers

    private func step(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = Calendar.current.startOfDay(for: d)
        }
    }

    /// "Today" / "Tomorrow" / "Yesterday" / "Wed, 25 Jun".
    private func dateLabel(_ date: Date) -> String {
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

    private func parseWithClaude() {
        let text = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        parseError = nil
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let parsed = try await ClaudeClient.parse(text, knownProjects: store.data.projects.map(\.name))
                let added = store.importParsedTasks(parsed)
                reloadWidget()
                if added > 0 { newTitle = "" } else { parseError = "No tasks recognized in that text." }
            } catch {
                parseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func reloadWidget() { WidgetCenter.shared.reloadAllTimelines() }

    private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A timeline slot is either a task (interactive) or a meeting (read-only).
private enum TimelineItem: Identifiable {
    case task(DobaTask)
    case meeting(Meeting)

    var id: String {
        switch self {
        case .task(let t): return "task-\(t.id.uuidString)"
        case .meeting(let m): return "meeting-\(m.id)"
        }
    }

    var sortKey: Date {
        switch self {
        case .task(let t): return t.scheduledTime ?? .distantFuture
        case .meeting(let m): return m.start
        }
    }

    var isDone: Bool {
        if case .task(let t) = self { return t.status == .done }
        return false
    }
}

/// One task line: checkbox + title + badges (incl. live actual hours) + timer
/// toggle + edit affordance.
private struct TaskRow: View {
    let task: DobaTask
    let project: Project?
    let actualHours: Double
    /// Seconds in the current running session (nil unless this task is timing).
    let runningElapsed: Double?
    let isTiming: Bool
    let needsLog: Bool
    let onToggleStatus: () -> Void
    let onToggleTimer: () -> Void
    let onDefer: () -> Void
    /// Non-nil only for floating tasks → "put on today's timeline".
    let onSchedule: (() -> Void)?
    /// Non-nil only for time-bound tasks → "send back to the floating pool".
    let onUnschedule: (() -> Void)?
    let onLog: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onToggleStatus) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(task.status == .done ? "Mark as not done" : "Complete — log time worked")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEdit)
                    .help("Открыть редактирование")

                HStack(spacing: 6) {
                    if let project {
                        Label(project.name, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color(hex: project.colorHex) ?? .secondary)
                            .font(.caption)
                    }
                    if let est = task.estimatedHours {
                        Text("\(est, format: .number)h").font(.caption).foregroundStyle(.secondary)
                    }
                    if task.billable {
                        Image(systemName: "dollarsign.circle").font(.caption).foregroundStyle(.green)
                    }
                    if task.linkedEventID != nil {
                        Image(systemName: "calendar").font(.caption).foregroundStyle(.blue)
                            .help("From a calendar meeting")
                    }
                    if task.isCarriedOver {
                        Image(systemName: "arrow.uturn.forward").font(.caption).foregroundStyle(.orange)
                    }
                    if task.recurrence != nil {
                        Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary)
                    }
                    if isTiming || actualHours > 0 {
                        // Running → this session's live H:MM:SS; else logged hours.
                        let timeText = isTiming ? clockString(runningElapsed ?? 0) : "\(actualHours.formatted(.number))h"
                        Label(timeText, systemImage: "stopwatch")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(isTiming ? Color.red : .secondary)
                    }
                    if needsLog {
                        Button(action: onLog) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("No time logged — tap to log it")
                    }
                }
            }

            Spacer()

            if let slot = task.scheduledTime {
                Text(slot, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let onSchedule {
                Button(action: onSchedule) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Put on today's timeline")
            }
            if let onUnschedule {
                Button(action: onUnschedule) {
                    Image(systemName: "tray.and.arrow.down").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Move to the floating pool")
            }

            Button(action: onToggleTimer) {
                Image(systemName: isTiming ? "stop.circle.fill" : "play.circle")
                    .foregroundStyle(isTiming ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isTiming ? "Stop timer" : "Start timer")

            Button(action: onDefer) {
                Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Move to next day")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// A meeting from the system calendar — read-only, no checkbox/timer/editor.
private struct MeetingRow: View {
    let meeting: Meeting
    let onConvert: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).foregroundStyle(.primary)
                Text("\(meeting.start, format: .dateTime.hour().minute()) – \(meeting.end, format: .dateTime.hour().minute())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onConvert) {
                Image(systemName: "plus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add as task — to check off and log time")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

/// Seconds → "H:MM:SS" (or "M:SS" under an hour) for the live running timer.
private func clockString(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private struct WeekBillableBar: View {
    let planned: Double
    let logged: Double
    let target: Double
    /// 0…1 — optional "where you should be by now" tick (month pacing).
    var pace: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                if logged > target {
                    Capsule().fill(Color.pink)
                } else {
                    if planned > 0 {
                        Capsule().fill(Color.gray.opacity(0.45))
                            .frame(width: max(0, width * min(planned / target, 1)))
                    }
                    if logged > 0 {
                        Capsule().fill(Color.green)
                            .frame(width: max(0, width * min(logged / target, 1)))
                    }
                }
                if let pace {
                    Rectangle().fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5)
                        .offset(x: width * min(max(pace, 0), 1) - 0.75)
                }
            }
        }
        .frame(height: 12)
    }
}

extension Color {
    /// Build a Color from a "#RRGGBB" string. UI-layer concern, so it lives in
    /// the app target rather than in DobaKit (which stays UI-framework-free).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
