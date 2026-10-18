import SwiftUI
import LiftingCore

struct HistoryCalendar: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let sessions: [Session]
    let unit: WeightUnit
    private let calendar = Calendar.current

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var previousMonth: Date { calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart }
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: offset) + dates.map(Optional.some)
    }
    private var workoutDays: Set<Date> { Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }) }
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
    private var stats: HistoryMonthStats { HistoryMonthStats(month: monthStart, sessions: sessions, calendar: calendar) }
    private var previousStats: HistoryMonthStats { HistoryMonthStats(month: previousMonth, sessions: sessions, calendar: calendar) }

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
                Text("\(monthStart.formatted(.dateTime.month(.wide))) vs \(previousMonth.formatted(.dateTime.month(.wide)))")
                    .font(.subheadline.weight(.semibold))
                Grid(horizontalSpacing: 20, verticalSpacing: 16) {
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
                        statistic("Avg. duration", value: clockText(stats.averageDuration), delta: timeDelta(stats.averageDuration - previousStats.averageDuration))
                    }
                    GridRow {
                        statistic("Volume (\(unit.rawValue))", value: number(unit.display(stats.volume), decimals: 0), delta: delta(unit.display(stats.volume - previousStats.volume)))
                        statistic("Avg. volume", value: number(unit.display(stats.averageVolume), decimals: 0), delta: delta(unit.display(stats.averageVolume - previousStats.averageVolume)))
                    }
                }
            }
        }
        .card(padding: 16)
    }

    private func moveMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: monthStart) else { return }
        month = next
        selectedDay = nil
    }

    private func dayButton(_ date: Date) -> some View {
        let hasWorkout = workoutDays.contains(date)
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let today = calendar.isDateInToday(date)
        let ink = Palette.tint(scheme)
        return Button { selectedDay = selected ? nil : date } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline.weight(hasWorkout || today ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(hasWorkout ? (scheme == .dark ? Color.black : .white) : .primary)
                .frame(width: 34, height: 34)
                .background(hasWorkout ? ink : .clear, in: Circle())
                .overlay(Circle().strokeBorder(selected ? Color.primary : today ? ink : .clear, lineWidth: selected ? 2 : 1).padding(-3))
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!hasWorkout)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())), \(sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }.count) workouts")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("history.day.\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))")
    }

    private func statistic(_ title: String, value: String, delta: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(delta).font(.caption2).foregroundStyle(.secondary)
            }.monospacedDigit().fixedSize(horizontal: true, vertical: false)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func delta(_ value: Double) -> String {
        let rounded = value.rounded()
        return rounded == 0 ? "0" : "\(rounded > 0 ? "+" : "−")\(number(abs(rounded), decimals: 0))"
    }
    private func timeDelta(_ value: Double) -> String { value == 0 ? "0:00" : "\(value > 0 ? "+" : "−")\(clockText(abs(value)))" }
}

private struct HistoryMonthStats {
    let workouts: Int
    let restDays: Int
    let sets: Int
    let reps: Int
    let duration: Double
    let volume: Double
    var averageDuration: Double { workouts > 0 ? duration / Double(workouts) : 0 }
    var averageVolume: Double { workouts > 0 ? volume / Double(workouts) : 0 }

    init(month: Date, sessions: [Session], calendar: Calendar) {
        let interval = calendar.dateInterval(of: .month, for: month)
        let sessions = sessions.filter { session in
            guard let interval else { return false }
            return session.startedAt >= interval.start && session.startedAt < interval.end
        }
        let completed = sessions.flatMap(\.exercises).flatMap(\.sets).filter { $0.completedAt != nil }
        workouts = sessions.count
        // Only days that have already happened can be rest days.
        let elapsedDays: Int
        if let interval, interval.end <= Date() { elapsedDays = calendar.range(of: .day, in: .month, for: month)?.count ?? 0 }
        else if let interval, interval.start <= Date() { elapsedDays = (calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: Date())).day ?? 0) + 1 }
        else { elapsedDays = 0 }
        restDays = max(0, elapsedDays - Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }).count)
        sets = completed.count
        reps = completed.reduce(0) { $0 + ($1.reps ?? 0) }
        duration = sessions.reduce(0) { $0 + max(0, ($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) }
        volume = sessions.reduce(0) { $0 + $1.volume }
    }
}
