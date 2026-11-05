import XCTest
@testable import SpeakNowLocal

/// Pure logic behind Prompt mode. None of these call Ollama.
final class PromptShaperTests: XCTestCase {

    // MARK: parse

    func testParseCleanJSON() {
        let reply = #"{"title": "Fix login bug", "prompt": "Find why login fails.", "missing": ["Which browser?"]}"#
        let result = PromptShaper.parse(reply)
        XCTAssertEqual(result.title, "Fix login bug")
        XCTAssertEqual(result.prompt, "Find why login fails.")
        XCTAssertEqual(result.missing, ["Which browser?"])
    }

    func testParseJSONWrappedInText() {
        let reply = "Here you go:\n{\"title\": \"T\", \"prompt\": \"P\", \"missing\": []}\nHope that helps."
        let result = PromptShaper.parse(reply)
        XCTAssertEqual(result.prompt, "P")
        XCTAssertEqual(result.missing, [])
    }

    func testParseAcceptsQuestionsAlias() {
        let reply = #"{"prompt": "P", "questions": ["Q1", "  ", "Q2"]}"#
        XCTAssertEqual(PromptShaper.parse(reply).missing, ["Q1", "Q2"])
    }

    func testParseFallsBackToRawText() {
        let reply = "Just a plain prompt with no JSON."
        let result = PromptShaper.parse(reply)
        XCTAssertEqual(result.prompt, reply)
        XCTAssertEqual(result.missing, [])
        XCTAssertEqual(result.title, "")
    }

    func testParseEmptyPromptFallsBack() {
        let reply = #"{"title": "T", "prompt": "", "missing": ["Q"]}"#
        XCTAssertEqual(PromptShaper.parse(reply).prompt, reply)
    }

    // MARK: messages

    func testUserMessageNumbersTakesAndMarksAnswers() {
        let takes = [
            PromptTake(text: "first idea"),
            PromptTake(text: "the goal is speed", kind: .answer(question: "What is the goal?")),
            PromptTake(text: "second idea")
        ]
        let message = PromptShaper.userMessage(for: takes)
        XCTAssertTrue(message.contains("TAKE 1:\nfirst idea"))
        XCTAssertTrue(message.contains("ANSWER to \"What is the goal?\":\nthe goal is speed"))
        XCTAssertTrue(message.contains("TAKE 2:\nsecond idea"))
    }

    func testSystemPromptCarriesTargetAndAsk() {
        let target = PromptTemplate(id: "t", name: "T", body: "TARGET BODY")
        let ask = PromptTemplate(id: "a", name: "A", body: "ASK BODY")
        let system = PromptShaper.systemPrompt(target: target, ask: ask)
        XCTAssertTrue(system.contains("TARGET BODY"))
        XCTAssertTrue(system.contains("ASK BODY"))
        XCTAssertTrue(system.contains("\"missing\""))
    }

    // MARK: chunking and cleanup

    func testChunkKeepsAllWordsInOrder() {
        let text = (1...10).map(String.init).joined(separator: " ")
        let chunks = PromptShaper.chunk(text, maxWords: 4)
        XCTAssertEqual(chunks, ["1 2 3 4", "5 6 7 8", "9 10"])
    }

    func testChunkEmptyText() {
        XCTAssertEqual(PromptShaper.chunk("   ", maxWords: 4), [])
    }

    func testStripTriggerRemovesLeadingPrompt() {
        XCTAssertEqual(PromptShaper.stripTrigger("Prompt, build me a login page"), "build me a login page")
        XCTAssertEqual(PromptShaper.stripTrigger("prompt build it"), "build it")
    }

    func testStripTriggerLeavesOtherText() {
        XCTAssertEqual(PromptShaper.stripTrigger("Build a prompt library"), "Build a prompt library")
    }

    // MARK: templates

    func testParseNameUsesFirstHeading() {
        XCTAssertEqual(TemplateStore.parseName(from: "intro\n# Claude Opus\n## Checklist", fallback: "x"), "Claude Opus")
    }

    func testParseNameFallsBack() {
        XCTAssertEqual(TemplateStore.parseName(from: "no heading here", fallback: "my-file"), "my-file")
    }

    func testDefaultTargetsAllHaveChecklists() {
        for (id, body) in DefaultTemplates.targets {
            XCTAssertTrue(body.contains("## Checklist"), "\(id) has no checklist")
        }
    }

    // MARK: modes

    func testPromptKeywordDetected() {
        XCTAssertEqual(VoiceMode.detect(from: "Prompt, I want a login page").keyword, "PROMPT")
    }

    func testVisibleModesAreThree() {
        XCTAssertEqual(VoiceMode.visibleModes.map(\.keyword), ["PROMPT", "NOTE", "TEXT"])
    }
}
