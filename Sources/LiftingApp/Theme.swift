import SwiftUI
import LiftingCore

/// Resolved color roles for the current appearance. Each role means one thing everywhere;
/// values come from Settings > Colors, falling back to tuned Apple system colors.
struct Palette: Equatable {
    var colors = ColorTheme()
    var dark = false
    /// Custom set types, so badges and titles resolve wherever a set is drawn.
    var setTypes: [CustomSetType] = []
    func setType(_ plan: SetPlan) -> CustomSetType? { plan.customTypeID.flatMap { id in setTypes.first { $0.id == id } } }
    func title(_ plan: SetPlan) -> String { setType(plan).map(\.name) ?? plan.kind.title }
    /// Color for a set's badge: its custom type's color, else its built-in kind's role.
    func color(for plan: SetPlan) -> Color {
        if let type = setType(plan) { return type.color.flatMap(ColorTheme.parse).map { Color(hex: UInt($0)) } ?? technique }
        return kind(plan.kind)
    }
    func color(_ role: ColorRole) -> Color { Color(hex: UInt(colors.hex(role, dark: dark))) }
    var action: Color { color(.action) }
    var completed: Color { color(.completed) }
    var warmup: Color { color(.warmup) }
    var technique: Color { color(.technique) }
    var failure: Color { color(.failure) }
    var rest: Color { color(.rest) }
    var best: Color { color(.best) }
    var background: Color { color(.background) }
    var card: Color { color(.card) }
    var field: Color { color(.field) }
    /// Readable text on a filled role color.
    func on(_ role: ColorRole) -> Color {
        let hex = colors.hex(role, dark: dark)
        let r = Double((hex >> 16) & 255) / 255, g = Double((hex >> 8) & 255) / 255, b = Double(hex & 255) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6 ? .black : .white
    }
    func kind(_ kind: SetKind) -> Color {
        switch kind { case .warmup: return warmup; case .working: return .secondary; case .failure: return failure; default: return technique }
    }
    /// Soft fill behind content that belongs to a role, such as a completed set row.
    func wash(_ role: ColorRole) -> Color { color(role).opacity(dark ? 0.17 : 0.13) }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette() }
extension EnvironmentValues {
    var palette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}
extension Color { init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) } }

extension Font {
    /// Tabular figures for weights, reps, and times.
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight).monospacedDigit() }
}

/// Corner radius matching the system's inset-grouped lists, so cards and lists read as one family.
var cardRadius: CGFloat {
    if #available(iOS 26.0, macOS 26.0, *) { return 24 }
    return 12
}

struct CardStyle: ViewModifier {
    @Environment(\.palette) var palette
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content.padding(padding).background(palette.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }
}
extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(CardStyle(padding: padding)) }
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    /// Keeps the title for back menus and windows while the screen shows its own editable title.
    func titleInContent(_ title: String) -> some View {
        self.navigationTitle(title).inlineTitle()
            .contentMargins(.top, 0, for: .scrollContent)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
    }
    func sheetSize() -> some View { self.frame(idealWidth: 480, idealHeight: 700).presentationDetents([.large]) }
}

/// Grouped form that uses the Background and Cards color roles.
struct ThemedForm<Content: View>: View {
    @Environment(\.palette) var palette
    @ViewBuilder var content: Content
    var body: some View {
        Form {
            Group { content }.listRowBackground(palette.card)
                #if os(macOS)
                .buttonStyle(.borderless)
                #endif
        }
        .scrollContentBackground(.hidden).background(palette.background)
    }
}

/// Settings-style row label: a colored icon tile and a title.
struct TileLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        Label {
            // Color.primary, not .primary: inside a Button the hierarchical style resolves to the tint.
            Text(title).foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// An "Add ..." row inside the list it adds to, in the Action color.
struct AddRow: View {
    let title: String
    var symbol = "plus"
    let action: () -> Void
    @Environment(\.palette) var palette
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).foregroundStyle(palette.action) }
    }
}

extension View {
    /// The primary action style: prominent glass on iOS 26 and later, a filled button before that.
    @ViewBuilder func primaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }
    /// Floating glass capsule on iOS 26 and later, a material capsule before that.
    @ViewBuilder func floatingCapsule() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) { self.glassEffect(.regular, in: Capsule()) }
        else { self.background(.regularMaterial, in: Capsule()).overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)) }
    }
}

/// Heading above grouped content on scrolling screens, matching grouped-list section headers.
struct SectionTitle: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
        }.padding(.horizontal, 4).padding(.top, 8)
    }
}

/// Full-width secondary button on a field-colored background, used for Add Set and Add Exercise.
struct FieldButtonStyle: ButtonStyle {
    @Environment(\.palette) var palette
    @Environment(\.isEnabled) var enabled
    var role: ColorRole = .action
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(palette.color(role))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(palette.field, in: Capsule())
            .opacity(enabled ? configuration.isPressed ? 0.6 : 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Thin capsule progress track.
struct CapsuleProgress: View {
    let value: Double
    var role: ColorRole = .completed
    var height: CGFloat = 4
    @Environment(\.palette) var palette
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.field)
                Capsule().fill(palette.color(role)).frame(width: max(value > 0 ? height : 0, geo.size.width * min(1, max(0, value))))
            }
        }.frame(height: height).animation(.easeOut(duration: 0.25), value: value).accessibilityHidden(true)
    }
}

/// Small colored set badge: W1, 1, D1, A, M1, F, or a custom type's badge.
struct SetBadge: View {
    let text: String
    let plan: SetPlan
    @Environment(\.palette) var palette
    var body: some View {
        let plain = plan.kind == .working && plan.customTypeID == nil
        let color = palette.color(for: plan)
        Text(text).font(.footnote.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(plain ? Color.primary : color)
            .frame(minWidth: 26, minHeight: 22).padding(.horizontal, plain ? 0 : 3)
            .background(plain ? Color.clear : color.opacity(palette.dark ? 0.2 : 0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct Chip: View {
    let title: String
    var accent = false
    @Environment(\.palette) var palette
    var body: some View {
        Text(title).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(accent ? palette.action : .primary)
            .background(accent ? palette.wash(.action) : palette.field, in: Capsule())
    }
}

/// A capsule choice: filled in its role's wash and outlined when selected, plain on the card color otherwise.
struct ChipStyle: ButtonStyle {
    let selected: Bool
    var role: ColorRole = .action
    @Environment(\.palette) var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
            .foregroundStyle(selected ? palette.color(role) : Color.primary)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background(selected ? palette.wash(role) : palette.card, in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(palette.color(role), lineWidth: 1.5) } }
            .opacity(configuration.isPressed ? 0.6 : 1).contentShape(Capsule())
    }
}

/// Lays out children in rows, wrapping to a new row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, subview) in zip(arrange(width: bounds.width, subviews: subviews), subviews) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: min(size.width, width), height: size.height)))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String
    var body: some View { VStack(spacing: 12) { Image(systemName: symbol).font(.largeTitle); Text(text).font(.body) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 64) }
}

struct MetricTile: View {
    let value: String
    let label: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.figure(24)).lineLimit(1).minimumScaleFactor(0.7); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine) }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.palette) var palette
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.horizontal, 18).padding(.vertical, 14)
            .foregroundStyle(palette.on(.action))
            .background(palette.action.opacity(enabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1).opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SavedNameField: View {
    var name: String
    var onSave: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Name", text: $text).focused($focused)
            .onAppear { text = name }
            .onChange(of: text) { _, value in
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 200, value != name { onSave(value) }
            }
            .onChange(of: name) { _, value in if !focused { text = value } }
            .onChange(of: focused) { _, active in if !active { text = name } }
            .onSubmit { focused = false }
    }
}

/// A screen's name shown as its large title. Tap it to rename.
struct EditableTitle: View {
    var name: String
    var onSave: (String) -> Void
    var body: some View {
        Section {
            SavedNameField(name: name, onSave: onSave)
                .font(.largeTitle.bold()).submitLabel(.done)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .accessibilityLabel("Name").accessibilityIdentifier("title.name")
        }
    }
}

struct StoreErrorRow: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if let error = store.error {
            HStack(alignment: .top) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Dismiss") { store.error = nil }
            }
        }
    }
}

extension View {
    @ViewBuilder func compactMenu() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: true, vertical: false)
        #else
        self.menuIndicator(.hidden)
        #endif
    }
}
