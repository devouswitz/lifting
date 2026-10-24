import SwiftUI
import LiftingCore

struct LinkedExerciseEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    var routineID: UUID?
    var exerciseID: UUID?
    @State private var selection: Set<UUID> = []
    @State private var rest = 90
    @State private var transition = 0
    @State private var future = false
    @State private var originalGroup: String?
    @State private var initialSelection: Set<UUID> = []
    @State private var initialRest = 90
    @State private var initialTransition = 0
    @State private var loaded = false
    @State private var unlinked = false
    struct Member: Identifiable { var id: UUID; var name: String; var group: String; var rest: Int?; var transition: Int? }
    private var members: [Member] {
        if let routineID, let routine = store.data.routine(routineID) {
            return routine.slots.compactMap { slot in
                guard let v = store.data.variant(slot.variantID), let e = store.data.exercise(v.exerciseID) else { return nil }
                return Member(id: slot.id, name: e.name, group: slot.group, rest: slot.groupRestSeconds, transition: slot.transitionSeconds)
            }
        }
        return (store.data.activeSession?.exercises ?? []).map { Member(id: $0.id, name: $0.name, group: $0.group ?? "", rest: $0.groupRestSeconds, transition: $0.transitionSeconds) }
    }
    var body: some View {
        DraftEditor(valid: selection.count >= 2 && (0...86400).contains(rest) && (0...86400).contains(transition), changed: loaded && !unlinked && (selection != initialSelection || rest != initialRest || transition != initialTransition || future), saveID: "link.save", save: {
            store.perform { data in
                if let routineID { try data.linkRoutineExercises(routineID: routineID, slots: selection, rest: rest, transition: transition) }
                else { try data.linkSessionExercises(selection, rest: rest, transition: transition, saveFuture: future) }
            }
        }) {
            ThemedForm {
                StoreErrorRow()
                Section {
                    ForEach(members) { member in
                        Button { if selection.contains(member.id) { selection.remove(member.id) } else { selection.insert(member.id) } } label: {
                            HStack {
                                Text(member.name).foregroundStyle(Color.primary)
                                Spacer()
                                if selection.contains(member.id) { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(palette.technique) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityAddTraits(selection.contains(member.id) ? .isSelected : []).accessibilityIdentifier("link.member.\(member.id)")
                    }
                } header: { Text("Exercises") } footer: { Text("Two exercises make a superset; three or more make a circuit. You move through them in order, one set each round.") }
                Section("Rest") {
                    Stepper(value: $transition, in: 0...600, step: 5) { LabeledContent("Between exercises", value: transition == 0 ? "None" : clockText(Double(transition))) }
                    Stepper(value: $rest, in: 0...3600, step: 15) { LabeledContent("Between rounds", value: rest == 0 ? "None" : clockText(Double(rest))) }
                }
                if routineID == nil, store.data.activeSession?.routineID != nil { Toggle("Save to this day", isOn: $future) }
                if let originalGroup {
                    Button("Unlink exercises", role: .destructive) {
                        if store.perform({ d in
                            if let routineID { d.unlinkRoutineGroup(routineID: routineID, group: originalGroup) }
                            else { d.unlinkSessionGroup(originalGroup, saveFuture: future) }
                    }) { unlinked = true; store.cancelRestAlert(); dismiss() }
                    }
                }
            }.formStyle(.grouped).navigationTitle(selection.count > 2 ? "Circuit" : "Superset").inlineTitle()
        }.onAppear {
            guard !loaded else { return }
            if let exerciseID, let member = members.first(where: { $0.id == exerciseID }) {
                selection = [exerciseID]
                if !member.group.isEmpty {
                    originalGroup = member.group; selection = Set(members.filter { $0.group == member.group }.map(\.id))
                    rest = member.rest ?? 90; transition = member.transition ?? 0
                }
            }
            initialSelection = selection; initialRest = rest; initialTransition = transition; loaded = true
        }
    }
}
