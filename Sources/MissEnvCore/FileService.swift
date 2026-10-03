import Foundation

public enum FileServiceError: LocalizedError {
    case unsupportedEncoding, tooLarge, changedOnDisk, symbolicLink, notRegularFile
    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding: "UTF-8 형식의 파일만 편집할 수 있습니다. 원본은 변경하지 않았습니다."
        case .tooLarge: "2MB보다 큰 파일은 편집할 수 없습니다."
        case .changedOnDisk: "다른 앱에서 파일이 변경되었습니다. 원본을 다시 불러온 뒤 수정해 주세요."
        case .symbolicLink: "심볼릭 링크는 직접 편집하지 않습니다. 원본 폴더를 등록해 주세요."
        case .notRegularFile: "일반 파일만 편집할 수 있습니다."
        }
    }
}

public struct EnvFile: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let relativePath: String
    public init(url: URL, relativePath: String) { self.url = url; self.relativePath = relativePath }
    public var name: String { url.lastPathComponent }
    public var isExample: Bool { name.lowercased().split(separator: ".").contains("example") }
}

public struct EnvScanOptions: Sendable {
    public let includeExamples: Bool
    public init(includeExamples: Bool = false) { self.includeExamples = includeExamples }
}

public struct FileSnapshot: Sendable {
    public let data: Data
    public let text: String
    public let modified: Date
    public init(data: Data, text: String, modified: Date) { self.data = data; self.text = text; self.modified = modified }
}

public struct ScanResult: Sendable {
    public let files: [EnvFile]
    public let warnings: [String]
    public let projectRoots: [URL]
}

public enum FileService {
    public static let maximumSize = 2 * 1024 * 1024
    public static let excludedDirectories: Set<String> = [
        ".git", "node_modules", ".next", ".nuxt", ".build", "build", "dist", "DerivedData",
        ".venv", "venv", "vendor", "Pods", "Carthage", ".MissEnvBackups", ".turbo", ".cache"
    ]

    public static func scan(_ root: URL, options: EnvScanOptions = .init()) throws -> ScanResult {
        // /var and /private/var can identify the same macOS folder; enumerate and relativize against one canonical root.
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var warnings: [String] = []
        var files: [EnvFile] = []
        var projectRoots: Set<URL> = []
        // Hidden files must be included: .env and .env.local are the primary targets.
        guard let enumerator = FileManager.default.enumerator(at: canonicalRoot, includingPropertiesForKeys: keys, options: [], errorHandler: { url, _ in
            warnings.append("읽을 수 없는 경로: \(url.lastPathComponent)")
            return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        for case let url as URL in enumerator {
            let info = try url.resourceValues(forKeys: Set(keys))
            // Foundation does not traverse symlink directories. skipDescendants on a file would skip its parent's remaining entries.
            if info.isSymbolicLink == true { continue }
            let name = url.lastPathComponent
            let isProjectBundle = info.isDirectory == true && (name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace"))
            if name == ".git" || (info.isRegularFile == true && ProjectDiscovery.manifests.contains(name)) || isProjectBundle {
                projectRoots.insert(url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath())
            }
            if info.isDirectory == true {
                if isProjectBundle || excludedDirectories.contains(url.lastPathComponent) || enumerator.level > 12 { enumerator.skipDescendants() }
                continue
            }
            guard info.isRegularFile == true, name == ".env" || name.hasPrefix(".env.") else { continue }
            guard name != ".env.keys", !name.hasSuffix(".bak"), !name.hasSuffix(".backup"), !name.hasSuffix("~") else { continue }
            let canonicalFile = url.standardizedFileURL.resolvingSymlinksInPath()
            let relative = String(canonicalFile.path.dropFirst(canonicalRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let file = EnvFile(url: canonicalFile, relativePath: relative)
            // Filter before indexing so counts, search and comparison share one policy.
            guard options.includeExamples || !file.isExample else { continue }
            files.append(file)
        }
        return .init(files: files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }, warnings: warnings, projectRoots: projectRoots.sorted { $0.path < $1.path })
    }

    public static func read(_ url: URL) throws -> FileSnapshot {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isSymbolicLink != true else { throw FileServiceError.symbolicLink }
        guard values.isRegularFile == true else { throw FileServiceError.notRegularFile }
        guard (values.fileSize ?? 0) <= maximumSize else { throw FileServiceError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumSize else { throw FileServiceError.tooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw FileServiceError.unsupportedEncoding }
        // Foundation's encoding initializer consumes a UTF-8 BOM. Decode validated bytes verbatim instead.
        let text = String(decoding: data, as: UTF8.self)
        return .init(data: data, text: text, modified: values.contentModificationDate ?? .distantPast)
    }

    @discardableResult
    public static func save(_ text: String, to url: URL, expected: FileSnapshot) throws -> URL {
        let data = Data(text.utf8)
        guard data.count <= maximumSize else { throw FileServiceError.tooLarge }
        var coordinationError: NSError?
        var result: Result<URL, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            result = Result {
                let current = try read(coordinatedURL)
                guard current.data == expected.data else { throw FileServiceError.changedOnDisk }
                let manager = FileManager.default
                let backupFolder = coordinatedURL.deletingLastPathComponent().appendingPathComponent(".MissEnvBackups", isDirectory: true)
                try manager.createDirectory(at: backupFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let backup = backupFolder.appendingPathComponent("\(coordinatedURL.lastPathComponent).\(stamp).\(UUID().uuidString.prefix(8)).bak")
                try current.data.write(to: backup, options: .withoutOverwriting)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                // The staging file sits beside the original for atomic replacement on the same volume.
                let temporary = coordinatedURL.deletingLastPathComponent().appendingPathComponent(".missenv-\(UUID().uuidString).tmp")
                defer { if manager.fileExists(atPath: temporary.path) { try? manager.removeItem(at: temporary) } }
                try data.write(to: temporary, options: .withoutOverwriting)
                let attributes = try manager.attributesOfItem(atPath: coordinatedURL.path)
                try manager.setAttributes([.posixPermissions: attributes[.posixPermissions] ?? 0o600], ofItemAtPath: temporary.path)
                // Recheck after backup/staging, narrowing the window for non-coordinating editors.
                guard try read(coordinatedURL).data == expected.data else { throw FileServiceError.changedOnDisk }
                _ = try manager.replaceItemAt(coordinatedURL, withItemAt: temporary, backupItemName: nil, options: [])
                return backup
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
