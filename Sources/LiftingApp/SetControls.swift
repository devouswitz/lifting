import SwiftUI
import LiftingCore

extension View {
    /// A hold that opens a value's extra settings, also offered as a named accessibility action.
    func longPress(_ label: String, perform action: @escaping () -> Void) -> some View {
        highPriorityGesture(LongPressGesture().onEnded { _ in action() }).accessibilityAction(named: label, action)
    }
}

/// The set badge. Tap to change the set's type, hold for Set Details. Drop and MYO convert the set
/// into a working drop or MYO activation set, with the lifter's Drop and MYO setup.
struct SetTypeButton<Label: View>: View {
    @EnvironmentObject private var store: AppStore
    let plan: SetPlan
    let change: (SetPlan) -> Void
    let convert: (Technique) -> Void
    let details: () -> Void
    var duplicate: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label
    @State private var choosing = false

    var body: some View {
        // A percentage label shares the badge's cell, so the badge gives up half its height.
        Button { choosing = true } label: { label().frame(minWidth: 44, minHeight: plan.load == .percent ? 26 : 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .confirmationDialog("Set Type", isPresented: $choosing, titleVisibility: .visible) {
                Button("Working") { select(.working) }
                Button("Warm-up") { select(.warmup) }
                Button("Drop") { convert(.drop) }
                Button("MYO") { convert(.myo) }
                Button("Failure") { select(.failure) }
                ForEach(store.data.customSetTypes) { type in Button(type.name) { select(type.countsAs, customID: type.id) } }
                Button("Set Details", action: details)
                if let duplicate { Button("Duplicate Set", action: duplicate) }
                Button("Cancel", role: .cancel) {}
            }
            .longPress("Set details", perform: details)
            .accessibilityLabel("\(plan.kind.title), change set type")
            .accessibilityValue(plan.load == .percent ? "\(number(plan.percent))% of working weight" : "")
    }
    private func select(_ kind: SetKind, customID: UUID? = nil) {
        var edited = plan
        if kind == .warmup && plan.load == .working { edited.load = .percent }
        else if plan.kind == .warmup && kind != .warmup && plan.load == .percent { edited.load = .working }
        // A failure set aims past its target; leaving failure keeps that goal as a plain target.
        if kind == .failure && customID == nil { edited.markToFailure() }
        else if plan.kind == .failure && kind != .failure && plan.amrap { edited.amrap = false }
        edited.kind = kind; edited.customTypeID = customID
        change(edited)
    }
}

/// One of the two quick-add buttons under each exercise. Tap adds the set type; Drop and MYO add a chain
/// with the lifter's setup. Hold to customize that chain or change the button.
struct QuickAddButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    let index: Int
    let run: (QuickAdd) -> Void
    let customize: (Technique) -> Void
    private var slot: QuickAdd { QuickAdd.slots(store.data)[index] }
    var body: some View {
        Button { run(slot) } label: {
            Text(slot.title(store.data)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(slot.color(palette))
        }.buttonStyle(FieldButtonStyle(role: .technique))
            .contextMenu {
                if let technique = slot.technique {
                    Button("\(slot.title(store.data)) Setup…", systemImage: "slider.horizontal.3") { customize(technique) }
                }
                Section("Change Button") {
                    ForEach(QuickAdd.options(store.data), id: \.self) { option in
                        Button { assign(option) } label: {
                            if option == slot { SwiftUI.Label(option.title(store.data), systemImage: "checkmark") }
                            else { Text(option.title(store.data)) }
                        }
                    }
                }
                NavigationLink { SetTypesView() } label: { SwiftUI.Label("Manage Set Types", systemImage: "square.stack.3d.up") }
            }
            .accessibilityHint("Hold to customize or change this button")
            .accessibilityActions {
                if let technique = slot.technique { Button("\(slot.title(store.data)) Setup") { customize(technique) } }
                ForEach(QuickAdd.options(store.data), id: \.self) { option in
                    Button("Change to \(option.title(store.data))") { assign(option) }
                }
            }
    }
    private func assign(_ option: QuickAdd) {
        store.perform { data in
            var slots = QuickAdd.slots(data).map(\.raw)
            slots[index] = option.raw
            data.settings.quickAdd = slots
        }
    }
}

/// The exercise's equipment as a choice menu. Choosing other equipment switches to that version of the
/// movement, creating it the first time; each version keeps its own history.
struct EquipmentMenu: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    let exerciseID: UUID
    let choose: (UUID) -> Void
    var body: some View {
        if let exercise = store.data.exercise(exerciseID), exercise.mode != .cardio {
            let family = store.data.equipmentFamily(of: exerciseID)
            let used = Set(family.map { ExerciseCategory.key(EquipmentFamily.equipment($0)) })
            Menu {
                ForEach(family) { member in
                    Button { if member.id != exerciseID { choose(member.id) } } label: {
                        if member.id == exerciseID { Label(title(member), systemImage: "checkmark") } else { Text(title(member)) }
                    }
                }
                let others = EquipmentFamily.choices.filter { !used.contains(ExerciseCategory.key($0)) }
                if !others.isEmpty {
                    Section("New Version") {
                        ForEach(others, id: \.self) { equipment in
                            Button(equipment) {
                                var created: UUID?
                                if store.perform({ created = try $0.equipmentVersion(of: exerciseID, equipment: equipment).id }), let created { choose(created) }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(title(exercise)).fontWeight(.semibold)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                }.font(.subheadline).foregroundStyle(palette.action).frame(minHeight: 30).contentShape(Rectangle())
            }.compactMenu().accessibilityLabel("Equipment, \(title(exercise))")
        }
    }
    private func title(_ exercise: Exercise) -> String {
        let equipment = EquipmentFamily.equipment(exercise)
        return equipment.isEmpty ? "Equipment" : equipment
    }
}
