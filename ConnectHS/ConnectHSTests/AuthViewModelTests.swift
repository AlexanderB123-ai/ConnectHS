import XCTest
@testable import ConnectHS

/// Pure-logic tests for AuthViewModel's phone formatting + country code
/// default. Uses the static `formatPhoneE164(_:countryCode:)` so the tests
/// don't instantiate AuthViewModel — instantiation would transitively touch
/// the `supabase` global, which fatalErrors in the test bundle (no
/// SUPABASE_* keys in the synthesized Info.plist).
///
/// formatPhoneE164 is the single chokepoint feeding Supabase Auth, so
/// regressions here would break sign-in for every user.
final class AuthViewModelTests: XCTestCase {

    // MARK: - formatPhoneE164: US baseline (default country code = "1")

    func test_formatPhoneE164_usTenDigits_prependsPlusOne() {
        XCTAssertEqual(AuthViewModel.formatPhoneE164("5551234567", countryCode: "1"), "+15551234567")
    }

    func test_formatPhoneE164_strippedFormatting_ignoresPunctuation() {
        XCTAssertEqual(AuthViewModel.formatPhoneE164("(555) 123-4567", countryCode: "1"), "+15551234567")
        XCTAssertEqual(AuthViewModel.formatPhoneE164("555.123.4567", countryCode: "1"), "+15551234567")
        XCTAssertEqual(AuthViewModel.formatPhoneE164("555 123 4567", countryCode: "1"), "+15551234567")
    }

    func test_formatPhoneE164_userPastesCountryCodeWithDigits_doesNotDoublePrefix() {
        // User typed "1 555 123 4567" — country code "1" already present
        // in the digits; don't produce "+115551234567".
        XCTAssertEqual(AuthViewModel.formatPhoneE164("15551234567", countryCode: "1"), "+15551234567")
    }

    // MARK: - formatPhoneE164: non-US

    func test_formatPhoneE164_ukUserWithUkCode() {
        XCTAssertEqual(AuthViewModel.formatPhoneE164("7700900123", countryCode: "44"), "+447700900123")
    }

    func test_formatPhoneE164_inUserWithInCode() {
        XCTAssertEqual(AuthViewModel.formatPhoneE164("9876543210", countryCode: "91"), "+919876543210")
    }

    func test_formatPhoneE164_userTypesFullE164WithCountryCode_passesThrough() {
        // "447700900123" already starts with the UK country code; don't
        // produce "+44447700900123".
        XCTAssertEqual(AuthViewModel.formatPhoneE164("447700900123", countryCode: "44"), "+447700900123")
    }

    // MARK: - formatPhoneE164: edge cases

    func test_formatPhoneE164_emptyCountryCode_emitsPlusDigitsOnly() {
        // Defensive: if somehow countryCode is wiped, don't crash and don't
        // emit a corrupt number. Just prepend "+".
        XCTAssertEqual(AuthViewModel.formatPhoneE164("5551234567", countryCode: ""), "+5551234567")
    }

    func test_formatPhoneE164_countryCodeWithPunctuation_extractsDigits() {
        // User typed "+1" into the country code field by accident.
        XCTAssertEqual(AuthViewModel.formatPhoneE164("5551234567", countryCode: "+1"), "+15551234567")
    }

    // MARK: - defaultCountryCode: locale-based mapping

    func test_defaultCountryCode_returnsNonEmptyDigitsOnly() {
        let code = AuthViewModel.defaultCountryCode()
        XCTAssertFalse(code.isEmpty, "defaultCountryCode should never return empty")
        XCTAssertTrue(code.allSatisfy(\.isNumber), "defaultCountryCode should be digits-only (no '+')")
    }

    func test_defaultCountryCode_isOneOfMappedRegions() {
        // The mapping is intentionally narrow; this asserts the value is a
        // recognized prefix and not garbage.
        let known: Set<String> = ["1", "44", "91", "61", "49", "33", "52", "55", "81", "82", "86"]
        let code = AuthViewModel.defaultCountryCode()
        XCTAssertTrue(known.contains(code), "Expected a recognized country code, got \(code)")
    }
}
