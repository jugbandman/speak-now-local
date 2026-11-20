import XCTest
@testable import SpeakNowLocal

class TranscriptPostProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Constants.keyCleanupLevel)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Constants.keyCleanupLevel)
        super.tearDown()
    }

    // MARK: - Filler removal

    func testRemoveFillersStripsCommonFillers() {
        let input = "Um, so basically, you know, I mean, the sort of kind of plan is uh good."
        let result = TranscriptPostProcessor.removeFillers(input)
        XCTAssertFalse(result.lowercased().contains("um"))
        XCTAssertFalse(result.lowercased().contains("you know"))
        XCTAssertTrue(result.contains("the plan is good"))
    }

    func testRemoveFillersKeepsRealWords() {
        let input = "I like this design."
        let result = TranscriptPostProcessor.removeFillers(input)
        XCTAssertEqual(result, "I like this design.")
    }

    // MARK: - Normalization

    func testNormalizeSpacingCollapsesAndSentenceCases() {
        let result = TranscriptPostProcessor.normalizeSpacing("  hello   there. it is  me.  ")
        XCTAssertEqual(result, "Hello there. It is me.")
    }

    // MARK: - Level routing

    func testProcessOffKeepsRawText() {
        UserDefaults.standard.set(TranscriptPostProcessor.CleanupLevel.off.rawValue, forKey: Constants.keyCleanupLevel)
        let result = TranscriptPostProcessor.process("um, hello there.")
        XCTAssertEqual(result, "um, hello there.")
    }

    func testProcessLightRunsFullPipeline() {
        UserDefaults.standard.set(TranscriptPostProcessor.CleanupLevel.light.rawValue, forKey: Constants.keyCleanupLevel)
        let result = TranscriptPostProcessor.process("um, so basically the arbor project is uh, you know, fine.")
        XCTAssertEqual(result, "The arbor project is fine.")
    }

    // Custom vocabulary is corrections.md. WhisperTranscriber applies it before
    // cleanup, so a fixed spelling must survive the light pipeline.
    func testCorrectionsThenLightCleanupKeepsTheFix() {
        UserDefaults.standard.set(TranscriptPostProcessor.CleanupLevel.light.rawValue, forKey: Constants.keyCleanupLevel)
        let fixes = [Corrections.Correction(right: "Arbor", wrongs: ["arbor"])]
        let corrected = Corrections.apply(fixes, to: "um, so basically the arbor project is uh, you know, fine.").text
        XCTAssertEqual(TranscriptPostProcessor.process(corrected), "The Arbor project is fine.")
    }

    func testDefaultLevelIsLight() {
        XCTAssertEqual(TranscriptPostProcessor.cleanupLevel, .light)
    }
}
