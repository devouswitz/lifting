import Foundation

/// Input state for the quick keypad. Opening an existing value does not make it an explicit edit.
public struct NumericEntry: Equatable {
    public private(set) var text: String
    public private(set) var changed = false
    private var replacing = true
    public let maximum: Double
    public let integer: Bool
    /// Allows a leading minus, for assisted bodyweight loads.
    public let signed: Bool

    public init(value: Double?, maximum: Double, integer: Bool, signed: Bool = false) {
        text = value.map(Self.format) ?? ""
        self.maximum = maximum
        self.integer = integer
        self.signed = signed
    }
    public var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    public var isValid: Bool {
        text.isEmpty || value.map { $0.isFinite && ((signed ? -maximum : 0)...maximum).contains($0) && (!integer || $0.rounded() == $0) } == true
    }
    public mutating func toggleSign() {
        guard signed else { return }
        text = text.hasPrefix("-") ? String(text.dropFirst()) : "-" + (text.isEmpty ? "0" : text)
        if text == "0" { text = "" }
        changed = true
    }
    public mutating func select() { replacing = true }
    public mutating func clear() { text = ""; replacing = true; changed = true }
    public mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
        replacing = false; changed = true
    }
    public mutating func insert(_ input: String) {
        let input = input.replacingOccurrences(of: ",", with: ".")
        guard !input.isEmpty, input.allSatisfy({ "0123456789".contains($0) || (!integer && $0 == ".") }) else { return }
        let negative = signed && text.hasPrefix("-")
        var next = replacing ? "" : String(text.drop { $0 == "-" })
        next += input
        guard next.count <= 14, next.filter({ $0 == "." }).count <= 1 else { return }
        if next.first == "." { next = "0" + next }
        while next.count > 1, next.first == "0", next.dropFirst().first != "." { next.removeFirst() }
        text = (negative ? "-" : "") + next; replacing = false; changed = true
    }
    public mutating func adjust(by delta: Double) {
        text = Self.format(min(maximum, max(signed ? -maximum : 0, (value ?? 0) + delta)))
        replacing = true; changed = true
    }
    private static func format(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}

/// Durations typed like a microwave timer: digits fill from the right, so 1, 3, 0 reads 1:30.
public struct DurationEntry: Equatable {
    public private(set) var digits: String
    public private(set) var changed = false
    private var replacing = true
    public let maximum: Double

    public init(seconds: Double?, maximum: Double = 86400) {
        self.maximum = maximum
        digits = seconds.map(Self.digits) ?? ""
    }
    /// Seconds, or nil when empty. Positions are hours, minutes, and seconds; 90 seconds may be typed as 1:30 or 0:90.
    public var seconds: Double? {
        guard !digits.isEmpty, let raw = Int(digits) else { return nil }
        return Double(raw / 10000 * 3600 + raw / 100 % 100 * 60 + raw % 100)
    }
    public var isValid: Bool { seconds.map { $0 <= maximum } ?? true }
    public var text: String {
        guard let raw = Int(digits.isEmpty ? "0" : digits) else { return "" }
        let hours = raw / 10000, minutes = raw / 100 % 100, seconds = raw % 100
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
    public mutating func insert(_ input: String) {
        guard !input.isEmpty, input.allSatisfy(\.isNumber) else { return }
        var next = (replacing ? "" : digits) + input
        while next.count > 1, next.first == "0" { next.removeFirst() }
        guard next.count <= 6 else { return }
        digits = next; replacing = false; changed = true
    }
    public mutating func backspace() {
        if !digits.isEmpty { digits.removeLast() }
        replacing = false; changed = true
    }
    public mutating func clear() { digits = ""; replacing = true; changed = true }
    public mutating func set(_ seconds: Double) { digits = Self.digits(min(maximum, max(0, seconds))); replacing = true; changed = true }
    public mutating func adjust(by delta: Double) { set((seconds ?? 0) + delta) }
    private static func digits(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        let hours = value / 3600, minutes = value % 3600 / 60, rest = value % 60
        let raw = hours * 10000 + minutes * 100 + rest
        return raw == 0 ? "0" : String(raw)
    }
}
