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

    /// `MenuScreen`'s PLAY button is an accessibility element with `.button`
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

        // SCAFFOLDING(CYBERPUN-17-2-t3): with no gameplay screen registered
        // yet, the menu unmounting is the only observable consequence of the
        // menu -> gameplay transition; assert the gameplay HUD here instead
        // once CYBERPUN-17-2-t3 ships it.
        let menuDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: play
        )
        wait(for: [menuDismissed], timeout: 5)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
