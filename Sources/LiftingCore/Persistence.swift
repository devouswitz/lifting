import Foundation

public struct LoadResult {
    public var data: TrainingData
    public var recoveredBackup: Bool
}

public struct LocalRepository {
    public let url: URL
    public var backupURL: URL { url.appendingPathExtension("previous") }
    public init(url: URL) { self.url = url }
    public static func encode(_ data: TrainingData) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(data.validated())
    }
    public static func decode(_ bytes: Data) throws -> TrainingData {
        guard bytes.count <= 100_000_000 else { throw TrainingError.invalid("The backup is too large.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(TrainingData.self, from: bytes).validated()
    }
    public func load() throws -> LoadResult? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if FileManager.default.fileExists(atPath: backupURL.path) { return LoadResult(data: try Self.decode(Data(contentsOf: backupURL)), recoveredBackup: true) }
            return nil
        }
        do { return LoadResult(data: try Self.decode(Data(contentsOf: url)), recoveredBackup: false) }
        catch {
            guard let backup = try? Self.decode(Data(contentsOf: backupURL)) else { throw TrainingError.invalid("Local data could not be read. Your files were preserved. Import a valid backup to recover.") }
            return LoadResult(data: backup, recoveredBackup: true)
        }
    }
    public func save(_ data: TrainingData) throws {
        let bytes = try Self.encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let old = try? Data(contentsOf: url), (try? Self.decode(old)) != nil { try old.write(to: backupURL, options: .atomic) }
        try bytes.write(to: url, options: .atomic)
    }
    public static func csv(_ data: TrainingData) -> Data {
        func escape(_ value: String) -> String {
            var safe = value
            if let first = value.first, ["=", "+", "-", "@", "\t", "\r"].contains(String(first)) { safe = "'" + value }
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let format = ISO8601DateFormatter()
        var lines = ["date,workout,exercise,variant,variant_id,kind,weight_kg,reps,seconds,meters,rpe,notes"]
        for session in data.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in session.exercises {
                for set in exercise.sets where set.completedAt != nil {
                    var row: [String] = [format.string(from: session.startedAt), session.name, exercise.name, exercise.label, exercise.variantID.uuidString, set.plan.kind.rawValue]
                    row.append(set.weight.map { String($0) } ?? "")
                    row.append(set.reps.map { String($0) } ?? "")
                    row.append(set.seconds.map { String($0) } ?? "")
                    row.append(set.meters.map { String($0) } ?? "")
                    row.append(set.rpe.map { String($0) } ?? "")
                    row.append([exercise.recurringNotes, exercise.notes].filter { !$0.isEmpty }.joined(separator: "\n"))
                    lines.append(row.map(escape).joined(separator: ","))
                }
            }
        }
        return Data(lines.joined(separator: "\r\n").utf8)
    }
}
