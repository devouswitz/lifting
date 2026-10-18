import SwiftUI
import LiftingCore

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    var sessions: [Session] { store.data.sessions.reversed().filter { search.isEmpty || "\($0.name) \($0.notes) \($0.exercises.map(\.name).joined(separator: " "))".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if store.data.sessions.isEmpty { EmptyState(symbol: "calendar", text: "No workouts logged.").listRowSeparator(.hidden) }
            ForEach(sessions) { session in
                NavigationLink { SessionDetail(sessionID: session.id) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(session.name).font(.headline); Spacer(); Text(session.startedAt, format: .dateTime.month(.abbreviated).day()).font(.subheadline).foregroundStyle(.secondary) }
                        Text("\(session.completedSets) sets · \(clockText((session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt))) · \(number(store.data.settings.unit.display(session.volume), decimals: 0)) \(store.data.settings.unit.rawValue)").font(.subheadline).foregroundStyle(.secondary)
                        if !session.notes.isEmpty { Label(session.notes, systemImage: "note.text").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }.padding(.vertical, 7)
                }
            }
        }.navigationTitle("History").searchable(text: $search, prompt: "Search workouts")
    }
}

struct SessionDetail: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let sessionID: UUID
    @State private var deleting = false
    @State private var editing = false
    var session: Session? { store.data.sessions.first { $0.id == sessionID } }
    func update(_ change: (inout Session) -> Void) { store.perform { d in if let i = d.sessions.firstIndex(where: { $0.id == sessionID }) { change(&d.sessions[i]) } } }
    var body: some View {
        Form {
            if let session {
                Section {
                    Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    HStack { MetricTile(value: "\(session.completedSets)", label: "Sets"); MetricTile(value: clockText((session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt)), label: "Duration") }
                    if editing {
                        DatePicker("Date", selection: Binding(get: { self.session?.startedAt ?? .now }, set: { date in update { s in let duration = (s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt); s.startedAt = date; s.endedAt = date.addingTimeInterval(duration) } }))
                        TextField("Name", text: Binding(get: { self.session?.name ?? "" }, set: { value in update { $0.name = value } }))
                    }
                    TextField("Workout note", text: Binding(get: { self.session?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
                }
                ForEach(session.exercises) { exercise in
                    Section {
                        HStack { Text(exercise.name).font(.headline); Spacer(); Chip(title: exercise.label) }
                        if let from = exercise.substitutedFrom { Text("Substitute for \(from)").font(.caption).foregroundStyle(.secondary) }
                        if !exercise.recurringNotes.isEmpty { Label(exercise.recurringNotes, systemImage: "pin.fill").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(exercise.sets) { set in
                            if editing {
                                NavigationLink {
                                    LoggedSetEditor(set: Binding(get: { self.session?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == set.id } ?? set }, set: { newSet in update { s in if let e = s.exercises.firstIndex(where: { $0.id == exercise.id }), let i = s.exercises[e].sets.firstIndex(where: { $0.id == set.id }) { s.exercises[e].sets[i] = newSet } } }), unit: store.data.settings.unit)
                                } label: { setRow(set) }
                            } else { setRow(set) }
                        }
                        TextField("Note for this exercise", text: Binding(get: { self.session?.exercises.first { $0.id == exercise.id }?.notes ?? "" }, set: { value in update { s in if let e = s.exercises.firstIndex(where: { $0.id == exercise.id }) { s.exercises[e].notes = value } } }), axis: .vertical)
                    }
                }
                Section { Button("Delete workout", role: .destructive) { deleting = true } }
            }
        }.formStyle(.grouped).navigationTitle(session?.name ?? "Workout").inlineTitle()
        .toolbar { Button(editing ? "Done" : "Edit") { editing.toggle() } }
        .confirmationDialog("Delete this workout?", isPresented: $deleting) { Button("Delete workout", role: .destructive) { store.perform { $0.sessions.removeAll { $0.id == sessionID } }; dismiss() } }
    }
    func setRow(_ set: LoggedSet) -> some View { HStack(alignment: .top) { Image(systemName: set.completedAt == nil ? "minus.circle" : "checkmark.circle.fill").foregroundStyle(set.completedAt == nil ? Color.secondary : Palette.accent); VStack(alignment: .leading, spacing: 4) { Text(loggedSetSummary(set, unit: store.data.settings.unit)).monospacedDigit(); if set.plan.kind != .working { Text(set.plan.kind.title).font(.caption).foregroundStyle(.secondary) } } } }
}

struct LoggedSetEditor: View {
    @Binding var set: LoggedSet
    let unit: WeightUnit
    var body: some View {
        Form {
            Picker("Type", selection: $set.plan.kind) { ForEach(SetKind.allCases) { Text($0.title).tag($0) } }
            Toggle("Completed", isOn: Binding(get: { set.completedAt != nil }, set: { set.completedAt = $0 ? .now : nil }))
            HStack { Text("Weight (\(unit.rawValue))"); OptionalNumberField(title: "Optional", value: $set.weight, factor: unit.kilograms(1)) }
            HStack { Text("Reps"); OptionalNumberField(title: "Optional", value: Binding(get: { set.reps.map(Double.init) }, set: { set.reps = $0.map(Int.init) }), integer: true) }
            HStack { Text("Time (minutes)"); OptionalNumberField(title: "Optional", value: $set.seconds, factor: 60) }
            HStack { Text("Distance (meters)"); OptionalNumberField(title: "Optional", value: $set.meters) }
            HStack { Text("RPE"); OptionalNumberField(title: "Optional", value: $set.rpe) }
        }.formStyle(.grouped).navigationTitle("Edit set").inlineTitle()
    }
}
