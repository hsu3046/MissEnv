import Foundation
import XCTest
@testable import MissEnvCore

final class EnvDocumentTests: XCTestCase {
    func testExactSplicePreservesBOMCRLFCommentsSpacingAndExport() throws {
        let text = "\u{FEFF}# 설정 👋\r\n\r\n  export API_KEY = \"old#value\"  # keep this\r\nOTHER='한글'\r\n"
        let document = EnvDocument(text)
        XCTAssertEqual(document.entries.count, 2)
        XCTAssertTrue(document.diagnostics.isEmpty)
        let changed = try document.replacing(document.entries[0], key: "API_TOKEN", value: "\"$& $1 $$ 새 값\"")
        XCTAssertEqual(changed, "\u{FEFF}# 설정 👋\r\n\r\n  export API_TOKEN = \"$& $1 $$ 새 값\"  # keep this\r\nOTHER='한글'\r\n")
    }

    func testMultilineQuotedValuesAreOneRecord() throws {
        let text = "# certificate\nCERT=\"line one\nline two 👋\" # trailing\nAFTER=ok\n"
        let doc = EnvDocument(text)
        XCTAssertEqual(doc.entries.map(\.key), ["CERT", "AFTER"])
        XCTAssertEqual(doc.entries[1].line, 4)
        XCTAssertEqual(doc.entries[0].comment, "certificate\ntrailing")
        XCTAssertEqual(try doc.replacing(doc.entries[0], key: "CERT", value: "'new\nmultiline'"), "# certificate\nCERT='new\nmultiline' # trailing\nAFTER=ok\n")
    }

    func testEscapedQuotesDoNotEndValue() {
        let doc = EnvDocument(#"JSON="{\"a\":\"b\"}" # meta"# + "\nNEXT=yes\n")
        XCTAssertEqual(doc.entries.count, 2)
        XCTAssertTrue(doc.diagnostics.isEmpty)
        XCTAssertEqual(doc.entries[0].comment, "meta")
    }

    func testBacktickQuotedAndHashValues() {
        let doc = EnvDocument("A=`one\ntwo#three`\nB=hello#comment\nC='a#b'\n")
        XCTAssertEqual(doc.entries.map(\.value), ["`one\ntwo#three`", "hello", "'a#b'"])
        XCTAssertTrue(doc.diagnostics.isEmpty)
    }

    func testEmptyValueBeforeCommentPreservesSpace() throws {
        let doc = EnvDocument("EMPTY=  # keep\n")
        XCTAssertEqual(doc.entries.first?.value, "")
        XCTAssertEqual(try doc.replacing(doc.entries[0], key: "EMPTY", value: "filled"), "EMPTY=filled  # keep\n")
    }

    func testDeletingDuplicateTargetsExactSecondOccurrence() throws {
        let text = "A=first\n# keep comment\nA=second\n\n# section\nB=third\n"
        let doc = EnvDocument(text)
        XCTAssertEqual(doc.duplicates, ["A"])
        XCTAssertEqual(try doc.deleting(doc.entries[1]), "A=first\n# keep comment\n\n# section\nB=third\n")
    }

    func testDeleteMultilineStopsAtNextRecordAndKeepsSection() throws {
        let doc = EnvDocument("A='one\ntwo'\n# next section\nB=three\n")
        XCTAssertEqual(try doc.deleting(doc.entries[0]), "# next section\nB=three\n")
    }

    func testAddingRespectsLineEndingAndMissingFinalNewline() throws {
        XCTAssertEqual(try EnvDocument("A=1\r\nB=2").adding(key: "C", value: "3"), "A=1\r\nB=2\r\nC=3\r\n")
        XCTAssertEqual(try EnvDocument("").adding(key: "C", value: ""), "C=\n")
    }

    func testMalformedLinesRetainedAndReported() {
        let source = "A=valid\nnot a variable\nB=\"unclosed\nC=next\n"
        let doc = EnvDocument(source)
        XCTAssertEqual(doc.source, source)
        XCTAssertEqual(doc.diagnostics.count, 2)
        XCTAssertEqual(doc.entries.map(\.key), ["A"])
    }

    func testValueValidationPreventsAssignmentInjectionAndCommentLoss() {
        XCTAssertThrowsError(try EnvDocument.validate(key: "A\nB", value: "x"))
        XCTAssertThrowsError(try EnvDocument.validate(key: "A", value: "x\nB=y"))
        XCTAssertThrowsError(try EnvDocument.validate(key: "A", value: "x#hidden"))
        XCTAssertThrowsError(try EnvDocument.validate(key: "A", value: "\"unterminated"))
        XCTAssertNoThrow(try EnvDocument.validate(key: "A", value: "\"x#literal\""))
        XCTAssertNoThrow(try EnvDocument.validate(key: "A", value: "'x\ny'"))
    }

    func testStaleEntryRejectedInsteadOfChangingAnotherRange() throws {
        let old = EnvDocument("A=one\n").entries[0]
        XCTAssertThrowsError(try EnvDocument("A=two\n").replacing(old, key: "A", value: "three"))
    }

    func testDiffDirectionsAndLastAssignment() {
        let current = EnvDocument("A=1\nB=old\nB=new\nD=4\n")
        let reference = EnvDocument("A=1\nB=old\nC=3\n")
        let changes = EnvDifference.compare(current: current, reference: reference)
        XCTAssertEqual(changes.map(\.key), ["A", "B", "C", "D"])
        XCTAssertEqual(changes.map(\.kind), [.same, .changed, .missing, .extra])
        XCTAssertEqual(changes[1].current, "new")
    }

    func testCommonValuesAcrossDifferentKeysDoNotProduceDuplicateWarnings() {
        let doc = EnvDocument("A=true\nB=true\nC=false\nD=false\nE=0\nF=0\nG=\nH=\n")
        XCTAssertTrue(doc.duplicates.isEmpty)
        XCTAssertTrue(doc.conflictingDuplicates.isEmpty)
        XCTAssertEqual(doc.reviewCount, 0)
    }

    func testSameKeyAndSameValueRemainSeparateWithoutWarning() throws {
        let source = "FLAG=true\nexport FLAG = true # repeated\nFLAG=true\n"
        let doc = EnvDocument(source)
        XCTAssertEqual(doc.duplicates, ["FLAG"])
        XCTAssertTrue(doc.conflictingDuplicates.isEmpty)
        XCTAssertEqual(doc.reviewCount, 0)
        XCTAssertEqual(doc.entries.count, 3)
        XCTAssertEqual(doc.source, source)
        XCTAssertEqual(try doc.deleting(doc.entries[1]), "FLAG=true\nFLAG=true\n")
    }

    func testPlainQuotedBooleanAndEmptyValuesDoNotConflict() {
        let doc = EnvDocument("FLAG=true\nFLAG='true'\nFLAG=\"true\"\nOFF=false\nOFF=\"false\"\nEMPTY=\nEMPTY=''\nEMPTY=\"\"\n")
        XCTAssertEqual(doc.duplicates, ["FLAG", "OFF", "EMPTY"])
        XCTAssertTrue(doc.conflictingDuplicates.isEmpty)
        XCTAssertEqual(doc.reviewCount, 0)
    }

    func testSameKeyWithTrueAndFalseIsStillOneRealConflict() {
        let doc = EnvDocument("FLAG=true\nFLAG=false\nFLAG='false'\n")
        XCTAssertEqual(doc.conflictingDuplicates, ["FLAG"])
        XCTAssertEqual(doc.reviewCount, 1)
        XCTAssertEqual(doc.entries.map(\.line), [1, 2, 3])
    }

    func testCaseAndQuotedWhitespaceAreNotCollapsed() {
        let doc = EnvDocument("FLAG=true\nFLAG=TRUE\nNAME=value\nNAME=' value '\nlower=true\nLOWER=false\n")
        XCTAssertEqual(doc.conflictingDuplicates, ["FLAG", "NAME"])
        XCTAssertEqual(doc.reviewCount, 2)
    }

    func testCommonWordsUsedAsActualKeysHaveNoBlanketException() {
        let doc = EnvDocument("true=first\ntrue=second\nfalse=same\nfalse=same\n")
        XCTAssertEqual(doc.duplicates, ["true", "false"])
        XCTAssertEqual(doc.conflictingDuplicates, ["true"])
    }

    func testExpansionAndEscapeSyntaxRemainLiteralForConflictDetection() {
        let doc = EnvDocument("EXPAND=${HOME}\nEXPAND='${HOME}'\nESCAPE=\"one\\ntwo\"\nESCAPE='one\\ntwo'\nCOMMAND=`true`\nCOMMAND=true\n")
        XCTAssertEqual(doc.conflictingDuplicates, ["EXPAND", "ESCAPE", "COMMAND"])
        XCTAssertEqual(doc.reviewCount, 3)
    }

    func testReviewCountCombinesSyntaxWarningsAndValueConflicts() {
        let doc = EnvDocument("FLAG=true\nFLAG=false\ninvalid assignment\nSAME=0\nSAME=0\n")
        XCTAssertEqual(doc.diagnostics.count, 1)
        XCTAssertEqual(doc.conflictingDuplicates, ["FLAG"])
        XCTAssertEqual(doc.reviewCount, 2)
    }
}
