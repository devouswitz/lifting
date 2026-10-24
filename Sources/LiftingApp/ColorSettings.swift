import SwiftUI
import LiftingCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ColorSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @State private var dark = false
    @State private var theme = ColorTheme()
    @State private var loaded = false
    @State private var resetting = false
    private var palette: Palette { Palette(colors: theme, dark: dark, setTypes: store.data.customSetTypes) }

    var body: some View {
        ThemedForm {
            Section {
                Picker("Appearance", selection: $dark) { Text("Light").tag(false); Text("Dark").tag(true) }
                    .pickerStyle(.segmented).labelsHidden()
            }
            Section {
                ColorPreview().environment(\.palette, palette).environment(\.colorScheme, dark ? .dark : .light)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("Meaning") { ForEach(ColorRole.allCases.filter { !$0.isNeutral }) { row($0) } }
            Section("Surfaces") { ForEach(ColorRole.allCases.filter(\.isNeutral)) { row($0) } }
            Section {
                Button("Reset \(dark ? "Dark" : "Light") Colors") { theme.light = dark ? theme.light : [:]; theme.dark = dark ? [:] : theme.dark }
                    .disabled((dark ? theme.dark : theme.light).isEmpty)
                Button("Reset All Colors", role: .destructive) { resetting = true }.disabled(theme == ColorTheme())
            }
        }.formStyle(.grouped).navigationTitle("Colors").inlineTitle()
        .onAppear {
            guard !loaded else { return }
            loaded = true; dark = scheme == .dark; theme = store.data.settings.colors ?? ColorTheme()
        }
        .task(id: theme) {
            // Coalesce rapid picker changes into one save.
            guard loaded, theme != (store.data.settings.colors ?? ColorTheme()) else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            store.perform { $0.settings.colors = theme == ColorTheme() ? nil : theme }
        }
        .onDisappear { if loaded, theme != (store.data.settings.colors ?? ColorTheme()) { store.perform { $0.settings.colors = theme == ColorTheme() ? nil : theme } } }
        .confirmationDialog("Reset all colors to the defaults?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset All Colors", role: .destructive) { theme = ColorTheme() }
        }
    }

    private func row(_ role: ColorRole) -> some View {
        HStack(spacing: 12) {
            ColorPicker(selection: binding(role), supportsOpacity: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.title)
                    Text(role.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            if theme.isCustomized(role, dark: dark) {
                Button { theme.set(role, dark: dark, hex: nil) } label: { Image(systemName: "arrow.uturn.backward.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Reset \(role.title)")
            }
        }
    }

    private func binding(_ role: ColorRole) -> Binding<Color> {
        Binding(get: { palette.color(role) }, set: { color in if let hex = color.hexValue { theme.set(role, dark: dark, hex: hex) } })
    }
}

/// A small slice of the workout screen drawn with the palette being edited.
private struct ColorPreview: View {
    @Environment(\.palette) var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bench press").font(.headline)
                Label("Superset", systemImage: "link").font(.footnote.weight(.medium)).foregroundStyle(palette.technique)
                Spacer()
                Label("3:00", systemImage: "timer").font(.subheadline.weight(.medium)).foregroundStyle(palette.rest)
            }
            row("W1", .warmup, "47.5", "5", done: true)
            row("1", .working, "95", "5", done: true)
            row("2", .working, "95", "5", done: false)
            row("D1", .drop, "75", "8", done: false)
            row("F", .failure, "95", "3", done: false)
            HStack(spacing: 8) {
                Label("Best 105 lb", systemImage: "star.fill").font(.subheadline.weight(.medium)).foregroundStyle(palette.best)
                Spacer()
                Text("Start Workout").font(.subheadline.weight(.semibold)).foregroundStyle(palette.on(.action))
                    .padding(.horizontal, 14).padding(.vertical, 8).background(palette.action, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .foregroundStyle(.primary)
        .padding(14).background(palette.card, in: RoundedRectangle(cornerRadius: cardRadius - 8, style: .continuous))
        .padding(10).background(palette.background, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore).accessibilityLabel("Color preview")
    }
    private func row(_ badge: String, _ kind: SetKind, _ weight: String, _ reps: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            SetBadge(text: badge, plan: SetPlan(kind: kind)).frame(width: 32)
            cell(weight, done: done); cell(reps, done: done)
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                .foregroundStyle(done ? palette.on(.completed) : Color.secondary.opacity(0.5))
                .frame(width: 30, height: 30).background(done ? palette.completed : palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.padding(3).background(done ? palette.wash(.completed) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
    private func cell(_ value: String, done: Bool) -> some View {
        Text(value).font(.figure(16)).frame(maxWidth: .infinity, minHeight: 32)
            .background(done ? Color.clear : palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Small row of the main role colors, shown next to the Colors setting.
struct ColorSwatches: View {
    @Environment(\.palette) var palette
    var body: some View {
        HStack(spacing: 4) {
            ForEach([ColorRole.action, .completed, .warmup, .technique, .failure, .rest], id: \.self) { role in
                Circle().fill(palette.color(role)).frame(width: 12, height: 12)
            }
        }.accessibilityHidden(true)
    }
}

extension Color {
    /// sRGB hex value of this color, used to store picker choices.
    var hexValue: UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(iOS)
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #else
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
