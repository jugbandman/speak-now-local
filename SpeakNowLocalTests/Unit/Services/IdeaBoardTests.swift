import XCTest
@testable import SpeakNowLocal

final class IdeaBoardTests: XCTestCase {

    private func card(_ id: String, _ title: String, _ bucket: String, ideas: [String] = []) -> IdeaCard {
        IdeaCard(id: id, title: title, bucket: bucket, ideaIDs: ideas, created: Date(), updated: Date())
    }

    func testParseIdeasAndNormalizesBuckets() {
        let reply = #"{"ideas": [{"text": "Add a gap check", "bucket": "Product", "card": "Prompt mode gaps"}, {"text": "Call Pete", "bucket": "unsure", "card": ""}, {"text": "  "}]}"#
        let ideas = IdeaSorter.parse(reply)
        XCTAssertEqual(ideas.count, 2)
        XCTAssertEqual(ideas[0], SortedIdea(text: "Add a gap check", bucket: "product", card: "Prompt mode gaps"))
        XCTAssertEqual(ideas[1].bucket, "unsorted")
        XCTAssertEqual(ideas[1].card, "Call Pete")
    }

    func testParseWrappedAndGarbage() {
        XCTAssertEqual(IdeaSorter.parse("Sure! {\"ideas\": []} done").count, 0)
        XCTAssertEqual(IdeaSorter.parse("no json at all").count, 0)
    }

    func testPlacementByExactTitleIgnoringCase() {
        var data = IdeaBoardData()
        data.cards = [card("c1", "Prompt mode gaps", "product")]
        let idea = SortedIdea(text: "x", bucket: "product", card: "prompt MODE gaps")
        XCTAssertEqual(IdeaSorter.placement(for: idea, vector: nil, data: data), "c1")
    }

    func testPlacementBySimilarMeaning() {
        var data = IdeaBoardData()
        data.cards = [card("c1", "Old title", "client", ideas: ["i1"])]
        data.ideas = [Idea(id: "i1", text: "y", entryID: "e1", date: Date(), cardID: "c1", vector: [1, 0, 0])]
        let idea = SortedIdea(text: "x", bucket: "client", card: "Brand new title")
        XCTAssertEqual(IdeaSorter.placement(for: idea, vector: [0.99, 0.05, 0], data: data), "c1")
        XCTAssertNil(IdeaSorter.placement(for: idea, vector: [0, 1, 0], data: data))
    }

    func testCosine() {
        XCTAssertEqual(IdeaSorter.cosine([1, 0], [1, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(IdeaSorter.cosine([1, 0], [0, 1]), 0, accuracy: 0.0001)
        XCTAssertEqual(IdeaSorter.cosine([1, 0], [1, 0, 0]), 0)
    }

    func testGuideKeywordsAndRuleBucket() {
        let guide = "# Buckets\n\n## Product\nSpeak Now, Ice Picks\n\n## Client\n- Velare, Doozy\n\n## Personal\nhockey\n\n## Examples\n- client: something"
        let kw = BucketGuide.keywords(from: guide)
        XCTAssertEqual(kw["client"], ["Velare", "Doozy"])
        XCTAssertEqual(BucketGuide.ruleBucket(for: "send velare the deck", keywords: kw), "client")
        XCTAssertEqual(BucketGuide.ruleBucket(for: "fix the Speak Now HUD", keywords: kw), "product")
        XCTAssertNil(BucketGuide.ruleBucket(for: "hockeystick shaped growth", keywords: kw))
    }

    func testWeeklyMarkdownGroupsAndCountsRepeats() {
        let now = Date()
        var data = IdeaBoardData()
        data.cards = [card("c1", "Prompt gaps", "product", ideas: ["i1", "i2"]),
                      card("c2", "Carpool", "personal", ideas: ["i3"]),
                      card("c3", "Old thing", "client", ideas: ["i4"])]
        data.ideas = [
            Idea(id: "i1", text: "ask about done", entryID: "e1", date: now, cardID: "c1", vector: nil),
            Idea(id: "i2", text: "check gaps", entryID: "e2", date: now, cardID: "c1", vector: nil),
            Idea(id: "i3", text: "hockey carpool", entryID: "e3", date: now, cardID: "c2", vector: nil),
            Idea(id: "i4", text: "stale", entryID: "e4", date: now.addingTimeInterval(-30 * 86400), cardID: "c3", vector: nil),
        ]
        let md = IdeaSorter.weeklyMarkdown(data, since: now.addingTimeInterval(-7 * 86400))
        XCTAssertTrue(md.hasPrefix("## Product"))
        XCTAssertTrue(md.contains("raised 2 times"))
        XCTAssertTrue(md.contains("## Personal"))
        XCTAssertFalse(md.contains("Old thing"))
    }
}
