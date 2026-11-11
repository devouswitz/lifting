import SwiftUI
import LiftingCore

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
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
    private var months: [Date] {
        Array(Set(matchingSessions.compactMap { calendar.dateInterval(of: .month, for: $0.startedAt)?.start })).sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("History view", selection: $mode) {
                ForEach(HistoryMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14).readableWidth()
                .accessibilityIdentifier("history.mode")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if mode == .calendar {
                        HistoryCalendar(month: $month, selectedDay: $selectedDay, sessions: sortedSessions, unit: store.data.settings.unit)
                        if let selectedDay { daySessions(selectedDay) }
                    } else if matchingSessions.isEmpty {
                        EmptyState(symbol: "clock", text: store.data.sessions.isEmpty ? "No workouts logged." : "No matching workouts.")
                    } else {
                        ForEach(months, id: \.self) { month in
                            VStack(alignment: .leading, spacing: 10) {
                                let sessions = matchingSessions.filter { calendar.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
                                HStack(alignment: .firstTextBaseline) {
                                    Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                                    Spacer()
                                    Text(counted(sessions.filter { $0.skipped != true }.count, "workout")).font(.caption).foregroundStyle(.secondary)
                                }
                                sessionList(sessions)
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 24).readableWidth()
            }
        }
        .background(palette.background)
        .navigationTitle("History")
        .searchable(text: $search, prompt: "Search workouts")
        // Search results are a list, so searching shows the log.
        .onChange(of: search) { _, value in if !value.isEmpty { mode = .log } }
    }

    /// The workouts on the day tapped in the calendar.
    private func daySessions(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.headline)
            sessionList(sortedSessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) })
        }
    }

    private func sessionList(_ sessions: [Session]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                NavigationLink { SessionDetail(sessionID: session.id) } label: {
                    HistoryWorkoutRow(session: session, title: store.data.title(for: session), settings: store.data.settings)
                }.buttonStyle(.plain).accessibilityIdentifier("history.workout.\(session.id)")
                if index < sessions.count - 1 { Divider().padding(.leading, 58) }
            }
        }.card(padding: 0)
    }
}

private enum HistoryMode: String, CaseIterable, Identifiable {
    case log = "Log", calendar = "Calendar"
    var id: String { rawValue }
}

/// One logged workout in the list: date, title, and totals. Exercises and sets are on its own screen.
private struct HistoryWorkoutRow: View {
    let session: Session
    let title: String
    let settings: LiftingCore.Settings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(session.startedAt, format: .dateTime.day()).font(.title3.weight(.semibold)).monospacedDigit()
                Text(session.startedAt, format: .dateTime.weekday(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(session.skipped == true ? .secondary : .primary)
                if session.skipped == true { Text("Skipped").font(.caption).foregroundStyle(.secondary) }
                else {
                    let total = WorkTotal(session, settings: settings)
                    let exercises = session.exercises.filter { $0.sets.contains { $0.completedAt != nil } }.count
                    Text([counted(exercises, "exercise"), counted(session.completedSets, "set"), clockText(session.duration()), total.empty ? nil : total.value, total.note, session.health?.activeKcal.map { "\(grouped($0)) kcal" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    let changes = session.planChanges, changed = changes.added.count + changes.swapped.count + changes.removed.count
                    if changed > 0 { Label("\(counted(changed, "change")) from the plan", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary) }
                    if !session.notes.isEmpty { Label(session.notes, systemImage: "note.text").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 5)
        }.padding(16).contentShape(Rectangle())
    }
}


struct SessionDetail: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
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
        .toolbar { if session != nil { Button(editing ? "Done" : "Edit") { editing.toggle() }.fontWeight(editing ? .semibold : .regular).accessibilityIdentifier("history.edit") } }
        .alert("Delete this workout?", isPresented: $deleting) {
            Button("Delete Workout", role: .destructive) {
                store.deleteSession(sessionID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Lifts whose heaviest set in this workout beat every earlier one (more reps break a tie).
    private func records(in session: Session) -> Set<UUID> {
        Set(Set(session.exercises.filter { $0.mode == .strength }.map(\.exerciseID)).filter { id in
            let tops = store.data.topSets(exerciseID: id)
            guard let index = tops.firstIndex(where: { $0.sessionID == session.id }), index > 0 else { return false }
            return tops[..<index].allSatisfy { $0.weight < tops[index].weight || ($0.weight == tops[index].weight && $0.reps < tops[index].reps) }
        })
    }

    private func workoutDetail(_ session: Session) -> some View {
        let records = records(in: session)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year()).font(.subheadline).foregroundStyle(.secondary)
                    if session.skipped == true {
                        Label("Skipped", systemImage: "forward").font(.headline).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 16) {
                            detailMetric("Sets", value: "\(session.completedSets)")
                            detailMetric("Duration", value: clockText(session.duration()))
                            let total = WorkTotal(session, settings: store.data.settings)
                            detailMetric(total.caption, value: total.value)
                        }
                        if let health = session.health, health.hasData {
                            VStack(alignment: .leading, spacing: 6) {
                                Label { Text(healthSummary(health)).foregroundStyle(.secondary) } icon: { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                                // Each Apple Health workout that counted, when there was more than one.
                                if let parts = health.parts, parts.count > 1 {
                                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                                        HStack {
                                            Text(part.activityName)
                                            Spacer()
                                            Text([clockText(part.duration), part.activeKcal.map { "\(number($0, decimals: 0)) kcal" }].compactMap { $0 }.joined(separator: " · ")).monospacedDigit()
                                        }.foregroundStyle(.secondary).padding(.leading, 28)
                                    }
                                }
                            }.font(.subheadline).accessibilityElement(children: .combine).accessibilityIdentifier("history.health")
                        }
                    }
                    planChanges(session)
                    if !session.notes.isEmpty { Text(session.notes).font(.subheadline).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 16)
                ForEach(session.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 13) {
                        NavigationLink { ExerciseProgress(exerciseID: exercise.exerciseID, initialVariantID: exercise.variantID, programID: session.programID) } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name).font(.headline)
                                    if !exercise.label.isEmpty && exercise.label != session.name && exercise.label != store.data.title(for: session).replacingOccurrences(of: " - ", with: " · ") && !exercise.label.hasSuffix(" · \(session.name)") { Text(exercise.label).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if records.contains(exercise.exerciseID) {
                                    Label("Record", systemImage: "star.fill").labelStyle(TightLabelStyle()).font(.caption.weight(.medium)).foregroundStyle(palette.best)
                                }
                                Image(systemName: "chart.xyaxis.line").font(.subheadline).foregroundStyle(palette.action)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if let from = exercise.substitutedFrom { Label("Instead of \(from)", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary) }
                        else if exercise.slotID == nil, session.routineID != nil { Label("Added to this workout", systemImage: "plus").font(.caption).foregroundStyle(.secondary) }
                        HistorySetTable(sets: exercise.sets, mode: exercise.mode, unit: store.data.settings.unit)
                        if !exercise.recurringNotes.isEmpty { Label(exercise.recurringNotes, systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                        if !exercise.notes.isEmpty { Text(exercise.notes).font(.subheadline).textSelection(.enabled) }
                    }.card(padding: 16)
                }
                Button("Delete Workout", role: .destructive) { deleting = true }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
            }.padding(16).readableWidth()
        }.background(palette.background)
    }

    /// How the workout departed from its day: what was added, swapped, and taken out.
    @ViewBuilder private func planChanges(_ session: Session) -> some View {
        let changes = session.planChanges
        let lines: [(symbol: String, text: String)] = [
            changes.added.isEmpty ? nil : ("plus", "Added \(changes.added.formatted(.list(type: .and)))"),
            changes.swapped.isEmpty ? nil : ("arrow.triangle.2.circlepath", "Swapped \(changes.swapped.map { "\($0.from) for \($0.name)" }.formatted(.list(type: .and)))"),
            changes.removed.isEmpty ? nil : ("minus", "Left out \(changes.removed.formatted(.list(type: .and)))"),
        ].compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Changes from the plan").font(.caption).foregroundStyle(.secondary)
                ForEach(lines, id: \.text) { line in Label(line.text, systemImage: line.symbol).font(.subheadline) }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("history.changes")
        }
    }

    /// For example "412 kcal · 128 bpm average · Apple Watch".
    private func healthSummary(_ health: HealthLink) -> String {
        [health.activeKcal.map { "\(number($0, decimals: 0)) kcal" }, health.averageHeartRate.map { "\(number($0, decimals: 0)) bpm average" }, health.sourceName.isEmpty ? nil : health.sourceName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func detailMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editForm(_ session: Session) -> some View {
        ThemedForm {
            Section {
                DatePicker("Date", selection: Binding(get: { self.session?.startedAt ?? .now }, set: { date in
                    update { $0.changeStart(to: date) }
                }))
                SavedNameField(name: session.name) { value in update { $0.name = value } }
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
                            }), unit: store.data.settings.unit, completedAt: session.endedAt ?? session.startedAt)
                        } label: { setRow(set, mode: exercise.mode) }
                    }.onDelete { offsets in
                        let ids = offsets.map { exercise.sets[$0].id }
                        update { value in if let index = value.exercises.firstIndex(where: { $0.id == exercise.id }) { value.exercises[index].sets.removeAll { ids.contains($0.id) } } }
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
            if let health = session.health {
                Section {
                    if health.unlinked == true {
                        Button("Match with Apple Health Again") { store.perform { $0.relinkHealth(sessionID) }; Task { await store.refreshHealth() } }
                    } else if health.hasData {
                        Button("Remove Apple Health Match", role: .destructive) { store.perform { $0.unlinkHealth(sessionID) } }
                    }
                } footer: { if health.hasData, health.unlinked != true { Text(healthSummary(health)) } }
            }
            Section { Button("Delete Workout", role: .destructive) { deleting = true } }
        }.formStyle(.grouped)
    }

    private func setRow(_ set: LoggedSet, mode: ExerciseMode) -> some View {
        HStack(alignment: .top) {
            Image(systemName: set.completedAt == nil ? "minus.circle" : "checkmark.circle.fill")
                .foregroundStyle(set.completedAt == nil ? Color.secondary : palette.completed)
            VStack(alignment: .leading, spacing: 4) {
                Text(loggedSetSummary(set, mode: mode, unit: store.data.settings.unit)).monospacedDigit()
                if set.plan.kind != .working || set.plan.customTypeID != nil { Text(palette.title(set.plan)).font(.caption).foregroundStyle(palette.color(for: set.plan)) }
            }
        }
    }
}

private struct HistorySetTable: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    let sets: [LoggedSet]
    let mode: ExerciseMode
    let unit: WeightUnit
    private var columns: [HistorySetColumn] { HistorySetColumn.allCases.filter { column in sets.contains { column.value($0, mode: mode, unit: unit) != nil } } }

    var body: some View {
        if columns.count > 3 {
            ScrollView(.horizontal, showsIndicators: true) { table.frame(minWidth: CGFloat(76 + columns.count * 66)) }
        } else { table }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns) { column in Text(column.title(mode: mode, unit: unit)).frame(maxWidth: .infinity, alignment: .trailing) }
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            Divider()
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: set.completedAt == nil ? "minus" : "checkmark").font(.caption2.weight(.semibold))
                            .foregroundStyle(set.completedAt == nil ? Color.secondary : palette.completed)
                        SetBadge(text: setBadge(sets.map(\.plan), index: index, types: palette.setTypes), plan: set.plan)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns) { column in Text(column.value(set, mode: mode, unit: unit) ?? "-").frame(maxWidth: .infinity, alignment: .trailing) }
                }.font(.subheadline).monospacedDigit().padding(.vertical, 6).opacity(set.completedAt == nil ? 0.5 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(palette.title(set.plan)) set \(setBadge(sets.map(\.plan), index: index, types: palette.setTypes)), \(set.completedAt == nil ? "not completed" : "completed"), \(loggedSetSummary(set, mode: mode, unit: unit))")
                if index < sets.count - 1 { Divider().opacity(0.5) }
            }
        }
    }
}

private enum HistorySetColumn: CaseIterable, Identifiable, Hashable {
    case weight, reps, time, distance, rpe
    var id: Self { self }
    func title(mode: ExerciseMode, unit: WeightUnit) -> String {
        switch self {
        case .weight: return mode == .bodyweight ? "+\(unit.rawValue)" : unit.rawValue
        case .reps: return "Reps"
        case .time: return "Time"
        case .distance: return DistanceDisplay.unit.rawValue
        case .rpe: return "RPE"
        }
    }
    func value(_ set: LoggedSet, mode: ExerciseMode, unit: WeightUnit) -> String? {
        switch self {
        case .weight: return set.weight == nil && mode == .bodyweight ? nil : loadText(set.weight, mode: mode, unit: unit)
        case .reps: return set.reps.map(String.init) ?? (set.plan.repRange != nil || set.plan.amrap ? set.plan.repTarget.map(displayTarget) : nil)
        case .time: return set.seconds.map(clockText)
        case .distance: return set.meters.map { number(DistanceDisplay.value($0), decimals: 2) }
        case .rpe: return set.rpe.map { number($0) }
        }
    }
}

struct LoggedSetEditor: View {
    @Environment(\.palette) private var palette
    @Binding var set: LoggedSet
    let unit: WeightUnit
    /// The time a set takes when it is marked complete here: the workout's, not now.
    let completedAt: Date
    var body: some View {
        ThemedForm {
            Picker("Type", selection: setTypeChoice($set.plan, types: palette.setTypes)) {
                ForEach(SetKind.allCases) { Text($0.title).tag(SetTypeChoice.kind($0)) }
                ForEach(palette.setTypes) { Text($0.name).tag(SetTypeChoice.custom($0.id)) }
            }
            Toggle("Completed", isOn: Binding(get: { set.completedAt != nil }, set: { set.completedAt = $0 ? completedAt : nil }))
            NumberRow("Weight (\(unit.rawValue))", value: $set.weight, factor: unit.kilograms(1))
            NumberRow("Reps", value: Binding(get: { set.reps.map(Double.init) }, set: { set.reps = $0.map(Int.init) }), integer: true)
            DurationRow(title: "Time", seconds: $set.seconds)
            NumberRow("Distance (\(DistanceDisplay.unit.rawValue))", value: $set.meters, factor: DistanceDisplay.unit.meters)
            NumberRow("RPE", value: $set.rpe)
        }.formStyle(.grouped).navigationTitle("Edit set").inlineTitle()
    }
}
