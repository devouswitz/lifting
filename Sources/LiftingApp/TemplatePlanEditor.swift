import SwiftUI
import LiftingCore

struct TemplatePlanEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var variant: Variant
    @State var plan: SetPlan
    let save: (Variant) -> Bool

    var body: some View {
        NavigationStack {
            PlanEditor(plan: $plan, unit: store.data.settings.unit, suggestedWeight: variant.weight(for: plan))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let index = variant.sets.firstIndex(where: { $0.id == plan.id }) else { return }
                            variant.sets[index] = plan
                            if save(variant) { dismiss() }
                        }
                    }
                }
        }
    }
}
