import Foundation

public enum CSVCodec {
    public static func parse(_ data: Data) throws -> [[String]] {
        guard data.count <= 25_000_000, var text = String(data: data, encoding: .utf8) else { throw TrainingError.invalid("Use a UTF-8 CSV smaller than 25 MB.") }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let header = text.prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
        let separator: UInt8 = !header.contains(",") && header.contains(";") ? 59 : 44
        let bytes = Array(text.utf8)
        var rows: [[String]] = [], row: [String] = [], field: [UInt8] = []
        var quoted = false, closedQuote = false, i = 0
        func value() -> String { String(decoding: field, as: UTF8.self) }
        while i < bytes.count {
            let byte = bytes[i]
            if quoted {
                if byte == 34 {
                    if i + 1 < bytes.count && bytes[i + 1] == 34 { field.append(34); i += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(byte) }
            } else if byte == separator {
                row.append(value()); field.removeAll(keepingCapacity: true); closedQuote = false
            } else if byte == 10 || byte == 13 {
                if byte == 13, i + 1 < bytes.count, bytes[i + 1] == 10 { i += 1 }
                row.append(value()); field.removeAll(keepingCapacity: true); closedQuote = false
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row.removeAll(keepingCapacity: true)
            } else if byte == 34 {
                guard field.isEmpty && !closedQuote else { throw TrainingError.invalid("Invalid quote near CSV row \(rows.count + 1).") }
                quoted = true
            } else if closedQuote {
                guard byte == 32 || byte == 9 else { throw TrainingError.invalid("Unexpected text after a quote near CSV row \(rows.count + 1).") }
            } else { field.append(byte) }
            guard rows.count <= 50_000, row.count <= 128, field.count <= 1_000_000 else { throw TrainingError.invalid("The CSV has too many rows, columns, or oversized fields.") }
            i += 1
        }
        guard !quoted else { throw TrainingError.invalid("The CSV contains an unclosed quote.") }
        if !row.isEmpty || !field.isEmpty || closedQuote { row.append(value()); if row.contains(where: { !$0.isEmpty }) { rows.append(row) } }
        guard let first = rows.first, !first.isEmpty, rows.allSatisfy({ $0.count == first.count }) else { throw TrainingError.invalid("CSV rows must have the same number of columns as the header.") }
        return rows
    }

    public static func render(_ rows: [[String]]) -> Data {
        func escape(_ text: String) -> String {
            let first = text.first(where: { !$0.isWhitespace })
            let protected = text.first == "'" || first.map({ "=+-@".contains($0) }) == true || text.first == "\t" || text.first == "\r" ? "'" + text : text
            return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return Data(rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n").utf8)
    }

    public static func unprotect(_ text: String) -> String {
        guard text.first == "'" else { return text }
        let remaining = String(text.dropFirst())
        let first = remaining.first(where: { !$0.isWhitespace })
        if remaining.first == "'" || first.map({ "=+-@".contains($0) }) == true || remaining.first == "\t" || remaining.first == "\r" { return remaining }
        return text
    }
}

struct CSVRow {
    let values: [String: String]
    let number: Int
    func text(_ key: String, default fallback: String = "") -> String { CSVCodec.unprotect(values[key] ?? fallback) }
    func double(_ key: String, default fallback: Double? = nil, maximum: Double = 10_000_000) throws -> Double? {
        let value = text(key).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return fallback }
        guard let parsed = Double(value.replacingOccurrences(of: ",", with: ".")), parsed.isFinite, parsed >= 0, parsed <= maximum else { throw TrainingError.invalid("Invalid \(key) on CSV row \(number). Use a number from 0 to \(maximum.formatted(.number.grouping(.never))).") }
        return parsed
    }
    func int(_ key: String, default fallback: Int? = nil) throws -> Int? {
        guard let value = try double(key, default: fallback.map(Double.init)) else { return nil }
        guard value.rounded() == value else { throw TrainingError.invalid("\(key) must be a whole number on row \(number).") }
        return Int(value)
    }
    func uuid(_ key: String) throws -> UUID? {
        let value = text(key)
        if value.isEmpty { return nil }
        guard let id = UUID(uuidString: value) else { throw TrainingError.invalid("Invalid \(key) on CSV row \(number).") }
        return id
    }
    func bool(_ key: String) throws -> Bool {
        switch text(key).lowercased() { case "", "false", "0", "no": return false; case "true", "1", "yes": return true; default: throw TrainingError.invalid("Invalid \(key) on CSV row \(number).") }
    }
}
