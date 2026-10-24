import SwiftUI
import LiftingCore

struct HistoryCalendar: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let sessions: [Session]
    let unit: WeightUnit
    private let calendar = Calendar.current

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: offset) + dates.map(Optional.some)
    }
    private var workoutDays: Set<Date> { Set(sessions.filter { $0.skipped != true }.map { calendar.startOfDay(for: $0.startedAt) }) }
    private var skippedDays: Set<Date> { Set(sessions.filter { $0.skipped == true }.map { calendar.startOfDay(for: $0.startedAt) }) }
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
    @EnvironmentObject private var store: AppStore
    @State private var period = ComparisonPeriod.month
    private var ranges: (current: DateInterval, previous: DateInterval) { period.ranges(month: monthStart, now: Date(), calendar: calendar) }

    var body: some View {
        let ranges = ranges
        let stats = HistoryPeriodStats(interval: ranges.current, sessions: sessions, calendar: calendar)
        let previousStats = HistoryPeriodStats(interval: ranges.previous, sessions: sessions, calendar: calendar)
        let workoutDays = workoutDays, skippedDays = skippedDays
        return VStack(spacing: 20) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36).contentShape(Rectangle()) }
                    .accessibilityLabel("Previous month").accessibilityIdentifier("history.previousMonth")
                Spacer()
                Text(monthStart, format: .dateTime.month(.wide).year()).font(.headline)
                    .accessibilityIdentifier("history.month")
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36).contentShape(Rectangle()) }
                    .accessibilityLabel("Next month").accessibilityIdentifier("history.nextMonth")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 2)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date { dayButton(date, workoutDays: workoutDays, skippedDays: skippedDays) }
                    else { Color.clear.frame(height: 36).accessibilityHidden(true) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Menu {
                    Picker("Period", selection: $period) { ForEach(ComparisonPeriod.allCases) { Text($0.title).tag($0) } }
                } label: {
                    Label(period.title, systemImage: "chevron.up.chevron.down")
                }.compactMenu().font(.subheadline.weight(.semibold)).accessibilityIdentifier("history.period")
                Text("\(rangeLabel(ranges.current)) compared with \(rangeLabel(ranges.previous))")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                    GridRow {
                        statistic("Workouts", value: "\(stats.workouts)", delta: delta(Double(stats.workouts - previousStats.workouts)))
                        statistic("Rest days", value: stats.restDays.map(String.init) ?? "No data", delta: restDelta(stats, previousStats))
                    }
                    GridRow {
                        statistic("Sets", value: "\(stats.sets)", delta: delta(Double(stats.sets - previousStats.sets)))
                        statistic("Reps", value: "\(stats.reps)", delta: delta(Double(stats.reps - previousStats.reps)))
                    }
                    GridRow {
                        statistic("Duration", value: clockText(stats.duration), delta: timeDelta(stats.duration - previousStats.duration))
                        statistic("Average duration", value: clockText(stats.averageDuration), delta: timeDelta(stats.averageDuration - previousStats.averageDuration))
                    }
                    GridRow {
                        statistic("Volume (\(unit.rawValue))", value: number(unit.display(stats.volume), decimals: 0), delta: delta(unit.display(stats.volume - previousStats.volume)))
                        statistic("Average volume", value: number(unit.display(stats.averageVolume), decimals: 0), delta: delta(unit.display(stats.averageVolume - previousStats.averageVolume)))
                    }
                }
                muscleAverages(ranges: ranges, stats: stats, previousStats: previousStats)
            }
        }
        .card(padding: 16)
    }

    /// Volume per workout for each primary muscle, so the rows add up to Average volume.
    @ViewBuilder private func muscleAverages(ranges: (current: DateInterval, previous: DateInterval), stats: HistoryPeriodStats, previousStats: HistoryPeriodStats) -> some View {
        let current = averages(ranges.current, workouts: stats.workouts)
        let previous = averages(ranges.previous, workouts: previousStats.workouts)
        let names = Set(current.keys).union(previous.keys).sorted { a, b in
            let left = (current[a] ?? 0, previous[a] ?? 0), right = (current[b] ?? 0, previous[b] ?? 0)
            return left == right ? a < b : left > right
        }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Average volume by muscle (\(unit.rawValue))").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                let top = max(current.values.max() ?? 0, 1)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(names, id: \.self) { name in
                        GridRow {
                            Text(name).font(.subheadline).lineLimit(1)
                            // Share of the busiest muscle, for scanning the split at a glance.
                            GeometryReader { proxy in
                                Capsule().fill(palette.action.opacity(0.35)).frame(width: max(2, proxy.size.width * (current[name] ?? 0) / top), height: 6)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }.frame(height: 18).accessibilityHidden(true)
                            Text(number(unit.display(current[name] ?? 0), decimals: 0)).font(.figure(15)).gridColumnAlignment(.trailing)
                            Text(delta(unit.display((current[name] ?? 0) - (previous[name] ?? 0)))).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .leading)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }.accessibilityIdentifier("history.muscles")
        }
    }
    private func averages(_ interval: DateInterval, workouts: Int) -> [String: Double] {
        guard workouts > 0 else { return [:] }
        let rows = store.data.muscleSummary(since: interval.start, until: interval.end).filter { $0.volume > 0 }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.volume / Double(workouts)) })
    }

    private func moveMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: monthStart) else { return }
        month = next
        selectedDay = nil
    }

    private func dayButton(_ date: Date, workoutDays: Set<Date>, skippedDays: Set<Date>) -> some View {
        let hasWorkout = workoutDays.contains(date)
        let skipped = !hasWorkout && skippedDays.contains(date)
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let today = calendar.isDateInToday(date)
        let ink = palette.completed
        return Button { selectedDay = selected ? nil : date } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline.weight(hasWorkout || today ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(hasWorkout ? palette.on(.completed) : .primary)
                .frame(width: 34, height: 34)
                .background(hasWorkout ? ink : .clear, in: Circle())
                .overlay(Circle().strokeBorder(skipped ? Color.secondary.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                .overlay(Circle().strokeBorder(selected ? Color.primary : today ? palette.action : .clear, lineWidth: selected ? 2 : 1).padding(-3))
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!hasWorkout && !skipped)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())), \(skipped ? "skipped" : counted(sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) && $0.skipped != true }.count, "workout"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("history.day.\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))")
    }

    private func statistic(_ title: String, value: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.figure(19)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(delta).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func restDelta(_ stats: HistoryPeriodStats, _ previousStats: HistoryPeriodStats) -> String {
        guard let current = stats.restDays, let previous = previousStats.restDays else { return "" }
        return delta(Double(current - previous))
    }
    private func rangeLabel(_ interval: DateInterval) -> String {
        guard interval.duration > 0 else { return "No data" }
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let style: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()
        return "\(interval.start.formatted(style))–\(last.formatted(style))"
    }

    private func delta(_ value: Double) -> String {
        let rounded = value.rounded()
        return rounded == 0 ? "same" : "\(rounded > 0 ? "+" : "−")\(number(abs(rounded), decimals: 0))"
    }
    private func timeDelta(_ value: Double) -> String { abs(value) < 1 ? "same" : "\(value > 0 ? "+" : "−")\(clockText(abs(value)))" }
}
