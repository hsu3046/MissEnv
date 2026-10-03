import Foundation
import XCTest
@testable import MissEnvCore

final class FileServiceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MissEnvTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func write(_ relative: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testDiscoveryIncludesHiddenFilesAndNestedPackagesButExcludesArtifacts() throws {
        _ = try write(".env", "A=1")
        _ = try write(".env.local", "A=2")
        _ = try write("apps/web/.env.example", "A=")
        _ = try write("node_modules/pkg/.env", "A=ignored")
        _ = try write(".MissEnvBackups/.env", "A=backup")
        _ = try write(".env.local.bak", "A=backup")
        _ = try write(".env.keys", "PRIVATE_KEY=ignored")
        let scan = try FileService.scan(root, options: .init(includeExamples: true))
        XCTAssertEqual(Set(scan.files.map(\.relativePath)), [".env", ".env.local", "apps/web/.env.example"])
    }

    func testScanNeverFollowsSymlinkToOtherProject() throws {
        let actual = try write("real/.env", "A=1")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".env.local"), withDestinationURL: actual)
        XCTAssertEqual(try FileService.scan(root).files.count, 1)
        XCTAssertThrowsError(try FileService.read(root.appendingPathComponent(".env.local")))
    }

    func testExampleFilesExcludedByDefaultWithPreciseCaseInsensitiveTokens() throws {
        for name in [".env", ".env.local", ".env.example", ".env.local.example", ".env.example.production", ".env.ExAmPlE", ".env.example-service", ".env.sample"] {
            _ = try write(name, "DEMO=1")
        }
        let scan = try FileService.scan(root)
        XCTAssertEqual(Set(scan.files.map(\.name)), [".env", ".env.local", ".env.example-service", ".env.sample"])
    }

    func testIncludeExamplesOptionRestoresNestedExampleFiles() throws {
        _ = try write("web/.env", "DEMO=1")
        _ = try write("web/config/.env.local.example", "TEMPLATE_ONLY=1")
        let excluded = try FileService.scan(root)
        let included = try FileService.scan(root, options: .init(includeExamples: true))
        XCTAssertEqual(excluded.files.map(\.relativePath), ["web/.env"])
        XCTAssertEqual(Set(included.files.map(\.relativePath)), ["web/.env", "web/config/.env.local.example"])
    }

    func testSaveBacksUpExactOriginalAndPreservesFilePermissions() throws {
        let url = try write(".env", "\u{FEFF}# original\r\nA=old\r\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let snapshot = try FileService.read(url)
        let backup = try FileService.save("A=new\r\n", to: url, expected: snapshot)
        XCTAssertEqual(try FileService.read(url).text, "A=new\r\n")
        XCTAssertEqual(try Data(contentsOf: backup), snapshot.data)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o640)
        let backupPermissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(backupPermissions?.intValue, 0o600)
    }

    func testConcurrentExternalEditIsNotOverwritten() throws {
        let url = try write(".env", "A=old\n")
        let snapshot = try FileService.read(url)
        try Data("A=external\n".utf8).write(to: url)
        XCTAssertThrowsError(try FileService.save("A=my-edit\n", to: url, expected: snapshot)) { error in
            XCTAssertTrue(error is FileServiceError)
        }
        XCTAssertEqual(try FileService.read(url).text, "A=external\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".MissEnvBackups").path))
    }

    func testConsecutiveSavesProduceUniqueRecoverableBackups() throws {
        let url = try write(".env.local", "A=1\n")
        let first = try FileService.save("A=2\n", to: url, expected: FileService.read(url))
        let second = try FileService.save("A=3\n", to: url, expected: FileService.read(url))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "A=1\n")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "A=2\n")
    }

    func testRejectsNonUTF8WithoutModifyingIt() throws {
        let url = root.appendingPathComponent(".env")
        let binary = Data([0xFF, 0xFE, 0x00, 0xC1])
        try binary.write(to: url)
        XCTAssertThrowsError(try FileService.read(url))
        XCTAssertEqual(try Data(contentsOf: url), binary)
    }

    func testUTF8BOMRoundTripPreservesOriginalBytes() throws {
        let url = try write(".env", "\u{FEFF}# 한글 👋\r\nA=1\r\n")
        let snapshot = try FileService.read(url)
        XCTAssertEqual(Data(snapshot.text.utf8), snapshot.data)
        let doc = EnvDocument(snapshot.text)
        let next = try doc.replacing(doc.entries[0], key: "A", value: "2")
        _ = try FileService.save(next, to: url, expected: snapshot)
        XCTAssertEqual(try Data(contentsOf: url), Data("\u{FEFF}# 한글 👋\r\nA=2\r\n".utf8))
    }

    func testRejectsOversizedFile() throws {
        let url = root.appendingPathComponent(".env")
        try Data(repeating: 65, count: FileService.maximumSize + 1).write(to: url)
        XCTAssertThrowsError(try FileService.read(url))
    }

    func testDirectoryNamedEnvIsNotAFile() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".env"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try FileService.read(root.appendingPathComponent(".env")))
    }
}
