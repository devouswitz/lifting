import SwiftUI
import LiftingCore

/// One of the quick-add buttons under each live exercise.
enum QuickAdd: Hashable {
    case drop, myo, warmup, failure, custom(UUID)
    init?(_ raw: String) {
        switch raw {
        case "drop": self = .drop
        case "myo": self = .myo
        case "warmup": self = .warmup
        case "failure": self = .failure
        default:
            guard raw.hasPrefix("type:"), let id = UUID(uuidString: String(raw.dropFirst(5))) else { return nil }
            self = .custom(id)
        }
    }
    var raw: String {
        switch self { case .drop: return "drop"; case .myo: return "myo"; case .warmup: return "warmup"; case .failure: return "failure"; case .custom(let id): return "type:\(id.uuidString)" }
    }
    static let defaults: [QuickAdd] = [.drop, .myo]
    /// The two buttons in use, falling back to the defaults for a missing or deleted choice.
    static func slots(_ data: TrainingData) -> [QuickAdd] {
        let saved = data.settings.quickAdd ?? []
        return (0..<2).map { index in
            guard saved.indices.contains(index), let value = QuickAdd(saved[index]), value.isAvailable(in: data) else { return defaults[index] }
            return value
        }
    }
    static func options(_ data: TrainingData) -> [QuickAdd] { [.drop, .myo, .warmup, .failure] + data.customSetTypes.map { .custom($0.id) } }
    func isAvailable(in data: TrainingData) -> Bool { if case .custom(let id) = self { return data.setType(id) != nil }; return true }
    func title(_ data: TrainingData) -> String {
        switch self { case .drop: return "Drop"; case .myo: return "MYO"; case .warmup: return "Warm-up"; case .failure: return "Failure"; case .custom(let id): return data.setType(id)?.name ?? "Set" }
    }
    func color(_ palette: Palette) -> Color {
        switch self {
        case .drop, .myo: return palette.technique
        case .warmup: return palette.warmup
        case .failure: return palette.failure
        case .custom(let id): return palette.color(for: SetPlan(customTypeID: id))
        }
    }
}

extension SetPlan {
    init(customTypeID: UUID?) { self.init(); self.customTypeID = customTypeID }
}

/// Built-in and custom set types, and which two appear as quick-add buttons in workouts.
struct SetTypesView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @State private var editing: CustomSetType?
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            Section("Built in") {
                builtIn("W1", SetPlan(kind: .warmup), "Warm-up", "Not counted in volume or progress")
                builtIn("1", SetPlan(kind: .working), "Working", "Counted")
                builtIn("D1", SetPlan(kind: .drop), "Drop", "Counted. Lighter sets right after a work set")
                builtIn("A", SetPlan(kind: .myoActivation), "MYO", "Counted. Activation set, then mini-sets")
                builtIn("F", SetPlan(kind: .failure), "Failure", "Counted. Taken to failure")
            }
            Section {
                ForEach(store.data.customSetTypes) { type in
                    Button { editing = type } label: {
                        HStack(spacing: 12) {
                            SetBadge(text: type.badge, plan: SetPlan(customTypeID: type.id)).frame(minWidth: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.name).foregroundStyle(Color.primary)
                                Text(countsText(type.countsAs)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                AddRow(title: "New Set Type") { editing = CustomSetType(name: "", badge: "", countsAs: .working) }.accessibilityIdentifier("settypes.new")
            } header: { Text("Custom") }
            Section {
                ForEach(0..<2, id: \.self) { index in
                    Picker(index == 0 ? "First button" : "Second button", selection: slotBinding(index)) {
                        ForEach(QuickAdd.options(store.data), id: \.self) { Text($0.title(store.data)).tag($0) }
                    }
                }
            } header: { Text("Quick-add buttons") } footer: { Text("Shown next to Add Set in workouts. Long-press either button during a workout to change it.") }
        }
        .formStyle(.grouped).navigationTitle("Set Types").inlineTitle()
        .sheet(item: $editing) { SetTypeEditor(type: $0).environmentObject(store).sheetSize() }
    }
    private func builtIn(_ badge: String, _ plan: SetPlan, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            SetBadge(text: badge, plan: plan).frame(minWidth: 34)
            VStack(alignment: .leading, spacing: 2) { Text(name); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func slotBinding(_ index: Int) -> Binding<QuickAdd> {
        Binding(get: { QuickAdd.slots(store.data)[index] }, set: { value in
            store.perform { d in var slots = QuickAdd.slots(d).map(\.raw); slots[index] = value.raw; d.settings.quickAdd = slots }
        })
    }
}

func countsText(_ kind: SetKind) -> String {
    switch kind { case .warmup: return "Counts as a warm-up"; case .failure: return "Counts as a failure set"; default: return "Counts as a working set" }
}

/// Name, badge, color, and counting rule for one custom set type.
struct SetTypeEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.palette) var palette
    @State var type: CustomSetType
    @State private var deleting = false
    private var isNew: Bool { !store.data.customSetTypes.contains { $0.id == type.id } }
    private var preview: Palette { var p = palette; p.setTypes = [type]; return p }
    var body: some View {
        NavigationStack {
            ThemedForm {
                StoreErrorRow()
                Section {
                    LabeledContent("Name") {
                        TextField("Back-off", text: $type.name).multilineTextAlignment(.trailing)
                            .onChange(of: type.name) { old, new in if type.badge.isEmpty || type.badge == CustomSetType.suggestedBadge(for: old) { type.badge = CustomSetType.suggestedBadge(for: new) } }
                    }
                    LabeledContent("Badge") {
                        TextField("B", text: Binding(get: { type.badge }, set: { type.badge = String($0.prefix(3)).uppercased() })).multilineTextAlignment(.trailing)
                    }
                    Picker("Counts as", selection: $type.countsAs) {
                        Text("Working set").tag(SetKind.working)
                        Text("Warm-up").tag(SetKind.warmup)
                        Text("Failure set").tag(SetKind.failure)
                    }
                } footer: { Text(type.countsAs == .warmup ? "Not counted in volume, records, or progression, and grouped with warm-ups." : "Counted in volume and records like a working set.") }
                Section {
                    Toggle("Use the Drop and MYO color", isOn: Binding(get: { type.color == nil }, set: { type.color = $0 ? nil : ColorTheme.format(ColorRole.technique.defaultHex(dark: palette.dark)) }))
                    if type.color != nil {
                        ColorPicker("Color", selection: Binding(get: { type.color.flatMap(ColorTheme.parse).map { Color(hex: UInt($0)) } ?? palette.technique }, set: { type.color = $0.hexValue.map(ColorTheme.format) }), supportsOpacity: false)
                    }
                    HStack {
                        Text("Preview")
                        Spacer()
                        SetBadge(text: type.badge.isEmpty ? "?" : type.badge, plan: SetPlan(customTypeID: type.id)).environment(\.palette, preview)
                    }
                }
                if !isNew {
                    Section { Button("Delete Set Type", role: .destructive) { deleting = true } }
                }
            }
            .formStyle(.grouped).navigationTitle(isNew ? "New Set Type" : type.name).inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.perform({ try $0.saveSetType(type) }) { dismiss() } }
                        .disabled(type.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || type.badge.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(type.name)?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete Set Type", role: .destructive) { if store.perform({ $0.removeSetType(type.id) }) { dismiss() } }
            } message: { Text("Sets that used it keep counting the same way and show as \(type.countsAs.title).") }
        }
    }
}
