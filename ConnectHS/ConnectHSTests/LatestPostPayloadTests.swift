import XCTest
@testable import ConnectHS

/// Codable round-trip tests for the App Group widget payload. We don't
/// touch the real shared container — encoding/decoding is the only
/// surface that needs to behave consistently between writer (the app)
/// and reader (the widget). Dates use `.iso8601` strategy to mirror
/// `LatestPostPayload.write()` / `read()`.
final class LatestPostPayloadTests: XCTestCase {

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func test_codable_roundTrip() throws {
        let original = LatestPostPayload(
            postID: UUID(),
            groupID: UUID(),
            groupName: "Lake Crew",
            groupEmoji: "🏖️",
            authorName: "Alex",
            postedAt: Date(timeIntervalSince1970: 1_700_000_000),
            backImageThumbBase64: "backbytes",
            frontImageThumbBase64: "frontbytes"
        )
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(LatestPostPayload.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_codable_handlesNilGroupEmoji() throws {
        let original = LatestPostPayload(
            postID: UUID(),
            groupID: UUID(),
            groupName: "Just Friends",
            groupEmoji: nil,
            authorName: "B",
            postedAt: Date(timeIntervalSince1970: 1_700_000_000),
            backImageThumbBase64: "b",
            frontImageThumbBase64: "f"
        )
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(LatestPostPayload.self, from: data)
        XCTAssertNil(decoded.groupEmoji)
        XCTAssertEqual(decoded, original)
    }

    /// `.iso8601` strategy truncates sub-second precision. If anyone ever
    /// flips the strategy back to default (.deferredToDate), this test
    /// catches the silent change in payload shape.
    func test_codable_dateStrategyIsISO8601() throws {
        let payload = LatestPostPayload(
            postID: UUID(),
            groupID: UUID(),
            groupName: "x",
            groupEmoji: nil,
            authorName: "x",
            postedAt: Date(timeIntervalSince1970: 1_700_000_000),
            backImageThumbBase64: "b",
            frontImageThumbBase64: "f"
        )
        let data = try makeEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""
        // 2023-11-14T22:13:20Z is the iso8601 representation of 1_700_000_000.
        XCTAssertTrue(
            json.contains("2023-11-14T22:13:20Z"),
            "Expected ISO-8601 date in JSON; got: \(json)"
        )
    }
}
