import XCTest

/// Acceptance-criteria flow for the app shell: the app launches into a menu,
/// the PLAY button is present and hittable (i.e. `uiLayer` really is above
/// `worldLayer` and really does get touches first), and tapping it starts a
/// run. This is the coverage the v1 smoke label never had - a launch-only
/// assertion stays green over an unplayable build.
final class CyberpunkMonsterCrawlUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `MenuScreenNode`'s PLAY button is an accessibility element with `.button`
    /// traits (see `ButtonNode`); matching on `.any` keeps the query working
    /// whichever element type SpriteKit surfaces it as.
    private func playButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["PLAY"]
    }

    func test_launchesIntoMenu_withAHittablePlayButton_thatStartsARun() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)

        let play = playButton(in: app)
        XCTAssertTrue(
            play.waitForExistence(timeout: 10),
            "the app must launch into a menu showing a PLAY button"
        )
        XCTAssertTrue(play.isHittable, "the PLAY button must be hittable, not painted over by the world layer")

        play.tap()

        let menuDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: play
        )
        wait(for: [menuDismissed], timeout: 5)
        XCTAssertEqual(app.state, .runningForeground)

        // Matched on the container marker's accessibility *label*, not on
        // `gameplay.container`. `SKNode` has no real `accessibilityIdentifier`
        // (see `SKNodeAccessibilityIdentifier`): that property is a Swift-side
        // associated object that never reaches the accessibility element
        // `SKView` synthesises, so an identifier subscript here would be a
        // silent no-op that can never match - the exact "green over an
        // unplayable build" failure this test exists to prevent. SpriteKit does
        // forward `accessibilityLabel`, which is why the PLAY query above
        // resolves, and `GameplayScreenNode`'s marker sets
        // `accessibilityLabel = "Gameplay"`.
        let gameplayContainer = app.descendants(matching: .any)["Gameplay"]
        XCTAssertTrue(
            gameplayContainer.waitForExistence(timeout: 5),
            "PLAY must land on the (skeleton) gameplay screen, not an empty uiLayer"
        )
    }
}
