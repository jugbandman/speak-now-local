import XCTest
@testable import SpeakNowLocal

final class CorrectionsTests: XCTestCase {

    func testParseSkipsCommentsAndBadLines() {
        let text = "# Corrections\n\nProse with no separator\n- FareHarbor: fair harbor, fare harbour\nTito:\nVelare: Belair"
        XCTAssertEqual(Corrections.parse(text), [
            .init(right: "FareHarbor", wrongs: ["fair harbor", "fare harbour"]),
            .init(right: "Velare", wrongs: ["Belair"])
        ])
    }

    func testFormatRoundTrips() {
        let items: [Corrections.Correction] = [.init(right: "Velare", wrongs: ["Belair", "Valair"])]
        XCTAssertEqual(Corrections.parse(Corrections.format(items)), items)
    }

    func testApplyReplacesWholeWordsInAnyCase() {
        let items: [Corrections.Correction] = [.init(right: "Velare", wrongs: ["Belair"])]
        let result = Corrections.apply(items, to: "Call belair today. BELAIR said yes.")
        XCTAssertEqual(result.text, "Call Velare today. Velare said yes.")
        XCTAssertEqual(result.hits["Velare"], 2)
    }

    func testApplyLeavesPartsOfOtherWords() {
        let items: [Corrections.Correction] = [.init(right: "Tito", wrongs: ["Tido"])]
        let result = Corrections.apply(items, to: "Tidos and Tido")
        XCTAssertEqual(result.text, "Tidos and Tito")
        XCTAssertEqual(result.hits["Tito"], 1)
    }

    func testApplyFixesCapitalizationOnly() {
        let items: [Corrections.Correction] = [.init(right: "FareHarbor", wrongs: ["fareharbor"])]
        let result = Corrections.apply(items, to: "use fareharbor and FareHarbor")
        XCTAssertEqual(result.text, "use FareHarbor and FareHarbor")
        XCTAssertEqual(result.hits["FareHarbor"], 1)
    }

    func testApplyMultiWordWrongSpelling() {
        let items: [Corrections.Correction] = [.init(right: "FareHarbor", wrongs: ["fair harbor"])]
        XCTAssertEqual(Corrections.apply(items, to: "book on fair harbor now").text, "book on FareHarbor now")
    }

    func testNoHitsLeavesTextAlone() {
        let items: [Corrections.Correction] = [.init(right: "Velare", wrongs: ["Belair"])]
        let result = Corrections.apply(items, to: "nothing to fix")
        XCTAssertEqual(result.text, "nothing to fix")
        XCTAssertTrue(result.hits.isEmpty)
    }

    func testHintDedupesAndCaps() {
        var items: [Corrections.Correction] = [.init(right: "Velare", wrongs: ["a"]), .init(right: "velare", wrongs: ["b"])]
        XCTAssertEqual(Corrections.hint(items), "Velare")
        items = (0..<60).map { Corrections.Correction(right: "T\($0)", wrongs: ["x"]) }
        XCTAssertEqual(Corrections.hint(items).components(separatedBy: ", ").count, Corrections.maxHintTerms)
    }

    func testServerPathSitsNextToCLI() {
        XCTAssertEqual(WhisperServer.serverPath(forCLI: "/opt/homebrew/bin/whisper-cli"), "/opt/homebrew/bin/whisper-server")
    }
}
