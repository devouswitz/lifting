import Foundation

/// Input state for the quick keypad. Opening an existing value does not make it an explicit edit.
public struct NumericEntry: Equatable {
    public private(set) var text: String
    public private(set) var changed = false
    private var replacing = true
    public let maximum: Double
    public let integer: Bool

    public init(value: Double?, maximum: Double, integer: Bool) {
        text = value.map(Self.format) ?? ""
        self.maximum = maximum
        self.integer = integer
    }
    public var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    public var isValid: Bool {
        text.isEmpty || value.map { $0.isFinite && (0...maximum).contains($0) && (!integer || $0.rounded() == $0) } == true
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
        var next = replacing ? "" : text
        next += input
        guard next.count <= 14, next.filter({ $0 == "." }).count <= 1 else { return }
        if next.first == "." { next = "0" + next }
        while next.count > 1, next.first == "0", next.dropFirst().first != "." { next.removeFirst() }
        text = next; replacing = false; changed = true
    }
    public mutating func adjust(by delta: Double) {
        text = Self.format(min(maximum, max(0, (value ?? 0) + delta)))
        replacing = true; changed = true
    }
    private static func format(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}
