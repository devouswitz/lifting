import SwiftUI
import LiftingCore

struct CategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let choices: [String]
    @Binding var selection: [String]
    var multiple = false
    var allowsEmpty = false
    @State private var search = ""
    @State private var creating = false
    @State private var name = ""
    private var matches: [String] { choices.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) } }
    private var resolvedName: String? { ExerciseCategory.resolve(name, choices: choices) }

    var body: some View {
        List {
            if allowsEmpty && !multiple { choice("None", value: "") }
            ForEach(matches, id: \.self) { choice($0, value: $0) }
            Button("Create Category", systemImage: "plus") { name = search; creating = true }
        }
        .navigationTitle(title).inlineTitle()
        .searchable(text: $search, prompt: "Search categories")
        .alert("Create Category", isPresented: $creating) {
            TextField("Category name", text: $name)
            Button("Create") { if let resolvedName { select(resolvedName, toggle: false) } }.disabled(resolvedName == nil)
            Button("Cancel", role: .cancel) {}
        }
    }
    private func choice(_ label: String, value: String) -> some View {
        let selected = value.isEmpty ? selection.isEmpty : selection.contains { ExerciseCategory.key($0) == ExerciseCategory.key(value) }
        return Button { select(value) } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func select(_ value: String, toggle: Bool = true) {
        if multiple {
            if let index = selection.firstIndex(where: { ExerciseCategory.key($0) == ExerciseCategory.key(value) }) { if toggle { selection.remove(at: index) } }
            else if selection.count < 50 { selection.append(value) }
        } else { selection = value.isEmpty ? [] : [value]; dismiss() }
    }
}
