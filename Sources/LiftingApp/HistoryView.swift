import SwiftUI
import LiftingCore

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var mode = HistoryMode.calendar
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date?
    private let calendar = Calendar.current

    private var sortedSessions: [Session] { store.data.sessions.sorted { $0.startedAt > $1.startedAt } }
    private var matchingSessions: [Session] {
        sortedSessions.filter { session in
            search.isEmpty || "\(store.data.title(for: session)) \(session.notes) \(session.exercises.map { "\($0.name) \($0.label) \($0.notes)" }.joined(separator: " "))".localizedCaseInsensitiveContains(search)
        }
    }
    private var visibleSessions: [Session] {
        guard mode == .calendar else { return matchingSessions }
        return matchingSessions.filter { session in
            if let selectedDay { return calendar.isDate(session.startedAt, inSameDayAs: selectedDay) }
            guard let interval = calendar.dateInterval(of: .month, for: month) else { return false }
            return session.startedAt >= interval.start && session.startedAt < interval.end
        }
    }
    private var months: [Date] {
        Array(Set(visibleSessions.compactMap { calendar.dateInterval(of: .month, for: $0.startedAt)?.start })).sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("History view", selection: $mode) {
                ForEach(HistoryMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
                .accessibilityIdentifier("history.mode")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if mode == .calendar {
                        HistoryCalendar(month: $month, selectedDay: $selectedDay, sessions: sortedSessions, unit: store.data.settings.unit)
                        calendarSessions
                    } else if matchingSessions.isEmpty {
                        EmptyState(symbol: "clock", text: store.data.sessions.isEmpty ? "No workouts logged." : "No matching workouts.")
                    } else {
                        ForEach(months, id: \.self) { month in
                            VStack(alignment: .leading, spacing: 10) {
                                let sessions = visibleSessions.filter { calendar.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
                                HStack(alignment: .firstTextBaseline) {
                                    Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                                    Spacer()
                                    Text(counted(sessions.count, "workout")).font(.caption).foregroundStyle(.secondary)
                                }
                                sessionList(sessions)
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Palette.background(scheme))
        .navigationTitle("History")
        .searchable(text: $search, prompt: "Search workouts")
    }

    private var calendarSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let selectedDay { Text(selectedDay, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.headline) }
                else { Text("Workouts").font(.headline) }
                Spacer()
                if selectedDay != nil { Button("All days") { selectedDay = nil }.font(.subheadline).accessibilityIdentifier("history.allDays") }
                else { Text("\(visibleSessions.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
            }
            if visibleSessions.isEmpty { Text(search.isEmpty ? "No workouts this month." : "No matching workouts.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20) }
            else { sessionList(visibleSessions) }
        }
    }

    private func sessionList(_ sessions: [Session]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                NavigationLink { SessionDetail(sessionID: session.id) } label: {
                    HistoryWorkoutRow(session: session, title: store.data.title(for: session), unit: store.data.settings.unit)
                }.buttonStyle(.plain).accessibilityIdentifier("history.workout.\(session.id)")
                if index < sessions.count - 1 { Divider().padding(.leading, 58) }
            }
        }.background(Palette.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum HistoryMode: String, CaseIterable, Identifiable {
    case log = "Log", calendar = "Calendar"
    var id: String { rawValue }
}

private struct HistoryWorkoutRow: View {
    let session: Session
    let title: String
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text(session.startedAt, format: .dateTime.day()).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(session.startedAt, format: .dateTime.weekday(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
                }.frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text("\(counted(session.completedSets, "set")) · \(clockText(max(0, (session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt)))) · \(number(unit.display(session.volume), decimals: 0)) \(unit.rawValue)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(session.exercises.filter { $0.sets.contains { $0.completedAt != nil } }) { exercise in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).font(.subheadline.weight(.medium))
                            if !exercise.label.isEmpty && exercise.label != session.name && !exercise.label.hasSuffix(" · \(session.name)") { Text(exercise.label).font(.caption2).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(loggedExerciseSummary(exercise, unit: unit))
                            .font(.caption).monospacedDigit().multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !session.notes.isEmpty { Label(session.notes, systemImage: "note.text").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }.padding(.leading, 42)
        }.padding(16).contentShape(Rectangle())
    }
}


struct SessionDetail: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let sessionID: UUID
    @State private var deleting = false
    @State private var editing = false
    private var session: Session? { store.data.sessions.first { $0.id == sessionID } }

    private func update(_ change: (inout Session) -> Void) {
        store.perform { data in
            if let index = data.sessions.firstIndex(where: { $0.id == sessionID }) { change(&data.sessions[index]) }
        }
    }

    var body: some View {
        Group {
            if let session {
                if editing { editForm(session) }
                else { workoutDetail(session) }
            } else { EmptyState(symbol: "clock", text: "Workout unavailable.") }
        }
        .navigationTitle(session.map { store.data.title(for: $0) } ?? "Workout").inlineTitle()
        .toolbar { if session != nil { Button(editing ? "Done" : "Edit") { editing.toggle() }.accessibilityIdentifier("history.edit") } }
        .confirmationDialog("Delete this workout?", isPresented: $deleting) {
            Button("Delete workout", role: .destructive) {
                store.perform { $0.sessions.removeAll { $0.id == sessionID } }
                dismiss()
            }
        }
    }

    private func workoutDetail(_ session: Session) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year()).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        detailMetric("Sets", value: "\(session.completedSets)")
                        detailMetric("Duration", value: clockText(max(0, (session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt))))
                        detailMetric("Volume (\(store.data.settings.unit.rawValue))", value: number(store.data.settings.unit.display(session.volume), decimals: 0))
                    }
                    if !session.notes.isEmpty { Text(session.notes).font(.subheadline).textSelection(.enabled) }
                }.padding(16).background(Palette.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
                ForEach(session.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 13) {
                        NavigationLink { ExerciseProgress(exerciseID: exercise.exerciseID, initialVariantID: exercise.variantID, programID: session.programID) } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name).font(.headline)
                                    if !exercise.label.isEmpty { Text(exercise.label).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chart.xyaxis.line").font(.subheadline).foregroundStyle(Palette.tint(scheme))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if let from = exercise.substitutedFrom { Text("Substitute for \(from)").font(.caption).foregroundStyle(.secondary) }
                        HistorySetTable(sets: exercise.sets, unit: store.data.settings.unit)
                        if !exercise.recurringNotes.isEmpty { Label(exercise.recurringNotes, systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                        if !exercise.notes.isEmpty { Text(exercise.notes).font(.subheadline).textSelection(.enabled) }
                    }.padding(16).background(Palette.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
                }
                Button("Delete workout", role: .destructive) { deleting = true }.font(.subheadline).padding(.horizontal, 4)
            }.padding(16)
        }.background(Palette.background(scheme))
    }

    private func detailMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editForm(_ session: Session) -> some View {
        Form {
            Section {
                DatePicker("Date", selection: Binding(get: { self.session?.startedAt ?? .now }, set: { date in
                    update { value in
                        let duration = (value.endedAt ?? value.startedAt).timeIntervalSince(value.startedAt)
                        value.startedAt = date
                        value.endedAt = date.addingTimeInterval(duration)
                    }
                }))
                TextField("Name", text: Binding(get: { self.session?.name ?? "" }, set: { value in update { $0.name = value } }))
                TextField("Workout note", text: Binding(get: { self.session?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
            }
            ForEach(session.exercises) { exercise in
                Section {
                    ForEach(exercise.sets) { set in
                        NavigationLink {
                            LoggedSetEditor(set: Binding(get: { self.session?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == set.id } ?? set }, set: { newSet in
                                update { value in
                                    if let exerciseIndex = value.exercises.firstIndex(where: { $0.id == exercise.id }),
                                       let setIndex = value.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) {
                                        value.exercises[exerciseIndex].sets[setIndex] = newSet
                                    }
                                }
                            }), unit: store.data.settings.unit)
                        } label: { setRow(set) }
                    }
                    TextField("Note for this exercise", text: Binding(get: { self.session?.exercises.first { $0.id == exercise.id }?.notes ?? "" }, set: { value in
                        update { session in
                            if let index = session.exercises.firstIndex(where: { $0.id == exercise.id }) { session.exercises[index].notes = value }
                        }
                    }), axis: .vertical)
                } header: {
                    HStack { Text(exercise.name); Spacer(); Text(exercise.label).textCase(nil) }
                } footer: {
                    if !exercise.recurringNotes.isEmpty { Text(exercise.recurringNotes) }
                }
            }
            Section { Button("Delete workout", role: .destructive) { deleting = true } }
        }.formStyle(.grouped)
    }

    private func setRow(_ set: LoggedSet) -> some View {
        HStack(alignment: .top) {
            Image(systemName: set.completedAt == nil ? "minus.circle" : "checkmark.circle.fill")
                .foregroundStyle(set.completedAt == nil ? Color.secondary : Palette.tint(scheme))
            VStack(alignment: .leading, spacing: 4) {
                Text(loggedSetSummary(set, unit: store.data.settings.unit)).monospacedDigit()
                if set.plan.kind != .working { Text(set.plan.kind.title).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct HistorySetTable: View {
    @Environment(\.colorScheme) private var scheme
    let sets: [LoggedSet]
    let unit: WeightUnit
    private var columns: [HistorySetColumn] { HistorySetColumn.allCases.filter { column in sets.contains { column.value($0, unit: unit) != nil } } }

    var body: some View {
        if columns.count > 3 {
            ScrollView(.horizontal, showsIndicators: true) { table.frame(minWidth: CGFloat(76 + columns.count * 66)) }
        } else { table }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns) { column in Text(column.title(unit: unit)).frame(maxWidth: .infinity, alignment: .trailing) }
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            Divider()
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: set.completedAt == nil ? "minus" : "checkmark").font(.caption2.weight(.semibold))
                                .foregroundStyle(set.completedAt == nil ? Color.secondary : Palette.tint(scheme))
                            Text("\(index + 1)")
                        }
                        if set.plan.kind != .working { Text(set.plan.kind.title).font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns) { column in Text(column.value(set, unit: unit) ?? "-").frame(maxWidth: .infinity, alignment: .trailing) }
                }.font(.subheadline).monospacedDigit().padding(.vertical, 9).opacity(set.completedAt == nil ? 0.5 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Set \(index + 1), \(set.plan.kind.title), \(set.completedAt == nil ? "not completed" : "completed"), \(loggedSetSummary(set, unit: unit))")
                if index < sets.count - 1 { Divider().opacity(0.5) }
            }
        }
    }
}

private enum HistorySetColumn: CaseIterable, Identifiable, Hashable {
    case weight, reps, time, distance, rpe
    var id: Self { self }
    func title(unit: WeightUnit) -> String {
        switch self {
        case .weight: return unit.rawValue
        case .reps: return "Reps"
        case .time: return "Time"
        case .distance: return "Meters"
        case .rpe: return "RPE"
        }
    }
    func value(_ set: LoggedSet, unit: WeightUnit) -> String? {
        switch self {
        case .weight: return set.weight.map { number(unit.display($0)) }
        case .reps: return set.reps.map(String.init) ?? (set.plan.repRange != nil ? set.plan.repTarget : nil)
        case .time: return set.seconds.map(clockText)
        case .distance: return set.meters.map { number($0) }
        case .rpe: return set.rpe.map { number($0) }
        }
    }
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
