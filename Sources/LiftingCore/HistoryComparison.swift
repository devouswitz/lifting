import Foundation

public enum ComparisonPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter, year
    public var id: String { rawValue }
    public var title: String {
        switch self { case .week: return "Past Week"; case .month: return "Month"; case .quarter: return "3 Months"; case .year: return "Year" }
    }

    /// Partial periods compare the same number of calendar days. Completed periods keep their natural boundaries.
    public func ranges(month: Date, now: Date, calendar: Calendar) -> (current: DateInterval, previous: DateInterval) {
        let shown = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        func offset(_ component: Calendar.Component, _ count: Int, _ date: Date) -> Date {
            calendar.date(byAdding: component, value: count, to: date) ?? date
        }
        let tomorrow = offset(.day, 1, calendar.startOfDay(for: now))
        if shown.start >= tomorrow {
            let empty = DateInterval(start: shown.start, duration: 0)
            return (empty, empty)
        }
        let end = min(shown.end, tomorrow)
        if self == .week {
            let start = offset(.day, -7, end)
            return (DateInterval(start: start, end: end), DateInterval(start: offset(.day, -7, start), end: start))
        }
        let months = self == .month ? 1 : self == .quarter ? 3 : 12
        let start = offset(.month, 1 - months, shown.start)
        let previousStart = offset(.month, -months, start)
        if end < shown.end {
            let elapsed = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            let previousEnd = min(offset(.day, elapsed, previousStart), start)
            return (DateInterval(start: start, end: end),
                    DateInterval(start: offset(.day, -elapsed, previousEnd), end: previousEnd))
        }
        return (DateInterval(start: start, end: end), DateInterval(start: previousStart, end: start))
    }
}

public struct HistoryPeriodStats {
    public let workouts: Int
    public let restDays: Int?
    public let sets: Int
    public let reps: Int
    public let duration: Double
    public let volume: Double
    public var averageDuration: Double { workouts > 0 ? duration / Double(workouts) : 0 }
    public var averageVolume: Double { workouts > 0 ? volume / Double(workouts) : 0 }

    public init(interval: DateInterval, sessions: [Session], calendar: Calendar, now: Date = Date()) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let end = min(interval.end, tomorrow)
        let recorded = sessions.filter { $0.endedAt != nil && $0.startedAt >= interval.start && $0.startedAt < end }
        let workouts = recorded.filter { $0.skipped != true }
        let completed = workouts.flatMap(\.exercises).flatMap(\.sets).filter { $0.completedAt != nil }
        self.workouts = workouts.count
        // An empty period is unknown, not evidence that every day was a rest day.
        if recorded.isEmpty {
            restDays = nil
        } else {
            let days = max(0, calendar.dateComponents([.day], from: interval.start, to: end).day ?? 0)
            restDays = max(0, days - Set(workouts.map { calendar.startOfDay(for: $0.startedAt) }).count)
        }
        sets = completed.count
        reps = completed.reduce(0) { $0 + ($1.reps ?? 0) }
        duration = workouts.reduce(0) { $0 + $1.duration() }
        volume = workouts.reduce(0) { $0 + $1.volume }
    }
}
