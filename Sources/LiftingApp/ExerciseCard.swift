import SwiftUI
import LiftingCore

/// Where a card sits among its siblings: the header drags to reorder, and Move Up/Down stay available to assistive tech.
struct CardOrder {
    let id: UUID
    let canMoveUp: Bool
    let canMoveDown: Bool
    @Binding var dragging: UUID?
    let move: (Int) -> Void
}

/// One exercise, in the live workout or a saved day. The header collapses it and drags to reorder;
/// the ellipsis holds the exercise's actions; the content shows while expanded.
struct ExerciseCard<Status: View, MenuItems: View, Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let name: String
    var link: String? = nil
    /// Shown under the name while collapsed.
    let summary: String
    let expanded: Bool
    let toggle: () -> Void
    let order: CardOrder
    var accessibilityValue = ""
    /// Prefix for UI-test identifiers on the header and menu.
    var identifier: String? = nil
    @ViewBuilder let status: () -> Status
    @ViewBuilder let menu: () -> MenuItems
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button(action: toggle) { header }
                    .buttonStyle(.plain)
                    .modifier(ExerciseDragHandle(id: order.id, enabled: order.canMoveUp || order.canMoveDown, dragging: order.$dragging))
                    .modifier(ReorderActions(canMoveUp: order.canMoveUp, canMoveDown: order.canMoveDown, move: order.move))
                    .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(name)").accessibilityValue(accessibilityValue)
                    .accessibilityIdentifier(identifier.map { "\($0).collapse" } ?? "")
                Menu(content: menu) {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).frame(width: 32, height: 44)
                }.compactMenu().foregroundStyle(.secondary)
                    .accessibilityLabel("Options for \(name)").accessibilityIdentifier(identifier.map { "\($0).options" } ?? "")
            }
            if expanded { content() }
        }.card(padding: 16)
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline).foregroundStyle(.primary)
                if let link { Label(link, systemImage: "link").font(.footnote.weight(.medium)).foregroundStyle(palette.technique).lineLimit(2) }
                if !expanded { Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            status()
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}

/// Equipment, working load, and rest, under an expanded exercise.
struct ExerciseInfoRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let exerciseID: UUID
    /// Switches to the same movement on other equipment. Nil hides the menu.
    var swap: ((UUID) -> Void)? = nil
    var swapDisabled = false
    let load: String?
    let rest: Int
    let editRest: () -> Void
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            if let swap { EquipmentMenu(exerciseID: exerciseID, choose: swap).disabled(swapDisabled) }
            if let load { Text(load).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).accessibilityLabel("Working sets, " + load) }
            Button(action: editRest) {
                HStack(spacing: 4) {
                    Text("Rest").foregroundStyle(.secondary)
                    Text(clockText(Double(rest))).foregroundStyle(palette.rest).fontWeight(.semibold).monospacedDigit()
                }.font(.subheadline).frame(minHeight: 30).contentShape(Rectangle())
            }.accessibilityLabel("Rest between sets, \(clockText(Double(rest)))")
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }.buttonStyle(.plain)
    }
}

extension NumericEdit {
    /// Rest between an exercise's sets, on the m:ss keypad.
    static func rest(_ seconds: Int, context: String?, save: @escaping (Int) -> Bool) -> NumericEdit {
        NumericEdit(title: "Rest Between Sets", context: context, value: Double(seconds), step: 15, maximum: 86400, format: .duration, presets: restPresets) { save(Int($0 ?? 0)) }
    }
}

/// "Warm-up" or "Working sets" above a group of rows.
struct SetGroupLabel: View {
    let title: String
    let color: Color
    var body: some View { Text(title).font(.footnote.weight(.semibold)).foregroundStyle(color).padding(.leading, 2).padding(.vertical, 2) }
}

/// One tappable value in a set row.
struct SetValueCell: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    /// Shows the title above the value, for accessibility text sizes.
    var labeled = false
    var filled = true
    var dimmed = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if labeled { Text(title).font(.caption2).foregroundStyle(.secondary) }
                Text(value).font(labeled ? .title3.monospacedDigit() : .figure(17)).foregroundStyle(dimmed ? .secondary : .primary).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, minHeight: 44)
                .background(filled ? palette.field : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
    }
}

/// How a card adds each kind of set. The live workout and a saved day apply these to their own records.
struct SetAdder {
    let set: () -> Void
    let warmup: () -> Void
    /// A set of a built-in kind or a custom type; a custom type may count as a warm-up.
    let typed: (SetKind, UUID?) -> Void
    /// A drop or MYO chain with the exercise's setup.
    let technique: (Technique) -> Void
    func run(_ slot: QuickAdd, types: [CustomSetType]) {
        switch slot {
        case .drop: technique(.drop)
        case .myo: technique(.myo)
        case .warmup: warmup()
        case .working: set()
        case .failure: typed(.failure, nil)
        case .custom(let id): typed(types.first { $0.id == id }?.countsAs ?? .working, id)
        }
    }
}

/// Add Set and the two quick-add buttons under an exercise.
struct ExerciseActions: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let addTitle: String
    let quickAdds: Bool
    let adder: SetAdder
    let customize: (Technique) -> Void
    var identifier: String? = nil
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Button(action: adder.set) { Label(addTitle, systemImage: "plus") }.buttonStyle(FieldButtonStyle())
            if quickAdds {
                ForEach(0..<2, id: \.self) { index in
                    QuickAddButton(index: index, run: { adder.run($0, types: store.data.customSetTypes) }, customize: customize)
                        .frame(width: typeSize.isAccessibilitySize ? nil : 96)
                        .accessibilityIdentifier(identifier.map { index == 0 ? "\($0).addDrop" : "\($0).addMyo" } ?? "")
                }
            }
        }.padding(.top, 2)
    }
}
