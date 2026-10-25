import SwiftUI
import Charts
import LiftingCore

struct ProgressView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    @State private var search = ""
    @State private var metric = Metric.weight
    @State private var range = ProgressRange.all
    @State private var selectedProgramID: UUID?
    /// Up to six charted lifts. Each keeps its slot, and so its color, until it is removed.
    @AppStorage("progress.chartLifts") private var liftSlots = ""
    /// Charted lifts switched off from the legend.
    @AppStorage("progress.hiddenLifts") private var hiddenLifts = ""
    @State private var initialized = false
    @State private var view = ProgressMode.exercises

    var body: some View {
        let history = ProgressHistory(data: store.data, programID: selectedProgramID, includeHidden: false)
        let hidden = ProgressHistory(data: store.data, programID: selectedProgramID).exercises.filter { $0.hiddenFromProgress == true }
        let lifts = chartedLifts(history)
        let tracks = liftTracks(lifts, history: history)
        let records = history.records(preferredMetric: metric).filter {
            search.isEmpty || $0.exercise.name.localizedCaseInsensitiveContains(search)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker("View", selection: $view) { ForEach(ProgressMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("progress.view")
                VStack(alignment: .leading, spacing: 14) {
                    if view == .exercises {
                        HStack {
                            liftMenu(lifts, history: history)
                            Spacer(minLength: 8)
                            ProgressMetricPicker(metric: $metric, metrics: Metric.allCases)
                        }
                    }
                    ProgressRangePicker(range: $range)
                    switch view {
                    case .exercises:
                        ProgressLineChart(tracks: tracks, metric: metric, unit: store.data.settings.unit, height: 270, showsLegend: false, labelsLineEnds: true,
                                          emptyText: lifts.isEmpty ? "Choose lifts to chart from the menu above." : "Turn on a lift below to chart it.")
                        liftLegend(lifts, showsLightDays: tracks.contains { track in track.points.contains { track.light.contains($0.id) } })
                    case .muscles: MuscleAnalyticsView(programID: selectedProgramID, since: range.since, days: range.rawValue)
                    case .body: BodyWeightView(since: range.since)
                    }
                }
                .card()

                if view == .exercises { SectionTitle(title: "Records").padding(.top, 4); VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search logged exercises", text: $search)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("progress.search")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(palette.field, in: Capsule())

                    if records.isEmpty {
                        Text(history.exercises.isEmpty ? "No exercises logged." : "No matching exercises.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                    ForEach(records) { record in
                        NavigationLink { ExerciseProgress(exerciseID: record.exercise.id, programID: selectedProgramID) } label: {
                            ProgressRecordRow(record: record, unit: store.data.settings.unit)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Hide from Progress", systemImage: "eye.slash") { store.setHiddenFromProgress(record.exercise.id, true) } }
                        if record.id != records.last?.id { Divider() }
                    }
                    if !hidden.isEmpty {
                        if !records.isEmpty { Divider() }
                        NavigationLink { HiddenExercisesView(programID: selectedProgramID) } label: {
                            HStack {
                                Text("Hidden exercises").foregroundStyle(.primary)
                                Spacer()
                                Text("\(hidden.count)").foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            }.padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("progress.hidden")
                    }
                }
                .card(padding: 16)
                }
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle("Progress")
        .onAppear {
            guard !initialized else { return }
            initialized = true
            // Fresh, or every charted lift deleted (a restore gives exercises new identities): start from the defaults.
            if !slots.contains(where: { id in id.map { store.data.exercise($0) != nil } ?? false }) { chooseRecentLifts(history) }
            if history.tracks(metric: metric).isEmpty, let exercise = history.exercises.first {
                metric = history.preferredMetric(for: exercise, preferred: metric)
            }
        }
        .onChange(of: selectedProgramID) { _, _ in
            search = ""; range = .all; metric = .weight
            let scoped = ProgressHistory(data: store.data, programID: selectedProgramID, includeHidden: false)
            if scoped.tracks(metric: metric).isEmpty, let exercise = scoped.exercises.first { metric = scoped.preferredMetric(for: exercise, preferred: metric) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Program", selection: $selectedProgramID) {
                        Text("All programs").tag(UUID?.none)
                        ForEach(store.data.recordedPrograms) { program in Text(program.name).tag(Optional(program.id)) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedProgramID.flatMap { store.data.program($0)?.name } ?? store.data.recordedPrograms.first { $0.id == selectedProgramID }?.name ?? "All programs").lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                    }
                }.accessibilityLabel("Program filter").accessibilityIdentifier("progress.program")
            }
        }
    }
}

// MARK: Charted lifts

private struct ChartedLift {
    let slot: Int
    let exercise: Exercise
    let on: Bool
}

extension ProgressView {
    private static let liftLimit = 6
    private var slots: [UUID?] {
        var ids = liftSlots.split(separator: ",", omittingEmptySubsequences: false).map { UUID(uuidString: String($0)) }
        while ids.count < Self.liftLimit { ids.append(nil) }
        return Array(ids.prefix(Self.liftLimit))
    }
    private var hiddenIDs: Set<UUID> { Set(hiddenLifts.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
    private func save(_ slots: [UUID?], hidden: Set<UUID>) {
        liftSlots = slots.map { $0?.uuidString ?? "" }.joined(separator: ",")
        hiddenLifts = hidden.filter { slots.contains($0) }.map(\.uuidString).joined(separator: ",")
    }

    /// The charted lifts logged in the current program filter, in slot order.
    private func chartedLifts(_ history: ProgressHistory) -> [ChartedLift] {
        let hidden = hiddenIDs
        return slots.enumerated().compactMap { slot, id in
            guard let id, let exercise = history.exercises.first(where: { $0.id == id }) else { return nil }
            return ChartedLift(slot: slot, exercise: exercise, on: !hidden.contains(id))
        }
    }

    /// First visit: the six lifts logged in the most sessions (the main lifts, not one day's accessories),
    /// the most recent first among equals, with four switched on.
    private func chooseRecentLifts(_ history: ProgressHistory) {
        var count: [UUID: Int] = [:], last: [UUID: Date] = [:]
        for session in history.data.sessions {
            for item in Set(session.exercises.filter { $0.sets.contains { $0.completedAt != nil && $0.plan.kind != .warmup } }.map(\.exerciseID)) {
                count[item, default: 0] += 1
                last[item] = max(last[item] ?? .distantPast, session.startedAt)
            }
        }
        let chosen = history.exercises.filter { $0.mode != .cardio }.sorted {
            count[$0.id, default: 0] != count[$1.id, default: 0] ? count[$0.id, default: 0] > count[$1.id, default: 0] : (last[$0.id] ?? .distantPast) > (last[$1.id] ?? .distantPast)
        }.prefix(Self.liftLimit).map(\.id)
        save(chosen.map(Optional.some), hidden: Set(chosen.dropFirst(4)))
    }

    private func setCharted(_ id: UUID, _ charted: Bool) {
        var current = slots
        var hidden = hiddenIDs
        if charted {
            guard !current.contains(id), let empty = current.firstIndex(where: { $0 == nil }) else { return }
            current[empty] = id; hidden.remove(id)
        } else if let index = current.firstIndex(of: id) {
            current[index] = nil
        }
        save(current, hidden: hidden)
    }

    private func toggleShown(_ id: UUID) {
        var hidden = hiddenIDs
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        save(slots, hidden: hidden)
    }

    private func liftTracks(_ lifts: [ChartedLift], history: ProgressHistory) -> [ProgressTrack] {
        lifts.filter(\.on).compactMap { lift in
            let points = history.points(exerciseID: lift.exercise.id, metric: metric, since: range.since)
            guard !points.isEmpty else { return nil }
            return ProgressTrack(id: lift.exercise.id, exerciseID: lift.exercise.id, label: lift.exercise.name, shortLabel: lift.exercise.name,
                                 colorIndex: lift.slot, points: points, light: history.lightSessions(exerciseID: lift.exercise.id))
        }
    }

    private func liftMenu(_ lifts: [ChartedLift], history: ProgressHistory) -> some View {
        let charted = Set(lifts.map(\.exercise.id))
        let full = slots.compactMap { $0 }.count >= Self.liftLimit
        return Menu {
            Section("Chart up to \(Self.liftLimit) lifts") {
                ForEach(history.exercises.filter { $0.mode != .cardio }) { exercise in
                    Toggle(exercise.name, isOn: Binding(get: { charted.contains(exercise.id) }, set: { setCharted(exercise.id, $0) }))
                        .disabled(full && !charted.contains(exercise.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(lifts.isEmpty ? "Choose lifts" : "\(lifts.filter(\.on).count) of \(lifts.count) lifts").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel("Charted lifts").accessibilityIdentifier("progress.lifts")
    }

    /// The legend doubles as the switch for each charted lift.
    private func liftLegend(_ lifts: [ChartedLift], showsLightDays: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 2) {
            ForEach(lifts, id: \.exercise.id) { lift in
                let color = progressColor(lift.slot, scheme: scheme)
                Button { toggleShown(lift.exercise.id) } label: {
                    HStack(spacing: 7) {
                        Circle().fill(lift.on ? color : .clear).overlay(Circle().strokeBorder(lift.on ? color : Color.secondary.opacity(0.6), lineWidth: 1.5)).frame(width: 9, height: 9)
                        Text(lift.exercise.name).font(.footnote).foregroundStyle(lift.on ? Color.primary : Color.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lift.exercise.name).accessibilityValue(lift.on ? "Shown" : "Hidden").accessibilityHint("Shows or hides this lift on the chart")
            }
            if showsLightDays {
                HStack(spacing: 7) {
                    Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 9, height: 9)
                    Text("Light day, off the line").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).accessibilityElement(children: .combine)
            }
        }
    }
}

struct ExerciseProgress: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    let exerciseID: UUID
    let programID: UUID?
    @State private var selectedVariant: UUID?
    @State private var metric = Metric.weight
    @State private var range = ProgressRange.all
    @State private var variantEditor: Variant?
    @State private var editingExercise = false
    @State private var initialized = false

    init(exerciseID: UUID, initialVariantID: UUID? = nil, programID: UUID? = nil) {
        self.exerciseID = exerciseID; self.programID = programID
        _selectedVariant = State(initialValue: initialVariantID)
    }

    private var exercise: Exercise? { store.data.exercise(exerciseID) }
    private var variants: [Variant] { store.data.variants.filter { $0.exerciseID == exerciseID } }

    var body: some View {
        let history = ProgressHistory(data: store.data, programID: programID)
        let availableTracks = history.tracks(exerciseID: exerciseID, metric: metric)
        let tracks = history.tracks(exerciseID: exerciseID, variantID: selectedVariant, metric: metric, since: range.since)
        let sessions = resultSessions
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    if availableTracks.count > 1 {
                        trackPicker(availableTracks)
                    }
                    HStack {
                        ProgressMetricPicker(metric: $metric, metrics: ProgressHistory.metrics(for: exercise?.mode ?? .strength))
                        Spacer()
                        Text(progressUnit(metric, weightUnit: store.data.settings.unit)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ProgressRangePicker(range: $range)
                    ProgressLineChart(tracks: tracks, metric: metric, unit: store.data.settings.unit, height: 260, barsForVolume: true)
                    if !tracks.isEmpty {
                        Divider()
                        ProgressStatistics(tracks: tracks, metric: metric, unit: store.data.settings.unit)
                    }
                }
                .card()

                repRecords(history)

                SectionTitle(title: "Results")
                VStack(alignment: .leading, spacing: 16) {
                    if sessions.isEmpty {
                        Text("No logged sets in this range.").foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                    ForEach(sessions) { session in
                        NavigationLink { SessionDetail(sessionID: session.id) } label: {
                            resultRow(session, history: history)
                        }
                        .buttonStyle(.plain)
                        if session.id != sessions.last?.id { Divider() }
                    }
                }
                .card()
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle(exercise?.name ?? "Progress")
        .inlineTitle()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if let exercise {
                metric = history.preferredMetric(for: exercise, variantID: selectedVariant, preferred: exercise.mode == .cardio ? .duration : .weight)
            }
            validateTrack()
        }
        .onChange(of: metric) { _, _ in validateTrack() }
        .toolbar {
            Menu {
                Button { editingExercise = true } label: { Label("Edit Exercise", systemImage: "pencil") }
                if exercise?.hiddenFromProgress == true { Button("Show in Progress", systemImage: "eye") { store.setHiddenFromProgress(exerciseID, false) } }
                else { Button("Hide from Progress", systemImage: "eye.slash") { store.setHiddenFromProgress(exerciseID, true) } }
                if !variants.isEmpty {
                    Menu("Prescriptions") {
                        ForEach(variants) { variant in
                            Button(history.trackLabel(variant.id, fallback: variant.label)) { variantEditor = variant }
                        }
                    }
                }
            } label: { Image(systemName: "ellipsis") }
            .compactMenu()
            .accessibilityLabel("Exercise options")
        }
        .sheet(isPresented: $editingExercise) {
            ExerciseEditor(initialExercise: exercise) { value in
                store.perform { data in
                    if let index = data.exercises.firstIndex(where: { $0.id == value.id }) { data.exercises[index] = value }
                }
            }
            .sheetSize()
        }
        .sheet(item: $variantEditor) { SavedExerciseEditor(variantID: $0.id).environmentObject(store).sheetSize() }
    }

    /// The heaviest weight lifted for at least 1, 3, 5, 8, 10, and 12 reps, up to the most reps logged.
    @ViewBuilder private func repRecords(_ history: ProgressHistory) -> some View {
        let unit = store.data.settings.unit
        let records = exercise?.mode == .strength ? history.data.repRecords(exerciseID: exerciseID, variantID: selectedVariant) : []
        if !records.isEmpty {
            SectionTitle(title: "Rep records")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(records, id: \.reps) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.reps == 1 ? "1 rep" : "\(record.reps) reps").font(.caption).foregroundStyle(.secondary)
                        Text("\(number(unit.display(record.weight))) \(unit.rawValue)").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                        Text(record.date.formatted(Calendar.current.isDate(record.date, equalTo: .now, toGranularity: .year)
                                                   ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).year()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private func trackPicker(_ tracks: [ProgressTrack]) -> some View {
        if tracks.count <= 2 {
            Picker("Track", selection: $selectedVariant) {
                Text("All").tag(UUID?.none)
                ForEach(tracks) { track in Text(track.shortLabel).tag(Optional(track.id)) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityIdentifier("progress.track")
        } else {
            Picker("Track", selection: $selectedVariant) {
                Text("All tracks").tag(UUID?.none)
                ForEach(tracks) { track in Text(track.shortLabel).tag(Optional(track.id)) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("progress.track")
        }
    }

    private func validateTrack() {
        guard let id = selectedVariant else { return }
        let history = ProgressHistory(data: store.data, programID: programID)
        if history.tracks(exerciseID: exerciseID, variantID: id, metric: metric).isEmpty { selectedVariant = nil }
    }

    private var resultSessions: [Session] {
        store.data.sessions(inProgram: programID).filter { session in
            session.startedAt >= range.since && session.exercises.contains { item in
                item.exerciseID == exerciseID && (selectedVariant == nil || item.variantID == selectedVariant)
                    && item.sets.contains { $0.completedAt != nil && $0.plan.kind != .warmup }
            }
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    private func resultRow(_ session: Session, history: ProgressHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().year()).font(.headline)
                Spacer()
                Text(store.data.title(for: session)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            ForEach(session.exercises.filter { item in
                item.exerciseID == exerciseID && (selectedVariant == nil || item.variantID == selectedVariant)
                    && item.sets.contains { $0.completedAt != nil && $0.plan.kind != .warmup }
            }) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(history.trackLabel(item.variantID, fallback: item.label)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(loggedExerciseSummary(item, unit: store.data.settings.unit))
                        .font(.subheadline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    if !item.notes.isEmpty { Text(item.notes).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            if !session.notes.isEmpty { Text(session.notes).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// Exercises left out of the Progress overview, with a way to show each again.
struct HiddenExercisesView: View {
    @EnvironmentObject var store: AppStore
    let programID: UUID?
    private var exercises: [Exercise] { ProgressHistory(data: store.data, programID: programID).exercises.filter { $0.hiddenFromProgress == true } }
    var body: some View {
        ThemedForm {
            Section {
                if exercises.isEmpty { Text("No hidden exercises").foregroundStyle(.secondary) }
                ForEach(exercises) { exercise in
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        Button("Show") { store.setHiddenFromProgress(exercise.id, false) }.buttonStyle(.borderless).accessibilityLabel("Show \(exercise.name) in Progress")
                    }
                }
            } footer: { Text("Hidden exercises are left out of the Progress chart and records. Their history is kept.") }
        }
        .formStyle(.grouped).navigationTitle("Hidden Exercises").inlineTitle()
    }
}

private enum ProgressRange: Int, CaseIterable, Identifiable {
    case month = 30, quarter = 90, year = 365, all = 0
    var id: Int { rawValue }
    var title: String {
        switch self { case .month: return "1M"; case .quarter: return "3M"; case .year: return "1Y"; case .all: return "All" }
    }
    var since: Date {
        self == .all ? .distantPast : Calendar.current.date(byAdding: .day, value: -rawValue, to: .now) ?? .distantPast
    }
}

private enum ProgressMode: String, CaseIterable, Identifiable {
    case exercises = "Exercises", muscles = "Muscles", body = "Body Weight"
    var id: Self { self }
}

private struct ProgressRangePicker: View {
    @Binding var range: ProgressRange
    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(ProgressRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .accessibilityIdentifier("progress.range")
    }
}

private struct ProgressMetricPicker: View {
    @Binding var metric: Metric
    let metrics: [Metric]
    var body: some View {
        Picker("Metric", selection: $metric) { ForEach(metrics) { Text($0.title).tag($0) } }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityIdentifier("progress.metric")
    }
}

private struct ProgressTrack: Identifiable {
    let id: UUID
    let exerciseID: UUID
    let label: String
    let shortLabel: String
    let colorIndex: Int
    let points: [ProgressPoint]
    /// Deloads and light days: plotted, but off the line and out of the statistics.
    var light: Set<UUID> = []
    var regularPoints: [ProgressPoint] { points.filter { !light.contains($0.id) } }
    var data: [ProgressChartDatum] {
        points.map { ProgressChartDatum(id: "\(id.uuidString)-\($0.id.uuidString)", sessionID: $0.id, trackID: id, date: $0.date, value: $0.value, light: light.contains($0.id)) }
    }
}

private struct ProgressChartDatum: Identifiable {
    let id: String
    let sessionID: UUID
    let trackID: UUID
    let date: Date
    let value: Double
    let light: Bool
}

private struct ProgressLineChart: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    let tracks: [ProgressTrack]
    let metric: Metric
    let unit: WeightUnit
    var height: CGFloat
    var showsLegend = true
    /// Labels each line's latest value at its end, for up to four lines.
    var labelsLineEnds = false
    /// Volume reads as bars: an amount per session rather than a level that carries over.
    var barsForVolume = false
    var emptyText = "No logged values in this range."
    @State private var selectedDate: Date?
    private var bars: Bool { barsForVolume && metric == .volume }
    private var endLabels: Bool { labelsLineEnds && !bars && tracks.count <= 4 }

    private var data: [ProgressChartDatum] { tracks.flatMap(\.data) }
    private var selectedPoints: [ProgressChartDatum] {
        guard let selectedDate, let nearest = data.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }) else { return [] }
        return data.filter { $0.sessionID == nearest.sessionID }
    }
    private var dateDomain: ClosedRange<Date> {
        let dates = data.map(\.date)
        let first = dates.min() ?? .now
        let last = dates.max() ?? first
        let padding = max(last.timeIntervalSince(first) * 0.025, 43_200)
        // Room after the last point for the end labels.
        let trailing = endLabels ? max(last.timeIntervalSince(first) * 0.14, 86_400 * 2) : padding
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(trailing)
    }
    private var valueDomain: ClosedRange<Double> {
        if metric == .rpe { return 0...10 }
        let values = data.map(\.value)
        if bars { return 0...max((values.max() ?? 1) * 1.1, 1) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.15, max(high * 0.05, 1))
        return max(0, low - padding)...max(high + padding, 1)
    }
    private var dateFormat: Date.FormatStyle {
        if dateDomain.upperBound.timeIntervalSince(dateDomain.lowerBound) < 172_800 { return .dateTime.hour().minute() }
        return dateDomain.upperBound.timeIntervalSince(dateDomain.lowerBound) > 366 * 86_400
            ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.abbreviated).day()
    }

    var body: some View {
        let plotted = data
        let selection = selectedPoints
        if plotted.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line").font(.largeTitle)
                Text(emptyText).font(.subheadline).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                plot(plotted, selection: selection)

                if showsLegend {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(tracks) { track in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(progressColor(track.colorIndex, scheme: scheme)).frame(width: 7, height: 7)
                                Text(track.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if plotted.contains(where: \.light) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if bars { RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.35)).frame(width: 7, height: 9) }
                                else { Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 7, height: 7) }
                                Text(bars ? "Light day" : "Light day, off the line").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let first = selection.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(first.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(selection) { point in
                            if let track = tracks.first(where: { $0.id == point.trackID }) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle().fill(progressColor(track.colorIndex, scheme: scheme)).frame(width: 7, height: 7)
                                    Text(point.light ? "\(track.label), light day" : track.label).font(.subheadline)
                                    Spacer()
                                    Text(progressValue(point.value, metric: metric, unit: unit)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("progress.selection")
                }
            }
            .onChange(of: metric) { _, _ in selectedDate = nil }
        }
    }

    private func plot(_ plotted: [ProgressChartDatum], selection: [ProgressChartDatum]) -> some View {
        let selectedIDs = Set(selection.map(\.id))
        let domain: [String] = tracks.map { $0.id.uuidString }
        let colors: [Color] = tracks.map { progressColor($0.colorIndex, scheme: scheme) }
        return Chart {
            ForEach(plotted) { point in
                if bars {
                    barMark(point)
                } else {
                    if !point.light { lineMark(point) }
                    pointMark(point, selected: selectedIDs.contains(point.id))
                }
            }
            if let point = selection.first { selectionRule(point.date) }
        }
        .chartForegroundStyleScale(domain: domain, range: colors)
        .chartLegend(.hidden)
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: valueDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                AxisTick().foregroundStyle(.secondary.opacity(0.4))
                AxisValueLabel(format: dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                AxisGridLine().foregroundStyle(.primary.opacity(0.1))
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)))
            }
        }
        .chartYAxisLabel(progressUnit(metric, weightUnit: unit), position: .topLeading)
        .chartOverlay { proxy in
            if endLabels {
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let origin = geometry[frame].origin
                        ZStack(alignment: .topLeading) {
                            ForEach(lineEnds(proxy), id: \.id) { end in
                                Text(number(end.value)).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                                    .offset(x: origin.x + end.x + 7, y: origin.y + end.y - 7)
                            }
                        }
                    }
                }.allowsHitTesting(false)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
            DragGesture(minimumDistance: 0)
                .onChanged { proxy.selectXValue(at: $0.location.x) }
                .onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .frame(height: height)
        .accessibilityLabel("\(metric.title) by date")
    }

    private func lineMark(_ point: ProgressChartDatum) -> some ChartContent {
        let date: PlottableValue<Date> = .value("Date", point.date)
        let value: PlottableValue<Double> = .value(metric.title, point.value)
        let track: PlottableValue<String> = .value("Track", point.trackID.uuidString)
        return LineMark(x: date, y: value, series: track)
            .foregroundStyle(by: track)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.linear)
    }

    private func pointMark(_ point: ProgressChartDatum, selected: Bool) -> some ChartContent {
        let date: PlottableValue<Date> = .value("Date", point.date)
        let value: PlottableValue<Double> = .value(metric.title, point.value)
        let track: PlottableValue<String> = .value("Track", point.trackID.uuidString)
        let size: CGFloat = selected ? 60 : 22
        return PointMark(x: date, y: value)
            .foregroundStyle(by: track)
            .symbol {
                // A light day is a hollow ring, a regular session a filled dot, both in the track's color.
                let diameter: CGFloat = selected ? 9 : 6
                let color = progressColor(tracks.first { $0.id == point.trackID }?.colorIndex ?? 0, scheme: scheme)
                if point.light {
                    Circle().strokeBorder(color, lineWidth: 1.5).background(Circle().fill(palette.card)).frame(width: diameter + 2, height: diameter + 2)
                } else {
                    Circle().fill(color).frame(width: diameter, height: diameter)
                }
            }
            .symbolSize(size)
    }

    private func barMark(_ point: ProgressChartDatum) -> some ChartContent {
        BarMark(x: .value("Date", point.date, unit: .day), y: .value(metric.title, point.value), width: .fixed(tracks.count > 1 ? 6 : 10))
            .foregroundStyle(by: .value("Track", point.trackID.uuidString))
            .opacity(point.light ? 0.35 : 1)
            .cornerRadius(3)
    }

    /// Each line's latest regular point in plot coordinates, nudged apart so the labels never overlap.
    private func lineEnds(_ proxy: ChartProxy) -> [(id: String, value: Double, x: CGFloat, y: CGFloat)] {
        var ends = tracks.compactMap { track -> (id: String, value: Double, x: CGFloat, y: CGFloat)? in
            guard let last = track.data.last(where: { !$0.light }), let x = proxy.position(forX: last.date), let y = proxy.position(forY: last.value) else { return nil }
            return (last.id, last.value, x, y)
        }.sorted { $0.y < $1.y }
        for index in ends.indices.dropFirst() where ends[index].y - ends[index - 1].y < 14 { ends[index].y = ends[index - 1].y + 14 }
        return ends
    }

    private func selectionRule(_ date: Date) -> some ChartContent {
        let value: PlottableValue<Date> = .value("Selected date", date)
        return RuleMark(x: value)
            .foregroundStyle(Color.secondary.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

private struct ProgressStatistics: View {
    @Environment(\.palette) private var palette
    let tracks: [ProgressTrack]
    let metric: Metric
    let unit: WeightUnit

    var body: some View {
        if tracks.count == 1, let track = tracks.first {
            HStack(alignment: .top, spacing: 12) {
                stat("Latest", value: track.regularPoints.last?.value ?? 0)
                stat(metric == .rpe ? "Peak" : "Best", value: track.regularPoints.map(\.value).max() ?? 0, color: palette.best)
                stat("Change", value: change(track), signed: true)
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Track")
                    Text("Latest")
                    Text(metric == .rpe ? "Peak" : "Best")
                    Text("Change")
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(tracks) { track in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(track.shortLabel).font(.caption.weight(.medium))
                        Text(number(track.regularPoints.last?.value ?? 0))
                        Text(number(track.regularPoints.map(\.value).max() ?? 0)).foregroundStyle(palette.best)
                        Text(signedNumber(change(track)))
                    }
                    .font(.subheadline).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Light days are left out, so a deload is never the latest result or the change.
    private func change(_ track: ProgressTrack) -> Double { (track.regularPoints.last?.value ?? 0) - (track.regularPoints.first?.value ?? 0) }
    private func stat(_ title: String, value: Double, signed: Bool = false, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(signed ? signedNumber(value) : number(value)).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                .minimumScaleFactor(0.75).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressRecord: Identifiable {
    let exercise: Exercise
    let metric: Metric
    let tracks: [ProgressTrack]
    /// Each session's heaviest set, for lifts with logged weights.
    var tops: [TopSet] = []
    var id: UUID { exercise.id }
    /// The heaviest set ever, more reps breaking a tie.
    var bestTop: TopSet? { tops.max { $0.weight == $1.weight ? $0.reps < $1.reps : $0.weight < $1.weight } }
    var latest: ProgressChartDatum? { tracks.flatMap(\.data).max { $0.date < $1.date } }
    var best: Double { tracks.flatMap(\.points).map(\.value).max() ?? 0 }
}

private struct ProgressRecordRow: View {
    @Environment(\.palette) private var palette
    let record: ProgressRecord
    let unit: WeightUnit
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.exercise.name).font(.headline).foregroundStyle(.primary)
                if let latest = record.latest {
                    let track = record.tracks.first { $0.id == latest.trackID }
                    Text(record.tracks.count > 1 ? "\(track?.shortLabel ?? "") · \(latest.date.formatted(.dateTime.month(.abbreviated).day()))" : latest.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                if let latest = record.tops.last, let best = record.bestTop {
                    // The latest top set, then either that it is the record or what the record is.
                    Text(setText(latest)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).monospacedDigit()
                    if best.weight > latest.weight || (best.weight == latest.weight && best.reps > latest.reps) {
                        Text("Best \(setText(best))").font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Label("Record", systemImage: "star.fill").labelStyle(TightLabelStyle()).font(.caption.weight(.medium)).foregroundStyle(palette.best)
                    }
                } else {
                    let latest = record.latest?.value ?? 0
                    Text(progressValue(latest, metric: record.metric, unit: unit)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).monospacedDigit()
                    if record.best > latest {
                        Text("\(record.metric == .rpe ? "Peak" : "Best") \(progressValue(record.best, metric: record.metric, unit: unit))").font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                    } else if record.metric != .rpe {
                        Label("Record", systemImage: "star.fill").labelStyle(TightLabelStyle()).font(.caption.weight(.medium)).foregroundStyle(palette.best)
                    }
                }
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private func setText(_ set: TopSet) -> String { "\(number(unit.display(set.weight))) \(unit.rawValue) × \(set.reps)" }
}

private struct ProgressHistory {
    private struct Descriptor {
        let id: UUID
        let exercise: Exercise
        let label: String
    }
    let data: TrainingData
    let exercises: [Exercise]
    private let descriptors: [Descriptor]

    /// The overview leaves out exercises hidden from Progress; an exercise's own screen includes them.
    init(data: TrainingData, programID: UUID? = nil, includeHidden: Bool = true) {
        var data = data
        if !includeHidden {
            let hidden = Set(data.exercises.filter { $0.hiddenFromProgress == true }.map(\.id))
            data.sessions = data.sessions.map { session in var copy = session; copy.exercises.removeAll { hidden.contains($0.exerciseID) }; return copy }
        }
        data.sessions = data.sessions(inProgram: programID)
        self.data = data
        var observed: [UUID: SessionExercise] = [:]
        for session in data.sessions {
            for item in session.exercises where item.sets.contains(where: { $0.completedAt != nil && $0.plan.kind != .warmup }) {
                observed[item.variantID] = item
            }
        }
        let loggedIDs = Set(observed.values.map(\.exerciseID))
        exercises = data.exercises.filter { loggedIDs.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        descriptors = observed.values.compactMap { item in
            guard let exercise = data.exercise(item.exerciseID) else { return nil }
            return Descriptor(id: item.variantID, exercise: exercise, label: data.variant(item.variantID)?.label ?? item.label)
        }.sorted {
            if $0.exercise.name != $1.exercise.name { return $0.exercise.name.localizedStandardCompare($1.exercise.name) == .orderedAscending }
            if $0.label != $1.label { return $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func metrics(for mode: ExerciseMode) -> [Metric] {
        mode == .cardio ? [.duration, .distance, .rpe] : [.weight, .volume, .estimatedMax, .reps, .duration, .distance, .rpe]
    }

    func trackLabel(_ id: UUID, fallback: String) -> String {
        guard let descriptor = descriptors.first(where: { $0.id == id }) else { return fallback }
        let matches = descriptors.filter { $0.exercise.id == descriptor.exercise.id && $0.label == descriptor.label }
        guard matches.count > 1, let index = matches.firstIndex(where: { $0.id == id }) else { return descriptor.label }
        return "\(descriptor.label) (\(index + 1))"
    }

    func tracks(exerciseID: UUID? = nil, variantID: UUID? = nil, metric: Metric, since: Date = .distantPast) -> [ProgressTrack] {
        descriptors.enumerated().compactMap { index, descriptor in
            guard exerciseID == nil || descriptor.exercise.id == exerciseID,
                  variantID == nil || descriptor.id == variantID,
                  Self.metrics(for: descriptor.exercise.mode).contains(metric) else { return nil }
            let points = data.points(exerciseID: descriptor.exercise.id, variantID: descriptor.id, metric: metric, since: since).map { point in
                var displayed = point
                if [.weight, .volume, .estimatedMax].contains(metric) { displayed.value = data.settings.unit.display(point.value) }
                return displayed
            }.filter { $0.value.isFinite }
            guard !points.isEmpty else { return nil }
            let shortLabel = trackLabel(descriptor.id, fallback: descriptor.label)
            let siblings = descriptors.filter { $0.exercise.id == descriptor.exercise.id }
            let label = exerciseID != nil ? shortLabel : siblings.count > 1 ? "\(descriptor.exercise.name) · \(shortLabel)" : descriptor.exercise.name
            return ProgressTrack(id: descriptor.id, exerciseID: descriptor.exercise.id, label: label, shortLabel: shortLabel, colorIndex: index, points: points,
                                 light: lightSessions(exerciseID: descriptor.exercise.id, variantID: descriptor.id))
        }
    }

    /// An exercise's points across all its tracks, in the display unit.
    func points(exerciseID: UUID, metric: Metric, since: Date) -> [ProgressPoint] {
        data.points(exerciseID: exerciseID, metric: metric, since: since).map { point in
            var displayed = point
            if [.weight, .volume, .estimatedMax].contains(metric) { displayed.value = data.settings.unit.display(point.value) }
            return displayed
        }.filter { $0.value.isFinite }
    }

    /// Judged on the whole history, so the first session in a short range is compared with the ones before it.
    func lightSessions(exerciseID: UUID, variantID: UUID? = nil) -> Set<UUID> {
        guard data.exercise(exerciseID)?.mode == .strength else { return [] }
        return TrainingData.lightSessions(data.topSets(exerciseID: exerciseID, variantID: variantID))
    }

    func preferredMetric(for exercise: Exercise, variantID: UUID? = nil, preferred: Metric) -> Metric {
        let choices: [Metric] = exercise.mode == .cardio ? [preferred, .duration, .distance, .rpe] : [preferred, .weight, .reps, .duration, .distance, .rpe]
        for choice in choices where Self.metrics(for: exercise.mode).contains(choice) {
            if !tracks(exerciseID: exercise.id, variantID: variantID, metric: choice).isEmpty { return choice }
        }
        return exercise.mode == .cardio ? .duration : .weight
    }

    func records(preferredMetric: Metric) -> [ProgressRecord] {
        exercises.map { exercise in
            let metric = self.preferredMetric(for: exercise, preferred: preferredMetric)
            return ProgressRecord(exercise: exercise, metric: metric, tracks: tracks(exerciseID: exercise.id, metric: metric),
                                  tops: exercise.mode == .strength ? data.topSets(exerciseID: exercise.id) : [])
        }
    }
}

/// Six chart colors in a fixed order, checked to stay distinct for color-blind readers in light and dark mode.
/// A line keeps its color by slot, so hiding one lift never repaints another.
func progressColor(_ index: Int, scheme: ColorScheme) -> Color {
    let light: [UInt] = [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100, 0xE87BA4, 0x6250D6]
    let dark: [UInt] = [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x9085E9]
    return Color(hex: (scheme == .dark ? dark : light)[index % light.count])
}

private func progressUnit(_ metric: Metric, weightUnit: WeightUnit) -> String {
    switch metric {
    case .weight, .volume, .estimatedMax: return metric == .volume ? "\(weightUnit.rawValue) × reps" : weightUnit.rawValue
    case .reps: return "reps"
    case .duration: return "min"
    case .distance: return "km"
    case .rpe: return "RPE"
    }
}

private func progressValue(_ value: Double, metric: Metric, unit: WeightUnit) -> String {
    "\(number(value)) \(progressUnit(metric, weightUnit: unit))"
}

private func signedNumber(_ value: Double) -> String { value > 0 ? "+\(number(value))" : number(value) }
