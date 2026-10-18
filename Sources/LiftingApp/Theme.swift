import SwiftUI

enum Palette {
    static let accent = Color(red: 0.118, green: 0.435, blue: 0.361)
    static let darkAccent = Color(red: 0.298, green: 0.788, blue: 0.651)
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x0D0D0F) : Color(hex: 0xF4F5F7) }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x19191C) : .white }
    static func secondary(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x242427) : Color(hex: 0xECEEF1) }
    static func tint(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkAccent : accent }
}
extension Color { init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) } }

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme
    func body(content: Content) -> some View {
        content.padding(12).background(Palette.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
    }
}
extension View {
    func card() -> some View { modifier(CardStyle()) }
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    func sheetSize() -> some View { self.frame(idealWidth: 480, idealHeight: 700).presentationDetents([.large]) }
}

struct Chip: View {
    let title: String
    @Environment(\.colorScheme) var scheme
    var body: some View { Text(title).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(Palette.secondary(scheme), in: Capsule()) }
}

struct EmptyState: View {
    let symbol: String
    let text: String
    var body: some View { VStack(spacing: 12) { Image(systemName: symbol).font(.largeTitle); Text(text).font(.body) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 64) }
}

struct MetricTile: View {
    let value: String
    let label: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.title2.weight(.semibold)).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?
    var factor: Double = 1
    var integer: Bool = false
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(title, text: $text)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { sync() }
            .onChange(of: value) { _, _ in if !focused { sync() } }
            .onChange(of: text) { _, new in
                if new.isEmpty { value = nil }
                else if let parsed = Double(new.replacingOccurrences(of: ",", with: ".")), parsed.isFinite, parsed >= 0, parsed * factor <= 10_000_000, !integer || parsed.rounded() == parsed { value = parsed * factor }
            }
            .onChange(of: focused) { _, active in if !active { sync() } }
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
    func sync() { text = value.map { number($0 / factor, decimals: 3) } ?? "" }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var scheme
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.semibold).padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(scheme == .dark ? Color(hex: 0x0B1F1A) : .white)
            .background(Palette.tint(scheme).opacity(enabled ? configuration.isPressed ? 0.75 : 1 : 0.35), in: RoundedRectangle(cornerRadius: 10))
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
        self.menuStyle(.borderlessButton).menuIndicator(.hidden)
        #else
        self.menuIndicator(.hidden)
        #endif
    }
}
