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
        DraftEditor(valid: plan.isValid, changed: store.data.activeSession?.exercises.first { $0.id == exerciseID }?.sets.first { $0.id == setID }?.plan != plan, save: {
            store.perform { try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }
        }) {
            PlanEditor(plan: $plan, unit: store.data.settings.unit, suggestedWeight: loggedSet?.wrappedValue.weight, ownsDraft: false, loggedSet: loggedSet)
        }
    }
    private var loggedSet: Binding<LoggedSet>? {
        guard let current = store.data.activeSession?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == setID }) else { return nil }
        return Binding(get: {
            store.data.activeSession?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == setID }) ?? current
        }, set: { edited in
            store.editExercise(exerciseID) { exercise in
                guard let index = exercise.sets.firstIndex(where: { $0.id == setID }) else { return }
                exercise.sets[index].seconds = edited.seconds
                exercise.sets[index].meters = edited.meters
            }
        })
    }
}
