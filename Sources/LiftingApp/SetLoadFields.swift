import SwiftUI
import LiftingCore

struct SetLoadFields: View {
    @Binding var plan: SetPlan
    let unit: WeightUnit
    var suggestedWeight: Double?
    var body: some View {
        Section(plan.kind == .warmup ? "Warm-up weight" : "Weight") {
            Picker("Based on", selection: $plan.load) { ForEach(LoadRule.allCases) { Text($0.title).tag($0) } }
            switch plan.load {
            case .working:
                NumberRow("Weight (\(unit.rawValue))", value: $plan.weightOverride, placeholder: suggestedWeight.map { number(unit.display($0)) } ?? "Suggested", factor: unit.kilograms(1))
            case .percent:
                PercentControl(title: "Percent of working set", value: $plan.percent, range: 0...1000)
            case .fixed:
                NumberRow("Weight (\(unit.rawValue))", value: $plan.fixedWeight, factor: unit.kilograms(1))
            case .none: EmptyView()
            }
        }
    }
}

struct LoadRuleEditor: View {
    @State var plan: SetPlan
    let unit: WeightUnit
    var suggestedWeight: Double?
    let save: (SetPlan) -> Bool
    @State private var original: SetPlan?
    var body: some View {
        DraftEditor(valid: plan.isValid, changed: original.map { $0 != plan } ?? false, save: { save(plan) }) {
            ThemedForm { SetLoadFields(plan: $plan, unit: unit, suggestedWeight: suggestedWeight) }
                .navigationTitle("Weight Settings").inlineTitle()
        }.onAppear { if original == nil { original = plan } }.sheetSize()
    }
}
