import Foundation

public struct EnvEntry: Identifiable, Equatable, Sendable {
    public var id: Int { recordRange.location }
    public let key: String
    /// The original value literal, including quotes. No interpolation or execution occurs.
    public let value: String
    public let line: Int
    public let keyRange: NSRange
    public let valueRange: NSRange
    public let recordRange: NSRange
    public let comment: String
}

public struct EnvDiagnostic: Identifiable, Equatable, Sendable {
    public var id: String { "\(line):\(message)" }
    public let line: Int
    public let message: String
}

public enum EnvEditError: LocalizedError {
    case invalidKey, invalidValue, staleEntry
    public var errorDescription: String? {
        switch self {
        case .invalidKey: "변수명은 문자 또는 _로 시작하고, 문자·숫자·_·.·-만 사용할 수 있습니다."
        case .invalidValue: "값의 따옴표와 줄바꿈을 확인하세요. 여러 줄 값은 따옴표로 감싸야 합니다."
        case .staleEntry: "편집 중 문서가 바뀌었습니다. 변수를 다시 선택해 주세요."
        }
    }
}

public struct EnvDocument: Sendable {
    public let source: String
    public let entries: [EnvEntry]
    public let diagnostics: [EnvDiagnostic]
    public let duplicates: Set<String>
    public let conflictingDuplicates: Set<String>
    public var newline: String { source.contains("\r\n") ? "\r\n" : "\n" }
    public var reviewCount: Int { diagnostics.count + conflictingDuplicates.count }

    public init(_ source: String) {
        self.source = source
        let text = source as NSString
        // Coordinates always refer to the untouched source, in UTF-16 like NSTextView.
        let assignment = try! NSRegularExpression(pattern: #"^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*="#)
        var cursor = text.length > 0 && text.character(at: 0) == 0xFEFF ? 1 : 0
        var line = 1
        var entries: [EnvEntry] = []
        var diagnostics: [EnvDiagnostic] = []
        var pendingComments: [String] = []

        func lineEnd(from start: Int) -> Int {
            var end = start
            while end < text.length && text.character(at: end) != 10 && text.character(at: end) != 13 { end += 1 }
            return end
        }
        func afterNewline(_ end: Int) -> Int {
            guard end < text.length else { return end }
            return end + (text.character(at: end) == 13 && end + 1 < text.length && text.character(at: end + 1) == 10 ? 2 : 1)
        }

        while cursor < text.length {
            let end = lineEnd(from: cursor)
            let physical = NSRange(location: cursor, length: end - cursor)
            let lineText = text.substring(with: physical)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if trimmed.hasPrefix("#") { pendingComments.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) }
                else { pendingComments.removeAll() }
                cursor = afterNewline(end)
                line += 1
                continue
            }
            guard let match = assignment.firstMatch(in: source, range: physical) else {
                diagnostics.append(.init(line: line, message: "변수 할당 형식을 확인하세요."))
                pendingComments.removeAll()
                cursor = afterNewline(end)
                line += 1
                continue
            }
            let equalsEnd = NSMaxRange(match.range)
            var valueStart = equalsEnd
            while valueStart < end && (text.character(at: valueStart) == 32 || text.character(at: valueStart) == 9) { valueStart += 1 }
            // For an empty assignment, keep existing spaces as the comment's separator.
            if valueStart == end || text.character(at: valueStart) == 35 { valueStart = equalsEnd }
            var valueEnd = end
            var recordEnd = end
            var inlineComment = ""
            let quote = valueStart < end ? text.character(at: valueStart) : 0
            if quote == 34 || quote == 39 || quote == 96 {
                var scan = valueStart + 1
                var escaped = false
                var closing: Int?
                while scan < text.length {
                    let char = text.character(at: scan)
                    if char == quote && !escaped { closing = scan; break }
                    escaped = char == 92 && !escaped
                    scan += 1
                }
                guard let closing else {
                    diagnostics.append(.init(line: line, message: "닫히지 않은 따옴표가 있습니다."))
                    break
                }
                valueEnd = closing + 1
                recordEnd = lineEnd(from: valueEnd)
                let tail = text.substring(with: NSRange(location: valueEnd, length: recordEnd - valueEnd)).trimmingCharacters(in: .whitespaces)
                if tail.hasPrefix("#") { inlineComment = String(tail.dropFirst()).trimmingCharacters(in: .whitespaces) }
                else if !tail.isEmpty { diagnostics.append(.init(line: line, message: "따옴표 뒤에 예상하지 못한 내용이 있습니다.")) }
            } else {
                var scan = valueStart
                while scan < end {
                    if text.character(at: scan) == 35 {
                        valueEnd = scan
                        inlineComment = text.substring(with: NSRange(location: scan + 1, length: end - scan - 1)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                    scan += 1
                }
                while valueEnd > valueStart && (text.character(at: valueEnd - 1) == 32 || text.character(at: valueEnd - 1) == 9) { valueEnd -= 1 }
            }
            let recordNext = afterNewline(recordEnd)
            let keyRange = match.range(at: 1)
            let valueRange = NSRange(location: valueStart, length: valueEnd - valueStart)
            entries.append(.init(
                key: text.substring(with: keyRange), value: text.substring(with: valueRange), line: line,
                keyRange: keyRange, valueRange: valueRange,
                recordRange: NSRange(location: cursor, length: recordNext - cursor),
                comment: (pendingComments + (inlineComment.isEmpty ? [] : [inlineComment])).joined(separator: "\n")
            ))
            // Count the original physical newlines, including quoted multiline values.
            let consumed = text.substring(with: NSRange(location: cursor, length: recordNext - cursor))
            line += consumed.replacingOccurrences(of: "\r\n", with: "\n").filter { $0 == "\n" || $0 == "\r" }.count
            cursor = recordNext
            pendingComments.removeAll()
        }
        self.entries = entries
        self.diagnostics = diagnostics
        let grouped = Dictionary(grouping: entries, by: \.key).filter { $0.value.count > 1 }
        self.duplicates = Set(grouped.keys)
        self.conflictingDuplicates = Set(grouped.filter { _, declarations in
            Set(declarations.map { Self.plainValueIdentity($0.value) }).count > 1
        }.keys)
    }

    public static func plainValueIdentity(_ literal: String) -> String {
        // Ignore surrounding quotes only for plain literals. Expansion/escape syntax
        // can vary by loader, so retain it verbatim rather than evaluating values.
        guard literal.count >= 2, let quote = literal.first,
              quote == "\"" || quote == "'", literal.last == quote else { return literal }
        let inner = String(literal.dropFirst().dropLast())
        guard !inner.contains("\\"), !inner.contains("$"), !inner.contains("`") else { return literal }
        return inner
    }

    public func replacing(_ entry: EnvEntry, key: String, value: String) throws -> String {
        try Self.validate(key: key, value: value)
        guard entries.contains(entry) else { throw EnvEditError.staleEntry }
        let original = source as NSString
        // Literal splicing preserves every byte outside the exact assignment ranges.
        let withValue = original.replacingCharacters(in: entry.valueRange, with: value)
        return (withValue as NSString).replacingCharacters(in: entry.keyRange, with: key)
    }

    public func deleting(_ entry: EnvEntry) throws -> String {
        guard entries.contains(entry) else { throw EnvEditError.staleEntry }
        return (source as NSString).replacingCharacters(in: entry.recordRange, with: "")
    }

    public func adding(key: String, value: String) throws -> String {
        try Self.validate(key: key, value: value)
        let separator = source.isEmpty || source.hasSuffix("\n") || source.hasSuffix("\r") ? "" : newline
        return source + separator + key + "=" + value + newline
    }

    public static func validate(key: String, value: String) throws {
        guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil else { throw EnvEditError.invalidKey }
        let probe = EnvDocument("\(key)=\(value)\n")
        guard probe.diagnostics.isEmpty, probe.entries.count == 1, probe.entries[0].value == value else { throw EnvEditError.invalidValue }
    }
}

public enum EnvDifferenceKind: String, Sendable {
    case missing = "누락", extra = "추가", changed = "다름", same = "동일"
}

public struct EnvDifference: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let current: String?
    public let reference: String?
    public let kind: EnvDifferenceKind

    public static func compare(current: EnvDocument, reference: EnvDocument) -> [EnvDifference] {
        // Duplicate assignments remain visible in the editor; comparison uses the last assignment.
        let lhs = Dictionary(current.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let rhs = Dictionary(reference.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        return Set(lhs.keys).union(rhs.keys).sorted().map { key in
            let a = lhs[key], b = rhs[key]
            let kind: EnvDifferenceKind = a == nil ? .missing : b == nil ? .extra : a == b ? .same : .changed
            return .init(key: key, current: a, reference: b, kind: kind)
        }
    }
}
