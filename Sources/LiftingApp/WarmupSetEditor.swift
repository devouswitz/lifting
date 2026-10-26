import SwiftUI
import LiftingCore

/// A warm-up's details, trimmed to what a warm-up uses: its load and reps up front, rest and type below,
/// and RPE, time, and distance folded away.
struct WarmupSetEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var plan: SetPlan
    var badge: String? = nil
    var name: String? = nil
    /// The resolved weight, shown under the percentage.
    var weight: Double? = nil
    var loggedSet: Binding<LoggedSet>? = nil
    var remove: (() -> Void)? = nil
    @State private var editing: Edit?
    @State private var more = false
    private enum Edit: Identifiable {
        case keypad(NumericEdit), reps
        var id: String { if case .keypad(let edit) = self { return "keypad.\(edit.id)" }; return "reps" }
    }
    private var unit: WeightUnit { store.data.settings.unit }

    var body: some View {
        ThemedForm {
            Section {
                HStack(spacing: 12) {
                    tile(load.title, load.value, load.caption, action: load.edit.map { edit in { editing = .keypad(edit) } })
                    tile("Reps", plan.repTarget.map(displayTarget) ?? "–", repCaption) { editing = .reps }
                }
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section {
                Picker("Warm-up weight", selection: $plan.load) {
                    Text("% of working").tag(LoadRule.percent)
                    Text("Fixed weight").tag(LoadRule.fixed)
                    if plan.load == .working { Text("Working").tag(LoadRule.working) }
                    Text("No weight").tag(LoadRule.none)
                }.pickerStyle(.segmented).labelsHidden()
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section {
                DurationRow("Rest after", seconds: $plan.restSeconds, placeholder: "Warm-up default").accessibilityIdentifier("plan.rest")
                Picker("Type", selection: setTypeChoice($plan, types: palette.setTypes)) {
                    ForEach(SetKind.allCases) { Text($0.title).tag(SetTypeChoice.kind($0)) }
                    ForEach(palette.setTypes) { Text($0.name).tag(SetTypeChoice.custom($0.id)) }
                }
            }
            Section {
                DisclosureGroup(isExpanded: $more) {
                    NumberRow("RPE", value: $plan.rpe).accessibilityIdentifier("plan.rpe")
                    DurationRow(title: "Time", seconds: $plan.seconds).accessibilityIdentifier("plan.seconds")
                    NumberRow("Distance (\(DistanceDisplay.unit.rawValue))", value: $plan.meters, factor: DistanceDisplay.unit.meters).accessibilityIdentifier("plan.meters")
                    if let loggedSet {
                        DurationRow(title: "Logged time", seconds: loggedSet.seconds)
                        NumberRow("Logged distance (\(DistanceDisplay.unit.rawValue))", value: loggedSet.meters, factor: DistanceDisplay.unit.meters)
                    }
                } label: {
                    LabeledContent("RPE, time, distance") { Text(extras).foregroundStyle(.secondary) }
                }
            }
            if let remove {
                Section { Button("Delete Set", role: .destructive) { remove(); dismiss() }.frame(maxWidth: .infinity) }
            }
        }
        .formStyle(.grouped).inlineTitle()
        .navigationTitle(name ?? "Warm-up")
        .toolbar {
            if let badge {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) { SetBadge(text: badge, plan: plan); Text(name ?? palette.title(plan)).font(.headline) }
                }
            }
        }
        .sheet(item: $editing) { edit in
            switch edit {
            case .keypad(let numeric): NumberEditor(edit: numeric)
            case .reps: RepValuesEditor(plan: plan) { edited in plan.takeTarget(from: edited); return true }
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            VStack(spacing: 4) {
                Text(title).font(.footnote).foregroundStyle(.secondary)
                Text(value).font(.figure(34)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
                Text(caption).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(palette.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }.buttonStyle(.plain).disabled(action == nil)
    }

    private var load: (title: String, value: String, caption: String, edit: NumericEdit?) {
        let weightCaption = weight.map { "\(number(unit.display($0))) \(unit.rawValue)" } ?? ""
        switch plan.load {
        case .percent:
            return ("% of working", number(plan.percent), weightCaption,
                    NumericEdit(title: "Percent of Working Set", context: name, value: plan.percent, step: 5, maximum: 1000) { plan.percent = $0 ?? 0; return true })
        case .fixed:
            return ("Weight", number(unit.display(plan.fixedWeight)), unit.rawValue,
                    NumericEdit(title: "Weight", context: name, value: unit.display(plan.fixedWeight), step: unit == .kg ? 2.5 : 5, maximum: 10000) { plan.fixedWeight = unit.kilograms($0 ?? 0); return true })
        case .working:
            return ("Weight", weight.map { number(unit.display($0)) } ?? "–", "working weight",
                    NumericEdit(title: "Weight", context: name, value: plan.weightOverride.map(unit.display), step: unit == .kg ? 2.5 : 5, maximum: 10000) { plan.weightOverride = $0.map(unit.kilograms); return true })
        case .none:
            return ("Weight", "–", "none", nil)
        }
    }
    private var repCaption: String {
        switch RepTargetMode(plan) { case .exact: return "exact"; case .range: return "range"; case .amrap: return "AMRAP"; case .none: return "no count" }
    }
    private var extras: String {
        let parts = [plan.rpe.map { "RPE \(number($0))" }, plan.seconds.map(clockText), plan.meters.map(distanceText)].compactMap { $0 }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }
}

/// A set's type as one picker value, a built-in kind or a custom type.
func setTypeChoice(_ plan: Binding<SetPlan>, types: [CustomSetType]) -> Binding<SetTypeChoice> {
    Binding(get: { plan.wrappedValue.customTypeID.flatMap { id in types.contains { $0.id == id } ? .custom(id) : nil } ?? .kind(plan.wrappedValue.kind) }, set: { choice in
        switch choice {
        case .kind(let kind): plan.wrappedValue.kind = kind; plan.wrappedValue.customTypeID = nil
        case .custom(let id): plan.wrappedValue.customTypeID = id; plan.wrappedValue.kind = types.first { $0.id == id }?.countsAs ?? .working
        }
    })
}
