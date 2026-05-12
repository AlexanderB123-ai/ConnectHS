import XCTest
@testable import ConnectHS

/// Sanity checks on `ReactionType` — emoji rendering, accessibility key
/// derivation, and Codable parity with the SQL `reaction_type` enum (which
/// uses snake_case `thumbs_up`, not Swift's camelCase `thumbsUp`).
final class ReactionTypeTests: XCTestCase {

    func test_rawValues_matchSQLEnum() {
        XCTAssertEqual(ReactionType.heart.rawValue, "heart")
        XCTAssertEqual(ReactionType.fire.rawValue, "fire")
        XCTAssertEqual(ReactionType.laugh.rawValue, "laugh")
        XCTAssertEqual(ReactionType.wow.rawValue, "wow")
        XCTAssertEqual(ReactionType.sad.rawValue, "sad")
        // The SQL enum is `thumbs_up`; if Swift ever drifts to `thumbsUp`
        // (the camelCase default), reactions will silently stop persisting.
        XCTAssertEqual(ReactionType.thumbsUp.rawValue, "thumbs_up")
    }

    func test_accessibilityLabelKey_followsConvention() {
        for reaction in ReactionType.allCases {
            XCTAssertEqual(
                reaction.accessibilityLabelKey,
                "reaction.label.\(reaction.rawValue)",
                "Catalog key must mirror raw value so VoiceOver can resolve it"
            )
        }
    }

    func test_emoji_isNonEmpty_forEveryCase() {
        for reaction in ReactionType.allCases {
            XCTAssertFalse(reaction.emoji.isEmpty, "\(reaction) has no emoji")
        }
    }
}
