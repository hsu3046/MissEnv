import Foundation
import XCTest
@testable import MissEnvCore

final class ProjectDiscoveryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MissEnvProjects-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    @discardableResult
    private func write(_ path: String, _ text: String = "") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testTwoUmbrellaFoldersCountTheirThreeActualProjects() throws {
        try write("work/web/package.json", "{}")
        try write("work/web/.env", "A=1")
        try write("work/api/pyproject.toml")
        try write("work/api/.env.local", "A=2")
        try write("personal/mac/Package.swift")
        try write("personal/mac/.env", "A=3")
        let result = ProjectDiscovery.discover(in: [root.appendingPathComponent("work"), root.appendingPathComponent("personal")])
        XCTAssertEqual(result.projects.map(\.name).sorted(), ["api", "mac", "web"])
        XCTAssertEqual(result.projects.count, 3)
        XCTAssertEqual(result.projects.first { $0.name == "mac" }!.files.count, 1)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testEnvVariantsAndNestedConfigBelongToOneProject() throws {
        try write("web/package.json", "{}")
        try write("web/.env", "A=1")
        try write("web/.env.local", "A=2")
        try write("web/config/.env.production", "A=3")
        let result = ProjectDiscovery.discover(in: [root])
        XCTAssertEqual(result.projects.count, 1)
        XCTAssertEqual(result.projects[0].files.map(\.relativePath), [".env", ".env.local", "config/.env.production"])
    }

    func testOverlappingAndAliasRootsDoNotDuplicateProjectsOrFiles() throws {
        try write("web/package.json", "{}")
        try write("web/.env", "A=1")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("web"))
        let first = ProjectDiscovery.discover(in: [root, root.appendingPathComponent("web"), alias])
        let second = ProjectDiscovery.discover(in: [root.appendingPathComponent("web"), root])
        XCTAssertEqual(first.projects.count, 1)
        XCTAssertEqual(first.projects[0].files.count, 1)
        XCTAssertEqual(first.projects.map(\.id), second.projects.map(\.id))
        XCTAssertEqual(first.projects[0].files[0].relativePath, ".env")
    }

    func testMonorepoFilesBelongToNearestProjectManifest() throws {
        try write("repo/package.json", "{}")
        try write("repo/.env", "A=root")
        try write("repo/apps/web/package.json", "{}")
        try write("repo/apps/web/config/.env.local", "A=web")
        try write("repo/apps/api/go.mod")
        try write("repo/apps/api/.env", "A=api")
        let result = ProjectDiscovery.discover(in: [root])
        XCTAssertEqual(result.projects.count, 3)
        XCTAssertEqual(result.projects.first { $0.name == "repo" }!.files.map(\.relativePath), [".env"])
        XCTAssertEqual(result.projects.first { $0.name == "web" }!.files.map(\.relativePath), ["config/.env.local"])
        XCTAssertEqual(result.projects.flatMap(\.files).count, 3)
    }

    func testGitDirectoryWorktreeFileAndXcodeBundleAreProjectMarkers() throws {
        try write("git-project/.git/HEAD", "ref: refs/heads/main")
        try write("worktree/.git", "gitdir: /example/git/worktrees/demo")
        try write("native/Example.xcodeproj/project.pbxproj")
        try write("git-project/.env", "A=1")
        try write("worktree/config/.env.local", "A=2")
        try write("native/.env.development", "A=3")
        // Metadata inside excluded directories must not create additional projects or files.
        try write("git-project/.git/.env", "A=ignored")
        try write("git-project/node_modules/dep/package.json", "{}")
        try write("git-project/node_modules/dep/.env", "A=ignored")
        let result = ProjectDiscovery.discover(in: [root])
        XCTAssertEqual(result.projects.map(\.name).sorted(), ["git-project", "native", "worktree"])
        XCTAssertEqual(result.projects.flatMap(\.files).count, 3)
        XCTAssertEqual(result.projects.first { $0.name == "worktree" }!.files.map(\.relativePath), ["config/.env.local"])
    }

    func testMarkerlessEnvFolderCountsOnceAndEmptyRootDoesNotCount() throws {
        XCTAssertTrue(ProjectDiscovery.discover(in: [root]).projects.isEmpty)
        try write("standalone/.env", "A=1")
        try write("standalone/.env.local", "A=2")
        let result = ProjectDiscovery.discover(in: [root])
        XCTAssertEqual(result.projects.map(\.name), ["standalone"])
        XCTAssertEqual(result.projects[0].files.count, 2)
    }

    func testMissingRootReportsWarningWithoutInventingProject() throws {
        let result = ProjectDiscovery.discover(in: [root.appendingPathComponent("missing")])
        XCTAssertTrue(result.projects.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testSymlinkManifestDoesNotCreatePhantomProject() throws {
        let target = try write("metadata.json", "{}")
        let folder = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("package.json"), withDestinationURL: target)
        XCTAssertTrue(ProjectDiscovery.discover(in: [root]).projects.isEmpty)
    }

    func testExampleFilteringHidesAllExampleOnlyProjects() throws {
        try write("marked/package.json", "{}")
        try write("marked/.env.example", "TEMPLATE_ONLY=1")
        try write("fallback/.env.example", "TEMPLATE_ONLY=2")
        let excluded = ProjectDiscovery.discover(in: [root])
        XCTAssertTrue(excluded.projects.isEmpty)
        let included = ProjectDiscovery.discover(in: [root], options: .init(includeExamples: true))
        XCTAssertEqual(included.projects.map(\.name).sorted(), ["fallback", "marked"])
        XCTAssertEqual(included.projects.flatMap(\.files).count, 2)
    }

    func testProjectsWithoutEnvFilesAreHiddenButTheirMarkersStillAssignOwnership() throws {
        try write("empty/Package.swift")
        try write("repo/package.json", "{}")
        try write("repo/apps/web/package.json", "{}")
        XCTAssertTrue(ProjectDiscovery.discover(in: [root]).projects.isEmpty)
        try write("repo/apps/web/config/.env.local", "A=1")
        let result = ProjectDiscovery.discover(in: [root])
        XCTAssertEqual(result.projects.map(\.name), ["web"])
        XCTAssertEqual(result.projects[0].files.map(\.relativePath), ["config/.env.local"])
    }
}
