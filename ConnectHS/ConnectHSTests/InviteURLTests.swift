import XCTest
@testable import ConnectHS

/// Pure-logic tests for the invite-link parser. No Supabase or UI dependencies
/// — safe to run anywhere.
final class InviteURLTests: XCTestCase {

    // MARK: - extractCode

    func test_extractCode_fromBareCode() {
        XCTAssertEqual(InviteURL.extractCode(from: "ABCD1234"), "ABCD1234")
    }

    func test_extractCode_fromCustomScheme() {
        XCTAssertEqual(
            InviteURL.extractCode(from: "connecths://invite/ABCD1234"),
            "ABCD1234"
        )
    }

    func test_extractCode_fromUniversalLink() {
        XCTAssertEqual(
            InviteURL.extractCode(from: "https://connecths.app/i/ABCD1234"),
            "ABCD1234"
        )
    }

    func test_extractCode_trimsWhitespace() {
        XCTAssertEqual(
            InviteURL.extractCode(from: "  ABCD1234\n"),
            "ABCD1234"
        )
    }

    func test_extractCode_emptyInputReturnsNil() {
        XCTAssertNil(InviteURL.extractCode(from: ""))
        XCTAssertNil(InviteURL.extractCode(from: "   "))
    }

    func test_extractCode_universalLinkWithTrailingSlash() {
        XCTAssertEqual(
            InviteURL.extractCode(from: "https://connecths.app/i/ABCD1234/"),
            "ABCD1234"
        )
    }

    // MARK: - isInvite

    func test_isInvite_acceptsCustomScheme() {
        let url = URL(string: "connecths://invite/ABCD1234")!
        XCTAssertTrue(InviteURL.isInvite(url))
    }

    func test_isInvite_acceptsUniversalLink() {
        let url = URL(string: "https://connecths.app/i/ABCD1234")!
        XCTAssertTrue(InviteURL.isInvite(url))
    }

    func test_isInvite_rejectsWrongHost() {
        let url = URL(string: "https://example.com/i/ABCD1234")!
        XCTAssertFalse(InviteURL.isInvite(url))
    }

    func test_isInvite_rejectsWrongPathOnOurHost() {
        // /i/ is invite; anything else (e.g. marketing pages) shouldn't redeem.
        let url = URL(string: "https://connecths.app/about")!
        XCTAssertFalse(InviteURL.isInvite(url))
    }

    func test_isInvite_rejectsCustomSchemeWithDifferentHost() {
        let url = URL(string: "connecths://post/some-uuid")!
        XCTAssertFalse(InviteURL.isInvite(url))
    }

    // MARK: - link builders

    func test_deepLink_round_trip() {
        let url = InviteURL.deepLink(code: "ABCD1234")
        XCTAssertEqual(url?.absoluteString, "connecths://invite/ABCD1234")
    }

    func test_universalLink_round_trip() {
        let url = InviteURL.universalLink(code: "ABCD1234")
        XCTAssertEqual(url?.absoluteString, "https://connecths.app/i/ABCD1234")
    }
}
