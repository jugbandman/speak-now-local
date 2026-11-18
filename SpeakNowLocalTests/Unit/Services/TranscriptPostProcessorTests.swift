import XCTest
@testable import SpeakNowLocal

class TranscriptPostProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Constants.keyCleanupLevel)
        UserDefaults.standard.removeObject(forKey: Constants.keyCustomDictionary)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Constants.keyCleanupLevel)
        UserDefaults.standard.removeObject(forKey: Constants.keyCustomDictionary)
        super.tearDown()
    }

    // MARK: - Custom dictionary

    func testParseDictionaryHandlesEqualsAndArrow() {
        let rules = TranscriptPostProcessor.parseDictionary("arbor=Arbor\ndmitry -> Dmitry\n\ninvalid-line")
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].find, "arbor")
        XCTAssertEqual(rules[0].replace, "Arbor")
        XCTAssertEqual(rules[1].find, "dmitry")
        XCTAssertEqual(rules[1].replace, "Dmitry")
    }

    func testApplyDictionaryReplacesWholeWordsCaseInsensitively() {
        UserDefaults.standard.set("wispr=Speak Now", forKey: Constants.keyCustomDictionary)
        let result = TranscriptPostProcessor.applyDictionary("I use wispr daily, wisprflow stays.")
        XCTAssertEqual(result, "I use Speak Now daily, wisprflow stays.")
    }

    func testApplyDictionaryLongestRuleWins() {
        UserDefaults.standard.set("andy=Andy\nandy carlson=Andy Carlson", forKey: Constants.keyCustomDictionary)
        let result = TranscriptPostProcessor.applyDictionary("call andy carlson back")
        XCTAssertEqual(result, "call Andy Carlson back")
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
        UserDefaults.standard.set("arbor=Arbor", forKey: Constants.keyCustomDictionary)
        let result = TranscriptPostProcessor.process("um, so basically the arbor project is uh, you know, fine.")
        XCTAssertEqual(result, "The Arbor project is fine.")
    }

    func testDefaultLevelIsLight() {
        XCTAssertEqual(TranscriptPostProcessor.cleanupLevel, .light)
    }
}
