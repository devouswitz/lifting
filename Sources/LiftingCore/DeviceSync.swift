import Foundation

public struct SyncRevision: Codable, Equatable, Comparable, Sendable {
    public var counter: Int64
    public var device: UUID
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.counter == rhs.counter ? lhs.device.uuidString < rhs.device.uuidString : lhs.counter < rhs.counter }
}

public struct SyncRecord: Codable, Equatable, Sendable {
    public var revision: SyncRevision
    public var payload: Data?
}

/// Each device writes only its own replica. Tombstones prevent old offline copies
/// from resurrecting deleted records. Whole records resolve by logical revision.
public struct DeviceSyncState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var deviceID: UUID
    public var clock: Int64 = 0
    public var records: [String: SyncRecord] = [:]
    public init(deviceID: UUID = UUID()) { self.deviceID = deviceID }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .millisecondsSince1970; return encoder
    }
    private static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder }
    private static func payloads(_ data: TrainingData) throws -> [String: Data] {
        let encoder = encoder(); var result: [String: Data] = [:]
        func add<T: Encodable & Identifiable>(_ items: [T], kind: String) throws where T.ID == UUID {
            for item in items { result["\(kind)/\(item.id.uuidString)"] = try encoder.encode(item) }
        }
        try add(data.exercises, kind: "exercise"); try add(data.variants, kind: "variant")
        try add(data.routines, kind: "routine"); try add(data.programs, kind: "program"); try add(data.withoutHealthData.sessions, kind: "session")
        try add(data.warmupPresets, kind: "warmup"); try add(data.customSetTypes, kind: "settype")
        for link in data.historyImports { result["import/\(link.sourceVariantID.uuidString)"] = try encoder.encode(link) }
        return result
    }
    public mutating func capture(_ data: TrainingData) throws {
        _ = try data.validated()
        let payloads = try Self.payloads(data)
        let changed = Set(payloads.keys).union(records.keys).filter { records[$0]?.payload != payloads[$0] }
        guard !changed.isEmpty else { return }
        guard clock < Int64.max - 1 else { throw TrainingError.invalid("Sync revision limit reached.") }
        clock += 1
        for key in changed { records[key] = SyncRecord(revision: SyncRevision(counter: clock, device: deviceID), payload: payloads[key]) }
    }
    public mutating func merge(_ incoming: [DeviceSyncState], into local: TrainingData) throws -> TrainingData {
        var next = self
        for remote in incoming {
            guard remote.version == 1, remote.clock >= 0, remote.clock < Int64.max - 1, remote.records.count <= 500_000 else { throw TrainingError.invalid("Unsupported or oversized sync file.") }
            next.clock = max(next.clock, remote.clock)
            for (key, record) in remote.records {
                guard record.revision.counter >= 0, record.revision.counter <= remote.clock else { throw TrainingError.invalid("Invalid sync revision.") }
                if let current = next.records[key] {
                    if current.revision == record.revision, current.payload != record.payload { throw TrainingError.invalid("Conflicting sync revisions. Local data was preserved.") }
                    if current.revision < record.revision { next.records[key] = record }
                } else { next.records[key] = record }
            }
        }
        let decoder = Self.decoder(); var result = local
        func values<T: Decodable & Identifiable>(_ kind: String, as type: T.Type) throws -> [T] where T.ID == UUID {
            try next.records.keys.sorted().filter { $0.hasPrefix(kind + "/") }.compactMap { key in
                guard let payload = next.records[key]?.payload else { return nil }
                let value = try decoder.decode(type, from: payload)
                guard key == "\(kind)/\(value.id.uuidString)" else { throw TrainingError.invalid("Sync record identity mismatch.") }
                return value
            }
        }
        let allowed = ["exercise", "variant", "routine", "program", "session", "import", "warmup", "settype"]
        guard next.records.keys.allSatisfy({ key in let parts = key.split(separator: "/"); return parts.count == 2 && allowed.contains(String(parts[0])) && UUID(uuidString: String(parts[1])) != nil }) else { throw TrainingError.invalid("Unknown sync record.") }
        result.exercises = try values("exercise", as: Exercise.self); result.variants = try values("variant", as: Variant.self)
        result.routines = try values("routine", as: Routine.self); result.programs = try values("program", as: TrainingProgram.self)
        result.warmupPresets = try values("warmup", as: WarmupPreset.self)
        result.customSetTypes = try values("settype", as: CustomSetType.self)
        // Apple Health values never travel through the shared folder; keep this device's own.
        let health = Dictionary(local.sessions.compactMap { session in session.health.map { (session.id, $0) } }, uniquingKeysWith: { first, _ in first })
        result.sessions = try values("session", as: Session.self).map { session in var value = session; value.health = health[session.id]; return value }.sorted { $0.startedAt < $1.startedAt }
        result.historyImports = try next.records.keys.sorted().filter { $0.hasPrefix("import/") }.compactMap { key in
            guard let payload = next.records[key]?.payload else { return nil }
            let value = try decoder.decode(HistoryImportLink.self, from: payload)
            guard key == "import/\(value.sourceVariantID.uuidString)" else { throw TrainingError.invalid("Sync import identity mismatch.") }; return value
        }
        if result.activeProgramID.flatMap(result.program) == nil { result.activeProgramID = result.programs.first?.id }
        // A mixed concurrent delete/edit can break a reference. Reject that merge
        // atomically instead of discarding a workout or silently repairing history.
        do { result = try result.validated() }
        catch { throw TrainingError.invalid("Sync needs review because devices edited related records. All device copies and local data were preserved.") }
        self = next
        return result
    }
    public func encoded() throws -> Data { try Self.encoder().encode(self) }
    public static func decode(_ bytes: Data) throws -> DeviceSyncState {
        guard bytes.count <= 100_000_000 else { throw TrainingError.invalid("Sync file is too large.") }
        let state = try decoder().decode(Self.self, from: bytes)
        guard state.version == 1, state.clock >= 0, state.clock < Int64.max - 1, state.records.count <= 500_000,
              state.records.values.allSatisfy({ $0.revision.counter >= 0 && $0.revision.counter <= state.clock }) else { throw TrainingError.invalid("Unsupported or invalid sync file.") }
        return state
    }
}
