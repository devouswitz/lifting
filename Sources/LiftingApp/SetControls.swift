import SwiftUI
import LiftingCore

struct SetTypeButton<Label: View>: View {
    @EnvironmentObject private var store: AppStore
    let plan: SetPlan
    let change: (SetPlan) -> Void
    let details: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: { label().frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .confirmationDialog("Set Type", isPresented: $choosing, titleVisibility: .visible) {
                ForEach(SetKind.allCases) { kind in Button(kind.title) { select(kind) } }
                ForEach(store.data.customSetTypes) { type in Button(type.name) { select(type.countsAs, customID: type.id) } }
                Button("Cancel", role: .cancel) {}
            }
            .contextMenu { Button(plan.kind == .warmup ? "Warm-up Settings" : "Set Details", systemImage: "slider.horizontal.3", action: details) }
            .accessibilityAction(named: "Set details", details)
            .accessibilityLabel("\(plan.kind.title), change set type")
            .accessibilityValue(plan.load == .percent ? "\(number(plan.percent))% of working weight" : "")
    }
    private func select(_ kind: SetKind, customID: UUID? = nil) {
        var edited = plan
        if kind == .warmup && plan.load == .working { edited.load = .percent }
        else if plan.kind == .warmup && kind != .warmup && plan.load == .percent { edited.load = .working }
        edited.kind = kind; edited.customTypeID = customID
        change(edited)
    }
}

struct QuickAddButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    let index: Int
    let action: (QuickAdd) -> Void
    private var slot: QuickAdd { QuickAdd.slots(store.data)[index] }
    var body: some View {
        Button { action(slot) } label: {
            Text(slot.title(store.data)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(slot.color(palette))
        }.buttonStyle(FieldButtonStyle(role: .technique))
            .contextMenu {
                Section("Change Button") {
                    ForEach(QuickAdd.options(store.data), id: \.self) { option in
                        Button { assign(option) } label: {
                            if option == slot { Label(option.title(store.data), systemImage: "checkmark") }
                            else { Text(option.title(store.data)) }
                        }
                    }
                }
                NavigationLink { SetTypesView() } label: { Label("Manage Set Types", systemImage: "square.stack.3d.up") }
            }
            .accessibilityHint("Long-press to change this button")
            .accessibilityActions {
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
