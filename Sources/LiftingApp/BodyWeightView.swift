import SwiftUI
import Charts
import LiftingCore

/// Weigh-ins over time, with a 7-day average so one heavy morning doesn't swing the trend.
/// The latest weigh-in before a workout sets the load of its bodyweight exercises.
struct BodyWeightView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) var scheme
    let since: Date
    @State private var editing: BodyWeightEntry?
    var body: some View {
        let unit = store.data.settings.unit
        let entries = store.data.bodyWeights.filter { $0.date >= since }
        let trend = store.data.bodyWeightTrend(since: since)
        let color = progressColor(0, scheme: scheme)
        VStack(alignment: .leading, spacing: 14) {
            if let latest = store.data.bodyWeights.last {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(number(unit.display(latest.kilograms))) \(unit.rawValue)").font(.figure(28))
                        Spacer()
                        Text(latest.date, format: .dateTime.month(.abbreviated).day().year()).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let summary = trendSummary(trend, unit: unit) { Text(summary).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            if entries.count > 1 {
                Chart {
                    ForEach(entries) { entry in
                        PointMark(x: .value("Date", entry.date), y: .value("Weigh-in", unit.display(entry.kilograms)))
                            .foregroundStyle(color.opacity(0.45)).symbolSize(22)
                    }
                    ForEach(trend, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("7-day average", unit.display(point.average)))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { AxisGridLine().foregroundStyle(.primary.opacity(0.1)); AxisValueLabel() } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisGridLine().foregroundStyle(.primary.opacity(0.06)); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxisLabel(unit.rawValue, position: .topLeading)
                .frame(height: 200)
                .accessibilityLabel("Body weight: weigh-ins and 7-day average")
                HStack(spacing: 16) {
                    HStack(spacing: 6) { Circle().fill(color.opacity(0.45)).frame(width: 7, height: 7); Text("Weigh-in") }
                    HStack(spacing: 6) { Capsule().fill(color).frame(width: 14, height: 2); Text("7-day average") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Button { editing = BodyWeightEntry(date: .now, kilograms: store.data.bodyWeights.last?.kilograms ?? 0) } label: {
                Label("Log Body Weight", systemImage: "plus")
            }.buttonStyle(FieldButtonStyle()).accessibilityIdentifier("bodyweight.log")
            VStack(spacing: 0) {
                ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    Button { editing = entry } label: {
                        HStack {
                            Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()).foregroundStyle(Color.primary)
                            Spacer()
                            Text("\(number(unit.display(entry.kilograms))) \(unit.rawValue)").monospacedDigit().foregroundStyle(.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { store.perform { $0.removeBodyWeight(entry.id) } } }
                }
            }
        }
        .sheet(item: $editing) { BodyWeightEditor(entry: $0).environmentObject(store) }
    }

    /// The latest 7-day average, and its weekly rate of change once there are two weeks to measure.
    private func trendSummary(_ trend: [BodyWeightTrend], unit: WeightUnit) -> String? {
        guard let last = trend.last else { return nil }
        let average = "7-day average \(number(unit.display(last.average), decimals: 1)) \(unit.rawValue)"
        guard let first = trend.first, trend.count >= 3 else { return average }
        let weeks = last.date.timeIntervalSince(first.date) / (7 * 86_400)
        guard weeks >= 2 else { return average }
        let rate = unit.display(last.average - first.average) / weeks
        if abs(rate) < 0.05 { return "\(average) · steady" }
        return "\(average) · \(rate < 0 ? "down" : "up") \(number(abs(rate), decimals: 1)) \(unit.rawValue) a week"
    }
}

struct BodyWeightEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: BodyWeightEntry
    @State private var deleted = false
    private var isNew: Bool { !store.data.bodyWeights.contains { $0.id == entry.id } }
    var body: some View {
        let unit = store.data.settings.unit
        DraftEditor(valid: entry.isValid && !deleted, changed: !deleted && (isNew || store.data.bodyWeights.first { $0.id == entry.id } != entry),
                    saveID: "bodyweight.save", confirmation: isNew ? "Add" : nil, save: { store.perform { try $0.saveBodyWeight(entry) } }) {
            ThemedForm {
                StoreErrorRow()
                Section {
                    NumberRow("Weight (\(unit.rawValue))", value: $entry.kilograms, factor: unit.kilograms(1))
                    DatePicker("Date", selection: $entry.date)
                }
                if !isNew {
                    Section { Button("Delete Weigh-in", role: .destructive) { if store.perform({ $0.removeBodyWeight(entry.id) }) { deleted = true; dismiss() } } }
                }
            }.formStyle(.grouped).navigationTitle(isNew ? "Log Body Weight" : "Weigh-in").inlineTitle()
        }.presentationDetents([.medium, .large])
    }
}
