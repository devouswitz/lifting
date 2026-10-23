import SwiftUI
import LiftingCore

struct LivePlanEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let exerciseID: UUID
    let setID: UUID
    @State var plan: SetPlan
    init(exerciseID: UUID, setID: UUID, initial: SetPlan) { self.exerciseID = exerciseID; self.setID = setID; _plan = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            PlanEditor(plan: $plan, unit: store.data.settings.unit)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply Today") { if store.perform({ try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }) { dismiss() } } }
                }
        }
    }
}

