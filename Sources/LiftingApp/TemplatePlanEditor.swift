import SwiftUI
import LiftingCore

struct TemplatePlanEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var variant: Variant
    @State var plan: SetPlan
    let save: (Variant) -> Bool

    var body: some View {
        DraftEditor(valid: plan.isValid, changed: variant.sets.first { $0.id == plan.id } != plan, save: {
            guard variant.sets.contains(where: { $0.id == plan.id }) else { return false }
            var edited = store.data.variant(variant.id) ?? variant
            guard let currentIndex = edited.sets.firstIndex(where: { $0.id == plan.id }) else { return false }
            edited.sets[currentIndex] = plan
            return save(edited)
        }) {
            PlanEditor(plan: $plan, unit: store.data.settings.unit, suggestedWeight: variant.weight(for: plan), ownsDraft: false)
        }
    }
}
