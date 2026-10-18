import SwiftUI
import Charts
import LiftingCore

struct ProgressView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var creating = false
    @State private var metric = Metric.weight
    @State private var range = ProgressRange.all
    @State private var selectedProgramID: UUID?
    @State private var selectedExerciseID: UUID?
    @State private var initialized = false

    var body: some View {
        let history = ProgressHistory(data: store.data, programID: selectedProgramID)
        let tracks = history.tracks(exerciseID: selectedExerciseID, metric: metric, since: range.since)
        let records = history.records(preferredMetric: metric).filter {
            search.isEmpty || $0.exercise.name.localizedCaseInsensitiveContains(search)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Program", selection: $selectedProgramID) {
                        Text("All programs").tag(UUID?.none)
                        ForEach(store.data.recordedPrograms) { program in Text(program.name).tag(Optional(program.id)) }
                    }.pickerStyle(.menu).accessibilityIdentifier("progress.program")
                    HStack {
                        Picker("Exercise", selection: $selectedExerciseID) {
                            Text("All").tag(UUID?.none)
                            ForEach(history.exercises) { exercise in
                                Text(exercise.name).tag(Optional(exercise.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("progress.exercise")
                        Spacer(minLength: 8)
                        ProgressMetricPicker(metric: $metric, metrics: Metric.allCases)
                    }
                    ProgressRangePicker(range: $range)
                    ProgressLineChart(tracks: tracks, metric: metric, unit: store.data.settings.unit, height: 270)
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Records").font(.title2.weight(.semibold))
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
                    .padding(10)
                    .background(Palette.secondary(scheme), in: RoundedRectangle(cornerRadius: 8))

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
                        if record.id != records.last?.id { Divider() }
                    }
                }
                .card()
            }
            .padding(16)
        }
        .background(Palette.background(scheme))
        .navigationTitle("Progress")
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if history.tracks(metric: metric).isEmpty, let exercise = history.exercises.first {
                metric = history.preferredMetric(for: exercise, preferred: metric)
            }
        }
        .onChange(of: selectedProgramID) { _, _ in
            selectedExerciseID = nil; search = ""; range = .all; metric = .weight
            let scoped = ProgressHistory(data: store.data, programID: selectedProgramID)
            if scoped.tracks(metric: metric).isEmpty, let exercise = scoped.exercises.first { metric = scoped.preferredMetric(for: exercise, preferred: metric) }
        }
        .onChange(of: selectedExerciseID) { _, id in
            guard let id, let exercise = store.data.exercise(id) else { return }
            if !ProgressHistory.metrics(for: exercise.mode).contains(metric) {
                metric = history.preferredMetric(for: exercise, preferred: metric)
            }
        }
        .onChange(of: metric) { _, value in
            if let id = selectedExerciseID, let exercise = store.data.exercise(id),
               !ProgressHistory.metrics(for: exercise.mode).contains(value) {
                selectedExerciseID = nil
            }
        }
        .toolbar {
            Button { creating = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Create exercise")
        }
        .sheet(isPresented: $creating) {
            ExerciseEditor { exercise in store.perform { $0.exercises.append(exercise) } }.sheetSize()
        }
    }
}

struct ExerciseProgress: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
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
                    ProgressLineChart(tracks: tracks, metric: metric, unit: store.data.settings.unit, height: 260)
                    if !tracks.isEmpty {
                        Divider()
                        ProgressStatistics(tracks: tracks, metric: metric, unit: store.data.settings.unit)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Results").font(.title2.weight(.semibold))
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
        .background(Palette.background(scheme))
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
                Button { editingExercise = true } label: { Label("Edit exercise", systemImage: "pencil") }
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
        .sheet(item: $variantEditor) { VariantEditor(variant: $0).environmentObject(store).sheetSize() }
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
    var data: [ProgressChartDatum] {
        points.map { ProgressChartDatum(id: "\(id.uuidString)-\($0.id.uuidString)", sessionID: $0.id, trackID: id, date: $0.date, value: $0.value) }
    }
}

private struct ProgressChartDatum: Identifiable {
    let id: String
    let sessionID: UUID
    let trackID: UUID
    let date: Date
    let value: Double
}

private struct ProgressLineChart: View {
    @Environment(\.colorScheme) private var scheme
    let tracks: [ProgressTrack]
    let metric: Metric
    let unit: WeightUnit
    var height: CGFloat
    @State private var selectedDate: Date?

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
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
    private var valueDomain: ClosedRange<Double> {
        if metric == .rpe { return 0...10 }
        let values = data.map(\.value)
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
                Text("No logged values in this range.").font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                plot(plotted, selection: selection)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(tracks) { track in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(progressColor(track.colorIndex, scheme: scheme)).frame(width: 7, height: 7)
                            Text(track.label).font(.caption).foregroundStyle(.secondary)
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
                                    Text(track.label).font(.subheadline)
                                    Spacer()
                                    Text(progressValue(point.value, metric: metric, unit: unit)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Palette.secondary(scheme), in: RoundedRectangle(cornerRadius: 8))
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
                lineMark(point)
                pointMark(point, selected: selectedIDs.contains(point.id))
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
            .symbolSize(size)
    }

    private func selectionRule(_ date: Date) -> some ChartContent {
        let value: PlottableValue<Date> = .value("Selected date", date)
        return RuleMark(x: value)
            .foregroundStyle(Color.secondary.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

private struct ProgressStatistics: View {
    let tracks: [ProgressTrack]
    let metric: Metric
    let unit: WeightUnit

    var body: some View {
        if tracks.count == 1, let track = tracks.first {
            HStack(alignment: .top, spacing: 12) {
                stat("Latest", value: track.points.last?.value ?? 0)
                stat(metric == .rpe ? "Peak" : "Best", value: track.points.map(\.value).max() ?? 0)
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
                        Text(number(track.points.last?.value ?? 0))
                        Text(number(track.points.map(\.value).max() ?? 0))
                        Text(signedNumber(change(track)))
                    }
                    .font(.subheadline).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func change(_ track: ProgressTrack) -> Double { (track.points.last?.value ?? 0) - (track.points.first?.value ?? 0) }
    private func stat(_ title: String, value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(signed ? signedNumber(value) : number(value)).font(.title3.weight(.semibold)).monospacedDigit()
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
    var id: UUID { exercise.id }
    var latest: ProgressChartDatum? { tracks.flatMap(\.data).max { $0.date < $1.date } }
    var best: Double { tracks.flatMap(\.points).map(\.value).max() ?? 0 }
}

private struct ProgressRecordRow: View {
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
                Text(progressValue(record.latest?.value ?? 0, metric: record.metric, unit: unit)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).monospacedDigit()
                Text("\(record.metric == .rpe ? "Peak" : "Best") \(progressValue(record.best, metric: record.metric, unit: unit))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
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

    init(data: TrainingData, programID: UUID? = nil) {
        var data = data
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
            return ProgressTrack(id: descriptor.id, exerciseID: descriptor.exercise.id, label: label, shortLabel: shortLabel, colorIndex: index, points: points)
        }
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
            return ProgressRecord(exercise: exercise, metric: metric, tracks: tracks(exerciseID: exercise.id, metric: metric))
        }
    }
}

private func progressColor(_ index: Int, scheme: ColorScheme) -> Color {
    let colors: [Color] = [Palette.tint(scheme), .blue, .orange, .purple, .red, .cyan, .pink, .indigo, .teal, .brown]
    return colors[index % colors.count]
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
