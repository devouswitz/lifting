import Foundation

/// A meaning that owns one color everywhere in the app.
public enum ColorRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case action, completed, warmup, technique, failure, rest, best, background, card, field
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .action: return "Action"
        case .completed: return "Completed"
        case .warmup: return "Warm-up"
        case .technique: return "Drop and MYO"
        case .failure: return "Failure"
        case .rest: return "Rest and time"
        case .best: return "Best"
        case .background: return "Background"
        case .card: return "Cards"
        case .field: return "Fields"
        }
    }
    public var detail: String {
        switch self {
        case .action: return "Buttons, links, selected tabs"
        case .completed: return "Checked sets and finished exercises"
        case .warmup: return "Warm-up set badges and headers"
        case .technique: return "Drop sets, MYO sets, supersets"
        case .failure: return "Failure sets"
        case .rest: return "Rest timer and cardio time"
        case .best: return "Best results in Progress"
        case .background: return "Screen background"
        case .card: return "Cards and grouped rows"
        case .field: return "Value fields in set tables"
        }
    }
    public var isNeutral: Bool { [.background, .card, .field].contains(self) }
    /// Apple system color values, tuned separately for each appearance.
    public func defaultHex(dark: Bool) -> UInt32 {
        switch self {
        case .action: return dark ? 0x0A84FF : 0x007AFF
        case .completed: return dark ? 0x30D158 : 0x28A745
        case .warmup: return dark ? 0xFF9F0A : 0xE07C00
        case .technique: return dark ? 0xBF5AF2 : 0x9B3FCF
        case .failure: return dark ? 0xFF453A : 0xE5372C
        case .rest: return dark ? 0x40C8E0 : 0x1A9AB5
        case .best: return dark ? 0xFFD60A : 0xC28F00
        case .background: return dark ? 0x000000 : 0xF2F2F7
        case .card: return dark ? 0x1C1C1E : 0xFFFFFF
        case .field: return dark ? 0x2C2C2E : 0xEEEEF2
        }
    }
}

/// User overrides for color roles, stored per appearance. Missing roles use the defaults.
public struct ColorTheme: Codable, Equatable, Sendable {
    public var light: [String: String] = [:]
    public var dark: [String: String] = [:]
    public init() {}
    enum CodingKeys: String, CodingKey { case light, dark }
    /// Tolerates missing appearances and drops unknown roles or malformed values, so one bad entry
    /// (for example from a newer app version) never blocks loading a library or backup.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let roles = Set(ColorRole.allCases.map(\.rawValue))
        func clean(_ values: [String: String]?) -> [String: String] { (values ?? [:]).filter { roles.contains($0.key) && Self.parse($0.value) != nil } }
        light = clean(try? c.decodeIfPresent([String: String].self, forKey: .light))
        dark = clean(try? c.decodeIfPresent([String: String].self, forKey: .dark))
    }

    public func hex(_ role: ColorRole, dark isDark: Bool) -> UInt32 {
        (isDark ? dark : light)[role.rawValue].flatMap(Self.parse) ?? role.defaultHex(dark: isDark)
    }
    public mutating func set(_ role: ColorRole, dark isDark: Bool, hex value: UInt32?) {
        let text = value.flatMap { $0 == role.defaultHex(dark: isDark) ? nil : Self.format($0) }
        if isDark { dark[role.rawValue] = text } else { light[role.rawValue] = text }
    }
    public func isCustomized(_ role: ColorRole, dark isDark: Bool) -> Bool { (isDark ? dark : light)[role.rawValue] != nil }
    public var isValid: Bool {
        let roles = Set(ColorRole.allCases.map(\.rawValue))
        return [light, dark].allSatisfy { $0.count <= roles.count && $0.allSatisfy { roles.contains($0.key) && Self.parse($0.value) != nil } }
    }
    public static func parse(_ text: String) -> UInt32? {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return value
    }
    public static func format(_ value: UInt32) -> String { String(format: "#%06X", value & 0xFFFFFF) }
}
