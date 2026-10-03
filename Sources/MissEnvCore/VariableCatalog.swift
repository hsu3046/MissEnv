import Foundation

public struct CatalogFile: Sendable {
    public let id: String
    public let projectID: String
    public let projectName: String
    public let relativePath: String
    public let document: EnvDocument

    public init(id: String, projectID: String, projectName: String, relativePath: String, document: EnvDocument) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.relativePath = relativePath
        self.document = document
    }
}

public struct VariableOccurrence: Identifiable, Sendable {
    public var id: String { "\(fileID):\(entry.id)" }
    public let fileID: String
    public let projectID: String
    public let projectName: String
    public let relativePath: String
    public let entry: EnvEntry
}

public struct CatalogValueGroup: Identifiable, Sendable {
    // Identity uses source coordinates, never a credential string.
    public var id: String { occurrences[0].id }
    public let value: String
    public let occurrences: [VariableOccurrence]
    public let projectCount: Int
    public let keys: [String]
    public var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct CatalogVariable: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let projectCount: Int
    public let occurrenceCount: Int
    public let values: [CatalogValueGroup]
    public var hasEmptyValue: Bool { values.contains(where: \.isEmpty) }
}

public struct VariableCatalog: Sendable {
    public let variables: [CatalogVariable]
    public let aliases: [CatalogValueGroup]

    public init(files: [CatalogFile]) {
        var visited = Set<String>()
        let occurrences = files.filter { visited.insert($0.id).inserted }.flatMap { file in
            file.document.entries.map {
                VariableOccurrence(fileID: file.id, projectID: file.projectID, projectName: file.projectName,
                                   relativePath: file.relativePath, entry: $0)
            }
        }.sorted(by: Self.occurrenceOrder)
        variables = Dictionary(grouping: occurrences, by: { $0.entry.key }).map { key, uses in
            CatalogVariable(key: key, projectCount: Set(uses.map(\.projectID)).count,
                            occurrenceCount: uses.count, values: Self.groupValues(uses))
        }.sorted {
            if $0.projectCount != $1.projectCount { return $0.projectCount > $1.projectCount }
            return $0.key < $1.key
        }
        // Same-name sharing is already visible above. Aliases require different names
        // across actual project identities, excluding commonplace scalar values.
        aliases = Self.groupValues(occurrences).filter {
            $0.projectCount > 1 && $0.keys.count > 1 && Self.isMeaningfulSharedValue($0.value)
        }.sorted {
            if $0.projectCount != $1.projectCount { return $0.projectCount > $1.projectCount }
            return $0.id < $1.id
        }
    }

    private static func groupValues(_ occurrences: [VariableOccurrence]) -> [CatalogValueGroup] {
        Dictionary(grouping: occurrences, by: { EnvDocument.plainValueIdentity($0.entry.value) }).map { value, uses in
            CatalogValueGroup(value: value, occurrences: uses, projectCount: Set(uses.map(\.projectID)).count,
                              keys: Set(uses.map { $0.entry.key }).sorted())
        }.sorted { $0.value < $1.value }
    }

    private static func occurrenceOrder(_ lhs: VariableOccurrence, _ rhs: VariableOccurrence) -> Bool {
        if lhs.projectName != rhs.projectName { return lhs.projectName < rhs.projectName }
        if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
        if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
        return lhs.entry.id < rhs.entry.id
    }

    private static func isMeaningfulSharedValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let generic: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "nil", "none", "undefined"]
        guard !generic.contains(trimmed.lowercased()) else { return false }
        if let number = Double(trimmed), number.isFinite { return false }
        // Include integer literals in hex/octal/binary in the numeric exclusions.
        let unsigned = trimmed.first == "+" || trimmed.first == "-" ? String(trimmed.dropFirst()) : trimmed
        let lower = unsigned.lowercased()
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
            let digits = lower.dropFirst(2)
            if !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.hexDigitValue.map { $0 < radix } == true }) { return false }
        }
        return true
    }
}
