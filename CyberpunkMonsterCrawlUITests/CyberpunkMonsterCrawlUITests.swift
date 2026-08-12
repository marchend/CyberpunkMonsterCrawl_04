import XCTest

/// Bootstrap proof-of-life for the UI-test target (see project.yml — the
/// hard rule against empty test bundles means this target must ship with a
/// real test the moment it's declared, not an empty placeholder).
///
/// This bundle asserts only that the process reaches the foreground, so it
/// stays green in precisely the failure this feature exists to prevent:
/// world node rendered over the UI, no PLAY button, zero responsive input.
/// It is therefore scaffolding, and carries the marker so the grep-based
/// removal gate can find it rather than letting it survive forever.
final class CyberpunkMonsterCrawlUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // SCAFFOLDING(CYBERPUN-17-2-t2): replace this launch-only assertion with
    // the acceptance-criteria flow once the app shell lands — menu screen
    // present, PLAY button hittable, tapping it enters gameplay (i.e. the
    // uiLayer is above worldLayer and receives touches first). A launch-only
    // assertion protected by CI is the same shape as the v1 smoke label that
    // shipped green over an unplayable build; it is a bundle-validity floor,
    // not flow coverage.
    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
