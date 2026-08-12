import XCTest

/// Bootstrap proof-of-life for the UI-test target (see project.yml — the
/// hard rule against empty test bundles means this target must ship with a
/// real test the moment it's declared, not an empty placeholder). Real
/// flow coverage (state-machine transitions driven through the UI) lands
/// in a future PR that can drop files straight into this directory with
/// zero further `project.yml` churn.
final class CyberpunkMonsterCrawlUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
