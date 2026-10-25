import SwiftUI
import LiftingCore

struct TemplatePlanEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var variant: Variant
    @State var plan: SetPlan
    let save: (Variant) -> Bool

    /// Deleting saves the day without the set; the draft then has nothing left to save.
    private func remove() {
        guard var edited = store.data.variant(variant.id) else { return }
        edited.sets.removeAll { $0.id == plan.id }
        if save(edited) { variant = edited }
    }

    var body: some View {
        DraftEditor(valid: plan.isValid, changed: variant.sets.first { $0.id == plan.id } != plan, save: {
            guard variant.sets.contains(where: { $0.id == plan.id }) else { return false }
            var edited = store.data.variant(variant.id) ?? variant
            guard let currentIndex = edited.sets.firstIndex(where: { $0.id == plan.id }) else { return false }
            edited.sets[currentIndex] = plan
            return save(edited)
        }) {
            if plan.kind == .warmup {
                WarmupSetEditor(plan: $plan, badge: variant.sets.firstIndex { $0.id == plan.id }.map { setBadge(variant.sets, index: $0, types: store.data.customSetTypes) },
                                name: store.data.exercise(variant.exerciseID)?.name, weight: variant.weight(for: plan), remove: remove)
            } else {
                PlanEditor(plan: $plan, unit: store.data.settings.unit, suggestedWeight: variant.weight(for: plan), ownsDraft: false)
            }
        }
    }
}
