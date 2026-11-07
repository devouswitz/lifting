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
        let efforts: [CardioEffort]
        /// The exercise's place in the cardio palette, fixed so a run keeps its color across ranges.
        let colorIndex: Int
        var id: UUID { exercise.id }
        var latest: CardioEffort { efforts[efforts.count - 1] }
        var seconds: Double { efforts.reduce(0) { $0 + $1.seconds } }
        var meters: Double { efforts.reduce(0) { $0 + $1.meters } }
    }

    /// Cardio exercises logged in the range, most recent first.
    private var summaries: [Summary] {
        let order = store.data.exercises.filter { $0.mode == .cardio }.sorted { $0.name < $1.name }.map(\.id)
        return order.enumerated().compactMap { index, id in
            guard let exercise = store.data.exercise(id) else { return nil }
            let efforts = store.data.cardioEfforts(exerciseID: id, programID: programID, since: since)
            return efforts.isEmpty ? nil : Summary(exercise: exercise, efforts: efforts, colorIndex: index)
        }.sorted { $0.latest.date > $1.latest.date }
    }

    /// One bar segment: an exercise's time or distance in one week or month.
    private struct Segment: Identifiable {
        let index: Int
        let start: Date
        let name: String
        let value: Double
        var id: String { "\(index).\(name)" }
    }

    var body: some View {
        let monthly = days == 0 || days > 120
        let all = summaries
        let shown = all.filter { exerciseID == nil || $0.id == exerciseID }
        // Every exercise's buckets start on the same week or month, so they stack.
        let first = since == .distantPast ? all.map { $0.efforts[0].date }.min() ?? since : since
        let series = shown.map { row in
            (row, store.data.cardioBuckets(programID: programID, since: first, exerciseID: row.id, distance: distance, monthly: monthly)
                .map { distance ? DistanceDisplay.value($0.volume) : $0.volume / 60 })
        }
        let buckets = store.data.cardioBuckets(programID: programID, since: first, exerciseID: exerciseID, distance: distance, monthly: monthly)
        let values = buckets.indices.map { index in series.reduce(0) { $0 + ($1.1.indices.contains(index) ? $1.1[index] : 0) } }
        let segments = series.flatMap { row, amounts in
            amounts.enumerated().map { Segment(index: $0.offset, start: buckets.indices.contains($0.offset) ? buckets[$0.offset].start : .now, name: row.exercise.name, value: $0.element) }
        }
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
                    chart(buckets, values: values, segments: segments, rows: shown, monthly: monthly)
                }
                VStack(spacing: 0) {
                    ForEach(all) { row in
                        NavigationLink { ExerciseProgress(exerciseID: row.id, programID: programID) } label: { summaryRow(row, dot: all.count > 1) }.buttonStyle(.plain)
                        if row.id != all.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder private func chart(_ buckets: [VolumeBucket], values: [Double], segments: [Segment], rows: [Summary], monthly: Bool) -> some View {
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
            ForEach(segments) { segment in
                BarMark(x: .value(monthly ? "Month" : "Week", segment.start, unit: monthly ? .month : .weekOfYear), y: .value(distance ? "Distance" : "Minutes", segment.value))
                    .foregroundStyle(by: .value("Exercise", segment.name))
                    .opacity(selectedDate == nil || segment.index == selected ? 1 : 0.45).cornerRadius(3)
            }
            RuleMark(y: .value("Average", average)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartForegroundStyleScale(domain: rows.map(\.exercise.name), range: rows.map { progressColor($0.colorIndex, scheme: scheme) })
        .chartLegend(.hidden)
        .chartOverlay { proxy in GeometryReader { ChartScrub(proxy: proxy, geometry: $0, date: $selectedDate) } }
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

    private func summaryRow(_ row: Summary, dot: Bool) -> some View {
        let latest = row.latest
        let measured = [latest.meters > 0 ? distanceText(latest.meters) : nil, latest.seconds > 0 ? clockText(latest.seconds) : nil].compactMap { $0 }
        let date = latest.date.formatted(.dateTime.month(.abbreviated).day())
        let totals = [counted(row.efforts.count, "session"), row.meters > 0 ? distanceText(row.meters) : nil, row.seconds > 0 ? hours(row.seconds) : nil].compactMap { $0 }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if dot { Circle().fill(progressColor(row.colorIndex, scheme: scheme)).frame(width: 8, height: 8) }
                    Text(row.exercise.name).font(.headline).foregroundStyle(.primary)
                }
                Text(totals.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(measured.joined(separator: " · ")).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(latest.pace.map { "\(paceText($0)) · \(date)" } ?? date).font(.caption).foregroundStyle(.secondary).monospacedDigit()
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
