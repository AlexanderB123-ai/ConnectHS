import XCTest

/// Smoke test: a freshly-launched app puts the user on `WelcomeView`.
///
/// What's deliberately NOT tested here:
/// - **Auth flows.** Both phone OTP and Sign in with Apple are blocked on
///   Personal Team / no Twilio (see decisions.md 2026-05-08). The
///   "continue with phone" button surfaces a real Supabase failure on
///   tap; "continue with apple" needs the stripped SIWA entitlement back.
///   Until 2026-06-16 enrollment, the UI test surface ends here.
/// - **Post-auth flows** (group / camera / feed / archive). These need a
///   pre-bootstrapped session, which means injecting a UITest-only auth
///   bypass — deferred to a follow-up so v1's `#if DEBUG` backdoor
///   doesn't reappear (per decisions.md 2026-05-08 wipe).
final class AppLaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launch the app and assert the Welcome screen renders both the
    /// hero title and the phone-CTA button. Match by accessibility
    /// identifier (set on the SwiftUI views in `WelcomeView.swift`),
    /// NOT by visible text — the UI test bundle has no copy of the
    /// string catalog, so `NSLocalizedString` would return the key
    /// rather than the rendered English string.
    @MainActor
    func testLaunchLandsOnWelcomeScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["welcome.title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "welcome.title element not found — RootView didn't land on WelcomeView, or the .accessibilityIdentifier was removed."
        )

        let phoneCTA = app.buttons["welcome.continue.phone"]
        XCTAssertTrue(
            phoneCTA.waitForExistence(timeout: 2),
            "welcome.continue.phone element not found — the phone NavigationLink lost its .accessibilityIdentifier."
        )
    }

    /// Tapping the phone CTA navigates to `PhoneEntryView`. Validates the
    /// NavigationLink wiring without triggering any actual auth (no `send`
    /// tap, no Supabase call). Useful as a structural check that
    /// RootView/NavigationStack composition isn't broken.
    @MainActor
    func testTappingPhoneCTA_navigatesToPhoneEntry() throws {
        let app = XCUIApplication()
        app.launch()

        let phoneCTA = app.buttons["welcome.continue.phone"]
        XCTAssertTrue(phoneCTA.waitForExistence(timeout: 10))
        phoneCTA.tap()

        // 10s timeout: NavigationStack push animation + simulator render
        // can take several seconds on a cold automation session. Don't
        // tighten this without testing on a clean sim.
        let title = app.staticTexts["phone.title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "phone.title not found after tapping welcome's phone CTA — NavigationLink to PhoneEntryView may be broken."
        )
        let subtitle = app.staticTexts["phone.subtitle"]
        XCTAssertTrue(
            subtitle.waitForExistence(timeout: 3),
            "phone.subtitle not found — PhoneEntryView layout regressed."
        )
    }
}
