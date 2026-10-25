import SwiftUI
import Charts
import LiftingCore

/// Training by muscle: average sets a week against the period before, or volume over time.
struct MuscleAnalyticsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) var scheme
    let programID: UUID?
    let since: Date
    /// The range in days; 0 is all of history.
    let days: Int
    @State private var volume = false
    @State private var secondary = false
    @State private var muscle: String?
    @State private var selectedDate: Date?

    private var unit: WeightUnit { store.data.settings.unit }
    private var firstSession: Date { store.data.sessions(inProgram: programID).map(\.startedAt).min() ?? .now }
    /// Weeks of history inside a window, so a window that starts before the first workout isn't diluted.
    private func weeks(from start: Date, to end: Date) -> Double { end.timeIntervalSince(max(start, firstSession)) / (7 * 86_400) }
    private var weeks: Double { max(1, weeks(from: since, to: .now)) }
    private var current: [MuscleSummary] { store.data.muscleSummary(programID: programID, since: since) }
    private var previousStart: Date { since.addingTimeInterval(-Double(days) * 86_400) }
    /// The same length of time just before the range, when at least two weeks of it were trained.
    /// All of history has nothing before it.
    private var previous: (summary: [MuscleSummary], weeks: Double)? {
        guard days > 0 else { return nil }
        let span = weeks(from: previousStart, to: since)
        guard span >= 2 else { return nil }
        return (store.data.muscleSummary(programID: programID, since: previousStart, until: since), span)
    }
    private var color: Color { progressColor(0, scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Measure", selection: $volume) { Text("Sets").tag(false); Text("Volume").tag(true) }
                .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("muscles.measure")
            if volume { volumeView } else { setsView }
        }
    }

    // MARK: Sets

    private struct SetRow: Identifiable { let name: String; let value: Double; let previous: Double?; var id: String { name } }

    @ViewBuilder private var setsView: some View {
        let before = previous
        let rows = current.map { row in
            SetRow(name: row.name, value: row.setCount(includeSecondary: secondary) / weeks,
                   previous: before.map { list in (list.summary.first { $0.name == row.name }?.setCount(includeSecondary: secondary) ?? 0) / list.weeks })
        }.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        Toggle("Include secondary muscles (½ set)", isOn: $secondary).font(.subheadline)
        if rows.isEmpty {
            Text("No logged strength sets in this range.").foregroundStyle(.secondary).padding(.vertical, 24)
        } else {
            let scale = max(1, rows.map { max($0.value, $0.previous ?? 0) }.max() ?? 1)
            Text("Average sets a week").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.name).font(.subheadline).lineLimit(1).frame(width: 92, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 4, topTrailing: 4)).fill(color)
                                    .frame(width: max(2, geometry.size.width * row.value / scale), height: 14)
                                if let previous = row.previous {
                                    Capsule().fill(Color.secondary).frame(width: 2, height: 20).offset(x: geometry.size.width * previous / scale - 1)
                                }
                            }.frame(maxHeight: .infinity)
                        }.frame(height: 20)
                        Text(number(row.value, decimals: 1)).font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel(row.name)
                    .accessibilityValue("\(number(row.value, decimals: 1)) sets a week\(row.previous.map { ", previously \(number($0, decimals: 1))" } ?? "")")
                }
            }.accessibilityIdentifier("muscles.chart")
            if before != nil {
                HStack(spacing: 16) {
                    legendItem("This period") { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8) }
                    legendItem("Period before") { Capsule().fill(Color.secondary).frame(width: 2, height: 14) }
                }
            }
            let total = rows.reduce(0) { $0 + $1.value }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    listRow(row.name, detail: "\(number(row.value, decimals: 1)) sets a week" + (row.previous.map { " · before \(number($0, decimals: 1))" } ?? ""),
                            share: total > 0 ? row.value / total : 0)
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: Volume

    @ViewBuilder private var volumeView: some View {
        let monthly = days == 0 || days > 120
        let buckets = store.data.volumeBuckets(programID: programID, since: since, muscle: muscle, monthly: monthly)
        let values = buckets.map { unit.display($0.volume) }
        let muscles = current.filter { $0.volume > 0 }.sorted { $0.volume > $1.volume }
        // The period in progress is shown but left out of the average, and the headline starts on the last full one.
        let complete = buckets.count > 1 ? Array(values.dropLast()) : values
        let selected = selectedDate.flatMap { date in buckets.lastIndex { $0.start <= date } } ?? (buckets.count > 1 ? buckets.count - 2 : 0)
        if values.allSatisfy({ $0 == 0 }) {
            Text("No logged weight and reps in this range.").foregroundStyle(.secondary).padding(.vertical, 24)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("All muscles") { muscle = nil }.buttonStyle(ChipStyle(selected: muscle == nil, onCard: true))
                    ForEach(muscles) { row in Button(row.name) { muscle = row.name }.buttonStyle(ChipStyle(selected: muscle == row.name, onCard: true)) }
                }.padding(.horizontal, 1)
            }
            let average = complete.reduce(0, +) / Double(max(complete.count, 1))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(short(values[selected])) \(unit.rawValue)").font(.figure(28)).foregroundStyle(.primary)
                Text(bucketCaption(buckets, values: values, index: selected, monthly: monthly)).font(.caption).foregroundStyle(.secondary)
                Text("Average \(short(average)) \(unit.rawValue) a \(monthly ? "month" : "week")").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    BarMark(x: .value(monthly ? "Month" : "Week", bucket.start, unit: monthly ? .month : .weekOfYear), y: .value("Volume", values[index]))
                        .foregroundStyle(color).opacity(selectedDate == nil || index == selected ? 1 : 0.45).cornerRadius(3)
                }
                RuleMark(y: .value("Average", average)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                    AxisValueLabel { if let amount = value.as(Double.self) { Text(short(amount)) } }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: monthly ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day()) } }
            .frame(height: 200)
            .accessibilityLabel("\(monthly ? "Monthly" : "Weekly") volume\(muscle.map { " for \($0)" } ?? ""), average \(short(average)) \(unit.rawValue)")
            let total = muscles.reduce(0) { $0 + $1.volume }
            VStack(spacing: 0) {
                ForEach(muscles) { row in
                    listRow(row.name, detail: "\(short(unit.display(row.volume) / weeks)) \(unit.rawValue) a week", share: total > 0 ? row.volume / total : 0)
                    if row.id != muscles.last?.id { Divider() }
                }
            }
        }
    }

    private func bucketCaption(_ buckets: [VolumeBucket], values: [Double], index: Int, monthly: Bool) -> String {
        if index == buckets.count - 1, buckets.count > 1 { return monthly ? "This month so far" : "This week so far" }
        let label = monthly ? buckets[index].start.formatted(.dateTime.month(.wide).year()) : "Week of \(buckets[index].start.formatted(.dateTime.month(.abbreviated).day()))"
        guard index > 0, values[index - 1] > 0 else { return label }
        let change = (values[index] - values[index - 1]) / values[index - 1] * 100
        return "\(label) · \(change >= 0 ? "up" : "down") \(number(abs(change), decimals: 0))% on the \(monthly ? "month" : "week") before"
    }

    /// 48k, 4.8k, or 480: volume reads at a glance.
    private func short(_ value: Double) -> String {
        value >= 10_000 ? "\(number(value / 1000, decimals: 0))k" : value >= 1000 ? "\(number(value / 1000, decimals: 1))k" : number(value, decimals: 0)
    }

    private func listRow(_ name: String, detail: String, share: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(number(share * 100, decimals: 0))%").monospacedDigit()
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    private func legendItem<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 6) { mark(); Text(title) }.font(.caption).foregroundStyle(.secondary)
    }
}
