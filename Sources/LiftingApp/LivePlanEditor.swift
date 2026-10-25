import SwiftUI
import LiftingCore

struct LivePlanEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let exerciseID: UUID
    let setID: UUID
    @State var plan: SetPlan
    /// Deleted from the details: nothing is left to save.
    @State private var removed = false
    init(exerciseID: UUID, setID: UUID, initial: SetPlan) { self.exerciseID = exerciseID; self.setID = setID; _plan = State(initialValue: initial) }
    var body: some View {
        DraftEditor(valid: plan.isValid, changed: !removed && store.data.activeSession?.exercises.first { $0.id == exerciseID }?.sets.first { $0.id == setID }?.plan != plan, save: {
            store.perform { try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }
        }) {
            if plan.kind == .warmup, let item = store.data.activeSession?.exercises.first(where: { $0.id == exerciseID }) {
                WarmupSetEditor(plan: $plan, badge: item.sets.firstIndex { $0.id == setID }.map { setBadge(item.sets.map(\.plan), index: $0, types: store.data.customSetTypes) },
                                name: item.name, weight: loggedSet?.wrappedValue.weight, loggedSet: loggedSet,
                                remove: { removed = true; store.editExercise(exerciseID) { $0.sets.removeAll { $0.id == setID } } })
            } else {
                PlanEditor(plan: $plan, unit: store.data.settings.unit, suggestedWeight: loggedSet?.wrappedValue.weight, ownsDraft: false, loggedSet: loggedSet)
            }
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
