import SwiftUI
import Charts
import LiftingCore

/// Cardio over time: weekly (or monthly) time or distance as bars, then each cardio exercise's
/// latest session and totals, opening its own progress screen.
struct CardioProgressView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    let programID: UUID?
    let since: Date
    /// The range in days; 0 is all of history.
    let days: Int
    @State private var distance = false
    @State private var exerciseID: UUID?
    @State private var selectedDate: Date?

    private struct Summary: Identifiable {
        let exercise: Exercise
        let sessions: Int
        let seconds: Double
        let meters: Double
        let latest: (date: Date, seconds: Double, meters: Double)
        var id: UUID { exercise.id }
    }

    /// Cardio exercises logged in the range, most recent first.
    private var summaries: [Summary] {
        let sessions = store.data.sessions(inProgram: programID).filter { $0.startedAt >= since && $0.skipped != true }.sorted { $0.startedAt < $1.startedAt }
        var totals: [UUID: (count: Int, seconds: Double, meters: Double, latest: (Date, Double, Double))] = [:]
        for session in sessions {
            for item in session.exercises where item.mode == .cardio {
                let sets = item.sets.filter { $0.completedAt != nil && $0.plan.kind != .warmup }
                let seconds = sets.compactMap(\.seconds).reduce(0, +), meters = sets.compactMap(\.meters).reduce(0, +)
                guard seconds > 0 || meters > 0 else { continue }
                let previous = totals[item.exerciseID]
                totals[item.exerciseID] = ((previous?.count ?? 0) + 1, (previous?.seconds ?? 0) + seconds, (previous?.meters ?? 0) + meters, (session.startedAt, seconds, meters))
            }
        }
        return totals.compactMap { id, total in
            store.data.exercise(id).map { Summary(exercise: $0, sessions: total.count, seconds: total.seconds, meters: total.meters, latest: total.latest) }
        }.sorted { $0.latest.date > $1.latest.date }
    }

    var body: some View {
        let monthly = days == 0 || days > 120
        let all = summaries
        let buckets = store.data.cardioBuckets(programID: programID, since: since, exerciseID: exerciseID, distance: distance, monthly: monthly)
        let values = buckets.map { distance ? DistanceDisplay.value($0.volume) : $0.volume / 60 }
        let color = progressColor(0, scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            Picker("Measure", selection: $distance) { Text("Time").tag(false); Text("Distance").tag(true) }
                .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("cardio.measure")
            if all.isEmpty {
                Text("No cardio logged in this range. Log time or distance on a cardio exercise to see it here.")
                    .foregroundStyle(.secondary).padding(.vertical, 24)
            } else {
                if all.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("All cardio") { exerciseID = nil }.buttonStyle(ChipStyle(selected: exerciseID == nil, onCard: true))
                            ForEach(all) { row in Button(row.exercise.name) { exerciseID = row.id }.buttonStyle(ChipStyle(selected: exerciseID == row.id, onCard: true)) }
                        }.padding(.horizontal, 1)
                    }
                }
                if values.allSatisfy({ $0 == 0 }) {
                    Text(distance ? "No distance logged in this range." : "No time logged in this range.").foregroundStyle(.secondary).padding(.vertical, 24)
                } else {
                    chart(buckets, values: values, monthly: monthly, color: color)
                }
                VStack(spacing: 0) {
                    ForEach(all) { row in
                        NavigationLink { ExerciseProgress(exerciseID: row.id, programID: programID) } label: { summaryRow(row) }.buttonStyle(.plain)
                        if row.id != all.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder private func chart(_ buckets: [VolumeBucket], values: [Double], monthly: Bool, color: Color) -> some View {
        // The period in progress is shown but left out of the average, and the headline starts on the last full one.
        let complete = buckets.count > 1 ? Array(values.dropLast()) : values
        let average = complete.reduce(0, +) / Double(max(complete.count, 1))
        let selected = selectedDate.flatMap { date in buckets.lastIndex { $0.start <= date } } ?? (buckets.count > 1 ? buckets.count - 2 : 0)
        VStack(alignment: .leading, spacing: 2) {
            Text(amount(values[selected])).font(.figure(28)).foregroundStyle(.primary)
            Text(caption(buckets, values: values, index: selected, monthly: monthly)).font(.caption).foregroundStyle(.secondary)
            Text("Average \(amount(average)) a \(monthly ? "month" : "week")").font(.caption).foregroundStyle(.secondary)
        }
        Chart {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                BarMark(x: .value(monthly ? "Month" : "Week", bucket.start, unit: monthly ? .month : .weekOfYear), y: .value(distance ? "Distance" : "Minutes", values[index]))
                    .foregroundStyle(color).opacity(selectedDate == nil || index == selected ? 1 : 0.45).cornerRadius(3)
            }
            RuleMark(y: .value("Average", average)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel { if let amount = value.as(Double.self) { Text(number(amount, decimals: distance ? 1 : 0)) } }
            }
        }
        .chartYAxisLabel(distance ? DistanceDisplay.unit.rawValue : "min", position: .topLeading)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: monthly ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day()) } }
        .frame(height: 200)
        .accessibilityLabel("\(monthly ? "Monthly" : "Weekly") cardio \(distance ? "distance" : "time"), average \(amount(average))")
    }

    private func summaryRow(_ row: Summary) -> some View {
        let latest = [row.latest.meters > 0 ? distanceText(row.latest.meters) : nil, row.latest.seconds > 0 ? clockText(row.latest.seconds) : nil,
                      row.latest.meters > 0 && row.latest.seconds > 0 ? paceText(row.latest.seconds / row.latest.meters * 1000) : nil].compactMap { $0 }
        let totals = [counted(row.sessions, "session"), row.meters > 0 ? distanceText(row.meters) : nil, row.seconds > 0 ? hours(row.seconds) : nil].compactMap { $0 }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.exercise.name).font(.headline).foregroundStyle(.primary)
                Text(totals.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(latest.prefix(2).joined(separator: " · ")).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(latest.count > 2 ? "\(latest[2]) · \(row.latest.date.formatted(.dateTime.month(.abbreviated).day()))" : row.latest.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }

    /// "18.4 km" or "2 h 15 min".
    private func amount(_ value: Double) -> String {
        distance ? "\(number(value, decimals: 1)) \(DistanceDisplay.unit.rawValue)" : hours(value * 60)
    }
    private func hours(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func caption(_ buckets: [VolumeBucket], values: [Double], index: Int, monthly: Bool) -> String {
        if index == buckets.count - 1, buckets.count > 1 { return monthly ? "This month so far" : "This week so far" }
        let label = monthly ? buckets[index].start.formatted(.dateTime.month(.wide).year()) : "Week of \(buckets[index].start.formatted(.dateTime.month(.abbreviated).day()))"
        guard index > 0, values[index - 1] > 0 else { return label }
        let change = (values[index] - values[index - 1]) / values[index - 1] * 100
        return "\(label) · \(change >= 0 ? "up" : "down") \(number(abs(change), decimals: 0))% on the \(monthly ? "month" : "week") before"
    }
}
