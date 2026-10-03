import XCTest
@testable import MissEnvCore

final class VariableCatalogTests: XCTestCase {
    private func file(_ id: String, project: String, name: String? = nil, source: String) -> CatalogFile {
        .init(id: id, projectID: project, projectName: name ?? project, relativePath: id,
              document: EnvDocument(source))
    }

    func testProjectCountUsesIdentityInsteadOfFileCountOrProjectName() {
        let catalog = VariableCatalog(files: [
            file("/a/.env", project: "/a", name: "web", source: "API=https://fixture.invalid\n"),
            file("/a/.env.local", project: "/a", name: "web", source: "API=https://fixture.invalid\n"),
            file("/b/.env", project: "/b", name: "web", source: "API=https://fixture.invalid\n")
        ])
        XCTAssertEqual(catalog.variables.first?.projectCount, 2)
        XCTAssertEqual(catalog.variables.first?.occurrenceCount, 3)
        XCTAssertEqual(catalog.variables.first?.values.count, 1)
        XCTAssertEqual(catalog.variables.first?.values.first?.projectCount, 2)
    }

    func testOverlappingScanFilesAreNotCountedTwice() {
        let input = file("/web/.env", project: "/web", source: "API=fake-token\n")
        let catalog = VariableCatalog(files: [input, input])
        XCTAssertEqual(catalog.variables.first?.occurrenceCount, 1)
    }

    func testConflictingDuplicatesRemainIndividuallyNavigable() {
        let input = file("/web/.env", project: "/web", source: "# fixture\nAPI=first\nAPI=second\nAPI=first\n")
        let variable = VariableCatalog(files: [input]).variables[0]
        XCTAssertEqual(variable.projectCount, 1)
        XCTAssertEqual(variable.values.count, 2)
        let uses = variable.values.flatMap(\.occurrences).sorted { $0.entry.line < $1.entry.line }
        XCTAssertEqual(uses.map { $0.entry.line }, [2, 3, 4])
        XCTAssertEqual(Set(uses.map(\.id)).count, 3)
        XCTAssertEqual(uses.map(\.entry), input.document.entries)
    }

    func testCaseSensitiveNamesAndValuesArePreserved() {
        let catalog = VariableCatalog(files: [
            file("a", project: "a", source: "API=Value\napi=Value\n"),
            file("b", project: "b", source: "API=value\n")
        ])
        XCTAssertEqual(catalog.variables.map(\.key), ["API", "api"])
        XCTAssertEqual(catalog.variables[0].values.map(\.value), ["Value", "value"])
        XCTAssertTrue(catalog.aliases.isEmpty)
    }

    func testPlainQuotesGroupTogetherButRetainOriginalEntrySyntax() {
        let catalog = VariableCatalog(files: [
            file("a", project: "a", source: "API=\"fake-value\"\n"),
            file("b", project: "b", source: "TOKEN='fake-value'\n")
        ])
        XCTAssertEqual(catalog.aliases.count, 1)
        XCTAssertEqual(catalog.aliases[0].value, "fake-value")
        XCTAssertEqual(catalog.aliases[0].keys, ["API", "TOKEN"])
        XCTAssertEqual(catalog.aliases[0].occurrences.map { $0.entry.value }, ["\"fake-value\"", "'fake-value'"])
    }

    func testExpansionEscapeAndInnerWhitespaceAreNotNormalized() {
        let catalog = VariableCatalog(files: [
            file("a", project: "a", source: "DOLLAR=\"$TOKEN\"\nSPACE=' text '\nSLASH='a\\nb'\n"),
            file("b", project: "b", source: "OTHER=$TOKEN\nOTHER_SPACE=text\nOTHER_SLASH=\"a\\nb\"\n")
        ])
        XCTAssertTrue(catalog.aliases.isEmpty)
    }

    func testAliasesRequireDifferentNamesAndMultipleProjects() {
        let sameName = VariableCatalog(files: [
            file("a", project: "a", source: "API=fake-value\n"),
            file("b", project: "b", source: "API=fake-value\n")
        ])
        XCTAssertTrue(sameName.aliases.isEmpty)
        let oneProject = VariableCatalog(files: [
            file("a", project: "a", source: "API=fake-value\n"),
            file("b", project: "a", source: "TOKEN=fake-value\n")
        ])
        XCTAssertTrue(oneProject.aliases.isEmpty)
    }

    func testGenericValuesAreOnlyExcludedFromAliases() {
        let literals = ["", "''", "' '", "true", "'FALSE'", "yes", "NO", "on", "off", "null", "nil", "none", "undefined",
                        "0", "-42", "+2.5", "1e3", "0xFF", "-0o17", "0b101"]
        for literal in literals {
            let catalog = VariableCatalog(files: [
                file("a", project: "a", source: "FIRST=\(literal)\n"),
                file("b", project: "b", source: "SECOND=\(literal)\n")
            ])
            XCTAssertEqual(catalog.variables.count, 2)
            XCTAssertTrue(catalog.aliases.isEmpty)
        }
    }

    func testEmptyValuesAndMultilineUnicodeLocations() {
        let catalog = VariableCatalog(files: [
            file("a", project: "a", source: "EMPTY=\nCERT='한글\n👋'\nAFTER=fake\n"),
            file("b", project: "b", source: "EMPTY=filled\nOTHER_CERT=\"한글\n👋\"\n")
        ])
        let empty = catalog.variables.first { $0.key == "EMPTY" }
        XCTAssertEqual(empty?.hasEmptyValue, true)
        XCTAssertEqual(empty?.values.count, 2)
        XCTAssertEqual(catalog.aliases.first?.value, "한글\n👋")
        XCTAssertEqual(catalog.variables.first { $0.key == "AFTER" }?.values[0].occurrences[0].entry.line, 4)
    }

    func testEmptyCatalogAndSharedFirstOrdering() {
        XCTAssertTrue(VariableCatalog(files: []).variables.isEmpty)
        XCTAssertTrue(VariableCatalog(files: []).aliases.isEmpty)
        let catalog = VariableCatalog(files: [
            file("a", project: "a", source: "Z_SHARED=fake\nA_SINGLE=one\nB_SHARED=fake\n"),
            file("b", project: "b", source: "Z_SHARED=fake\nB_SHARED=fake\n")
        ])
        XCTAssertEqual(catalog.variables.map(\.key), ["B_SHARED", "Z_SHARED", "A_SINGLE"])
    }
}
