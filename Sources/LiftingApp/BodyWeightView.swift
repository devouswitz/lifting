import SwiftUI
import Charts
import LiftingCore

/// Weigh-ins over time. The latest one before a workout sets the load of its bodyweight exercises.
struct BodyWeightView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    let since: Date
    @State private var editing: BodyWeightEntry?
    var body: some View {
        let unit = store.data.settings.unit
        let entries = store.data.bodyWeights.filter { $0.date >= since }
        VStack(alignment: .leading, spacing: 14) {
            if let latest = store.data.bodyWeights.last {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(number(unit.display(latest.kilograms))) \(unit.rawValue)").font(.figure(28))
                    Spacer()
                    Text(latest.date, format: .dateTime.month(.abbreviated).day().year()).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if entries.count > 1 {
                Chart(entries) { entry in
                    LineMark(x: .value("Date", entry.date), y: .value(unit.rawValue, unit.display(entry.kilograms))).foregroundStyle(palette.action)
                    PointMark(x: .value("Date", entry.date), y: .value(unit.rawValue, unit.display(entry.kilograms))).foregroundStyle(palette.action).symbolSize(24)
                }
                .chartYScale(domain: .automatic(includesZero: false)).frame(height: 200)
                .accessibilityLabel("Body weight chart")
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
