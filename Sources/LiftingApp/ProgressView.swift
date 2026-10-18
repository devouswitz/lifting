import SwiftUI
import Charts
import LiftingCore

struct ProgressView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var creating = false
    var body: some View {
        List {
            if !store.data.sessions.isEmpty {
                Section { HStack { MetricTile(value: "\(store.data.sessions.count)", label: "Workouts"); MetricTile(value: "\(store.data.sessions.reduce(0) { $0 + $1.completedSets })", label: "Sets logged") }.padding(.vertical, 8) }
            }
            Section("Exercises") {
                ForEach(store.data.exercises.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.name < $1.name }) { exercise in
                    NavigationLink { ExerciseProgress(exerciseID: exercise.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(exercise.name).font(.headline)
                                let variants = store.data.variants.filter { $0.exerciseID == exercise.id }
                                Text(variants.isEmpty ? exercise.mode.title : variants.map(\.label).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let points = store.data.points(exerciseID: exercise.id, metric: exercise.mode == .cardio ? .duration : .weight)
                            if points.count > 1 {
                                Chart(points) { point in LineMark(x: .value("Date", point.date), y: .value("Value", point.value)) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 64, height: 28).accessibilityHidden(true)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.navigationTitle("Progress").searchable(text: $search, prompt: "Search exercises")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create exercise") }
        .sheet(isPresented: $creating) { ExerciseEditor { exercise in store.perform { $0.exercises.append(exercise) } }.sheetSize() }
    }
}

struct ExerciseProgress: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    let exerciseID: UUID
    @State private var selectedVariant: UUID?
    @State private var metric = Metric.weight
    @State private var range = 90
    @State private var selectedDate: Date?
    @State private var variantEditor: Variant?
    @State private var editingExercise = false
    var exercise: Exercise? { store.data.exercise(exerciseID) }
    var variants: [Variant] { store.data.variants.filter { $0.exerciseID == exerciseID } }
    var since: Date { range == 0 ? .distantPast : Calendar.current.date(byAdding: .day, value: -range, to: .now)! }
    var points: [ProgressPoint] { store.data.points(exerciseID: exerciseID, variantID: selectedVariant, metric: metric, since: since) }
    var series: [ChartDatum] {
        variants.filter { selectedVariant == nil || $0.id == selectedVariant }.flatMap { variant in
            store.data.points(exerciseID: exerciseID, variantID: variant.id, metric: metric, since: since).map { ChartDatum(id: "\(variant.id)-\($0.id)", date: $0.date, value: display($0.value), label: chartLabel(variant), seriesID: variant.id.uuidString) }
        }
    }
    func chartLabel(_ variant: Variant) -> String {
        let matching = variants.filter { $0.label == variant.label }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == variant.id }) else { return variant.label }
        return "\(variant.label) (\(index + 1))"
    }
    func display(_ value: Double) -> Double { [.weight, .volume, .estimatedMax].contains(metric) ? store.data.settings.unit.display(value) : value }
    var unit: String { [.weight, .volume, .estimatedMax].contains(metric) ? store.data.settings.unit.rawValue : metric == .duration ? "min" : metric == .distance ? "km" : "" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text([exercise?.mode.title ?? "", exercise?.equipment ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { filterChip("All variants", id: nil); ForEach(variants) { filterChip($0.label, id: $0.id) } }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Metric", selection: $metric) {
                        ForEach(Metric.allCases.filter { exercise?.mode == .cardio ? [.duration, .distance, .rpe].contains($0) : true }) { Text($0.title).tag($0) }
                    }
                    Picker("Range", selection: $range) { Text("1M").tag(30); Text("3M").tag(90); Text("1Y").tag(365); Text("All").tag(0) }.pickerStyle(.segmented)
                    if series.isEmpty { EmptyState(symbol: "chart.xyaxis.line", text: "No logged sets in this range.") }
                    else {
                        Chart {
                            ForEach(series) { point in
                                LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value), series: .value("Variant", point.seriesID)).foregroundStyle(by: .value("Variant", point.label)).symbol(by: .value("Variant", point.label)).interpolationMethod(.linear)
                                PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value)).foregroundStyle(by: .value("Variant", point.label)).symbol(by: .value("Variant", point.label)).symbolSize(28)
                            }
                            if let selectedDate { RuleMark(x: .value("Selected date", selectedDate)).foregroundStyle(.secondary.opacity(0.4)) }
                        }.chartForegroundStyleScale(range: [Palette.tint(scheme), Color.orange, Color.blue, Color.purple, Color.gray])
                        .chartXSelection(value: $selectedDate).chartYAxisLabel(unit).frame(height: 230)
                        if let selectedDate, let point = series.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }) { Text("\(point.date.formatted(date: .abbreviated, time: .omitted)) · \(number(point.value)) \(unit) · \(point.label)").font(.caption).monospacedDigit() }
                        let values = points.map { display($0.value) }
                        HStack { MetricTile(value: "\(number(values.max() ?? 0))", label: "Best \(unit)"); MetricTile(value: "\(number(values.last ?? 0))", label: "Latest \(unit)"); MetricTile(value: "\(number((values.last ?? 0) - (values.first ?? 0)))", label: "Change \(unit)") }
                    }
                    if metric == .estimatedMax { Text("Epley estimate from sets of 1-12 reps. Warm-ups are excluded.").font(.caption).foregroundStyle(.secondary) }
                }.card()
                if !variants.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Variants").font(.title2.weight(.semibold))
                        ForEach(variants) { variant in
                            Button { variantEditor = variant } label: {
                                HStack { VStack(alignment: .leading, spacing: 4) { Text(variant.label).font(.headline); Text(planSummary(variant, unit: store.data.settings.unit)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "slider.horizontal.3") }
                            }.buttonStyle(.plain).padding(.vertical, 4)
                        }
                    }.card()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sessions").font(.title2.weight(.semibold))
                    ForEach(store.data.sessions.reversed().filter { session in session.startedAt >= since && session.exercises.contains { $0.exerciseID == exerciseID && (selectedVariant == nil || $0.variantID == selectedVariant) && $0.sets.contains { $0.completedAt != nil } } }) { session in
                        NavigationLink { SessionDetail(sessionID: session.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(session.startedAt, format: .dateTime.month(.abbreviated).day()); Spacer(); Text(session.name).foregroundStyle(.secondary) }
                                ForEach(session.exercises.filter { $0.exerciseID == exerciseID && (selectedVariant == nil || $0.variantID == selectedVariant) }) { item in
                                    Text(item.sets.filter { $0.completedAt != nil && $0.plan.kind != .warmup }.map { loggedSetSummary($0, unit: store.data.settings.unit) }.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                                    if !item.notes.isEmpty { Label(item.notes, systemImage: "note.text").font(.caption).foregroundStyle(.secondary) }
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }.card()
            }.padding(16)
        }.background(Palette.background(scheme)).navigationTitle(exercise?.name ?? "Progress").inlineTitle()
        .onAppear { if exercise?.mode == .cardio { metric = .duration } }
        .toolbar { Button("Edit") { editingExercise = true } }
        .sheet(isPresented: $editingExercise) { ExerciseEditor(initialExercise: exercise) { value in store.perform { d in if let index = d.exercises.firstIndex(where: { $0.id == value.id }) { d.exercises[index] = value } } }.sheetSize() }
        .sheet(item: $variantEditor) { VariantEditor(variant: $0).environmentObject(store).sheetSize() }
    }
    func filterChip(_ title: String, id: UUID?) -> some View {
        Button { selectedVariant = id } label: { Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(selectedVariant == id ? scheme == .dark ? Color.black : .white : .primary).background(selectedVariant == id ? Palette.tint(scheme) : Palette.secondary(scheme), in: Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(selectedVariant == id ? .isSelected : []).accessibilityIdentifier("progress.variant.\(title)")
    }
}

struct ChartDatum: Identifiable { let id: String; let date: Date; let value: Double; let label: String; let seriesID: String }
