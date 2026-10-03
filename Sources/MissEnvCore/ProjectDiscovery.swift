import Foundation

public struct DiscoveredProject: Identifiable, Sendable {
    // Canonical paths keep identities stable across refreshes and overlapping scan folders.
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public let url: URL
    public let files: [EnvFile]
}

public struct ProjectDiscoveryResult: Sendable {
    public let projects: [DiscoveredProject]
    public let warnings: [String]
}

public enum ProjectDiscovery {
    public static let manifests: Set<String> = [
        "package.json", "Package.swift", "pyproject.toml", "setup.py", "setup.cfg",
        "Cargo.toml", "go.mod", "pom.xml", "build.gradle", "build.gradle.kts",
        "composer.json", "Gemfile", "mix.exs", "pubspec.yaml", "CMakeLists.txt"
    ]

    public static func discover(in roots: [URL], options: EnvScanOptions = .init()) -> ProjectDiscoveryResult {
        var markers: Set<URL> = []
        var files: [String: EnvFile] = [:]
        var warnings: [String] = []
        let canonicalRoots = Set(roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        for root in canonicalRoots.sorted(by: { $0.path < $1.path }) {
            do {
                let scan = try FileService.scan(root, options: options)
                markers.formUnion(scan.projectRoots)
                for file in scan.files { files[file.id] = file }
                warnings.append(contentsOf: scan.warnings.map { "\(root.lastPathComponent): \($0)" })
            } catch {
                warnings.append("\(root.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // The nearest manifest/Git root owns nested config files. Markerless folders
        // with env files remain usable. Only projects owning visible env files are listed.
        var grouped: [URL: [EnvFile]] = [:]
        for file in files.values {
            var ancestor = file.url.deletingLastPathComponent()
            var owner: URL?
            while true {
                if markers.contains(ancestor) { owner = ancestor; break }
                if ancestor.path == "/" { break }
                ancestor.deleteLastPathComponent()
            }
            let projectRoot = owner ?? file.url.deletingLastPathComponent()
            let relative = String(file.url.path.dropFirst(projectRoot.path == "/" ? 1 : projectRoot.path.count + 1))
            grouped[projectRoot, default: []].append(.init(url: file.url, relativePath: relative))
        }
        let projects = grouped.map { root, files in
            DiscoveredProject(url: root, files: files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending })
        }.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return .init(projects: projects, warnings: Array(Set(warnings)).sorted())
    }
}
