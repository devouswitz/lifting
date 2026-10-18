import SwiftUI
import Charts
import LiftingCore

struct MuscleAnalyticsView: View {
    @EnvironmentObject var store: AppStore
    let programID: UUID?
    let since: Date
    @State private var volume = false
    @State private var secondary = false
    var rows: [MuscleSummary] {
        store.data.muscleSummary(programID: programID, since: since).filter { value($0) > 0 }.sorted { value($0) > value($1) }
    }
    func value(_ row: MuscleSummary) -> Double { volume ? store.data.settings.unit.display(row.volume) : row.setCount(includeSecondary: secondary) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Measure", selection: $volume) { Text("Sets").tag(false); Text("Volume").tag(true) }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("muscles.measure")
            if !volume { Toggle("Include secondary muscles (½ set)", isOn: $secondary).font(.subheadline) }
            if rows.isEmpty { Text("No logged strength sets in this range.").foregroundStyle(.secondary).padding(.vertical, 24) }
            else {
                Chart(rows) { row in
                    BarMark(x: .value(volume ? store.data.settings.unit.rawValue : "Sets", value(row)), y: .value("Muscle", row.name)).foregroundStyle(Palette.accent)
                        .accessibilityLabel(row.name).accessibilityValue("\(number(value(row))) \(volume ? store.data.settings.unit.rawValue : "sets")")
                }.chartYScale(domain: rows.map(\.name)).chartXAxisLabel(volume ? "Volume (\(store.data.settings.unit.rawValue))" : "Logged sets")
                    .frame(height: CGFloat(max(180, rows.count * 36))).accessibilityIdentifier("muscles.chart")
                let total = rows.reduce(0) { $0 + value($1) }
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.headline)
                            Text("\(row.directSets) direct sets · \(number(store.data.settings.unit.display(row.volume), decimals: 0)) \(store.data.settings.unit.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(number(total > 0 ? value(row) / total * 100 : 0, decimals: 0))%").monospacedDigit()
                    }
                    if row.id != rows.last?.id { Divider() }
                }
            }
            Text(volume ? "Completed work sets with weight and reps, credited to the primary muscle." : "Completed work sets, including drop and MYO mini-sets. Warm-ups are excluded.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
