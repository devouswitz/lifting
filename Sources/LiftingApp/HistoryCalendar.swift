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
    private var stats: HistoryPeriodStats { HistoryPeriodStats(interval: ranges.current, sessions: sessions, calendar: calendar) }
    private var previousStats: HistoryPeriodStats { HistoryPeriodStats(interval: ranges.previous, sessions: sessions, calendar: calendar) }

    var body: some View {
        VStack(spacing: 20) {
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
                    if let date { dayButton(date) }
                    else { Color.clear.frame(height: 36).accessibilityHidden(true) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                HStack(spacing: 4) {
                    Text(period == .month ? "Compared with" : "\(period.label(ranges.current, month: monthStart, calendar: calendar)) compared with")
                    Menu {
                        Picker("Period", selection: $period) { ForEach(ComparisonPeriod.allCases) { Text($0.title).tag($0) } }
                    } label: {
                        HStack(spacing: 3) {
                            Text(period.label(ranges.previous, month: monthStart, calendar: calendar))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                        }.foregroundStyle(palette.action)
                    }.compactMenu().fixedSize().accessibilityIdentifier("history.period")
                }.font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                    GridRow {
                        statistic("Workouts", value: "\(stats.workouts)", delta: delta(Double(stats.workouts - previousStats.workouts)))
                        statistic("Rest days", value: "\(stats.restDays)", delta: delta(Double(stats.restDays - previousStats.restDays)))
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
                muscleAverages
            }
        }
        .card(padding: 16)
    }

    /// Volume per workout for each primary muscle, so the rows add up to Average volume.
    @ViewBuilder private var muscleAverages: some View {
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

    private func dayButton(_ date: Date) -> some View {
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

    private func delta(_ value: Double) -> String {
        let rounded = value.rounded()
        return rounded == 0 ? "same" : "\(rounded > 0 ? "+" : "−")\(number(abs(rounded), decimals: 0))"
    }
    private func timeDelta(_ value: Double) -> String { abs(value) < 1 ? "same" : "\(value > 0 ? "+" : "−")\(clockText(abs(value)))" }
}

/// The span the calendar's comparison covers, ending with the shown month (or today in the current month).
enum ComparisonPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter, year
    var id: String { rawValue }
    var title: String {
        switch self { case .week: return "Past Week"; case .month: return "Month"; case .quarter: return "3 Months"; case .year: return "Year" }
    }
    func ranges(month: Date, now: Date, calendar: Calendar) -> (current: DateInterval, previous: DateInterval) {
        let shown = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        func back(_ component: Calendar.Component, _ value: Int, from date: Date) -> Date { calendar.date(byAdding: component, value: -value, to: date) ?? date }
        switch self {
        case .week:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let end = min(shown.end, tomorrow)
            let start = back(.day, 7, from: end)
            return (DateInterval(start: start, end: end), DateInterval(start: back(.day, 7, from: start), end: start))
        case .month:
            let start = shown.start
            return (shown, DateInterval(start: back(.month, 1, from: start), end: start))
        case .quarter, .year:
            let months = self == .quarter ? 3 : 12
            let start = back(.month, months - 1, from: shown.start)
            return (DateInterval(start: start, end: shown.end), DateInterval(start: back(.month, months, from: start), end: start))
        }
    }
    /// Names a range briefly, adding the year only when it differs from the shown month's.
    func label(_ range: DateInterval, month: Date, calendar: Calendar) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let year = calendar.component(.year, from: month)
        let withYear = calendar.component(.year, from: range.start) != year || calendar.component(.year, from: last) != year
        switch self {
        case .week:
            let sameMonth = calendar.isDate(range.start, equalTo: last, toGranularity: .month)
            let first = range.start.formatted(.dateTime.month(.abbreviated).day())
            let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
            return "\(first)–\(end)\(withYear ? ", \(calendar.component(.year, from: last))" : "")"
        case .month:
            return range.start.formatted(withYear ? .dateTime.month(.wide).year() : .dateTime.month(.wide))
        case .quarter, .year:
            let style: Date.FormatStyle = withYear ? .dateTime.month(.abbreviated).year() : .dateTime.month(.abbreviated)
            return "\(range.start.formatted(style))–\(last.formatted(style))"
        }
    }
}

private struct HistoryPeriodStats {
    let workouts: Int
    let restDays: Int
    let sets: Int
    let reps: Int
    let duration: Double
    let volume: Double
    var averageDuration: Double { workouts > 0 ? duration / Double(workouts) : 0 }
    var averageVolume: Double { workouts > 0 ? volume / Double(workouts) : 0 }

    init(interval: DateInterval, sessions: [Session], calendar: Calendar, now: Date = Date()) {
        let sessions = sessions.filter { $0.skipped != true && $0.startedAt >= interval.start && $0.startedAt < interval.end }
        let completed = sessions.flatMap(\.exercises).flatMap(\.sets).filter { $0.completedAt != nil }
        workouts = sessions.count
        // Only days that have already happened can be rest days.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let elapsed = max(0, calendar.dateComponents([.day], from: interval.start, to: min(interval.end, tomorrow)).day ?? 0)
        restDays = max(0, elapsed - Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }).count)
        sets = completed.count
        reps = completed.reduce(0) { $0 + ($1.reps ?? 0) }
        duration = sessions.reduce(0) { $0 + max(0, ($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) }
        volume = sessions.reduce(0) { $0 + $1.volume }
    }
}
