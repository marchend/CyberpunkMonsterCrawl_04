import XCTest

/// End-to-end app-shell flow (AC1, AC2, AC5): launch shows the menu in
/// portrait, rotating to landscape re-lays it out with nothing clipped or
/// off-screen, and PLAY still starts a run afterwards.
///
/// Complements `CyberpunkMonsterCrawlUITests` (which covers the
/// launch -> PLAY -> gameplay flow in whatever the simulator's default
/// orientation is) by explicitly driving both orientations, per AC5:
/// "Rotation re-lays out the current screen with no clipped/off-screen
/// controls."
final class AppLaunchAndRotationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Leave the simulator the way the next test expects to find it.
        XCUIDevice.shared.orientation = .portrait
    }

    private func playButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["menu.playButton"]
    }

    private func menuContainer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["menu.container"]
    }

    /// True when `element` has a real, non-empty frame that lies entirely
    /// within `bounds` \u2014 the "nothing lands under the notch/home indicator
    /// or off the edge of the screen" half of AC5.
    ///
    /// The emptiness guard is load-bearing: `CGRect.contains(_:)` returns
    /// `true` for a zero-sized rect, so if SpriteKit's accessibility bridge
    /// ever stops surfacing a real frame for a `ButtonNode`, a bare
    /// containment check would keep passing vacuously over a button that is
    /// entirely off-screen.
    private func isFullyOnScreen(_ element: XCUIElement, within bounds: CGRect) -> Bool {
        let frame = element.frame
        return !frame.isEmpty && bounds.contains(frame)
    }

    func test_launchPortrait_rotateToLandscape_playStillWorks() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)

        // MARK: - Portrait: menu visible, PLAY hittable and on-screen

        let play = playButton(in: app)
        XCTAssertTrue(
            play.waitForExistence(timeout: 10),
            "the app must launch into a menu showing a PLAY button"
        )
        XCTAssertTrue(play.isHittable, "PLAY must be hittable, not painted over by the world layer")
        XCTAssertTrue(
            menuContainer(in: app).exists,
            "the menu container must be present in portrait"
        )

        let portraitScreenBounds = app.windows.firstMatch.frame
        XCTAssertTrue(
            isFullyOnScreen(play, within: portraitScreenBounds),
            "PLAY must not be clipped or off-screen in portrait"
        )

        // MARK: - Rotate to landscape: menu re-lays out, nothing off-screen

        XCUIDevice.shared.orientation = .landscapeLeft

        // Layout runs off `didChangeSize`, which SpriteKit fires shortly
        // after the rotation animation completes; re-fetch the button
        // (SpriteKit accessibility elements are recreated on layout) and
        // give it a moment to reappear before asserting against it.
        let playAfterRotation = playButton(in: app)
        XCTAssertTrue(
            playAfterRotation.waitForExistence(timeout: 10),
            "PLAY must still exist after rotating to landscape"
        )
        XCTAssertTrue(playAfterRotation.isHittable, "PLAY must remain hittable in landscape")
        XCTAssertTrue(
            menuContainer(in: app).exists,
            "the menu container must still be present in landscape"
        )

        let landscapeScreenBounds = app.windows.firstMatch.frame
        XCTAssertTrue(
            isFullyOnScreen(playAfterRotation, within: landscapeScreenBounds),
            "PLAY must not be clipped or off-screen after rotating to landscape"
        )

        let highScoresAfterRotation = app.descendants(matching: .any)["menu.highScoresButton"]
        if highScoresAfterRotation.exists {
            XCTAssertTrue(
                isFullyOnScreen(highScoresAfterRotation, within: landscapeScreenBounds),
                "HIGH SCORES must not be clipped or off-screen after rotating to landscape"
            )
        }

        // MARK: - PLAY still transitions to gameplay after rotation

        playAfterRotation.tap()

        let menuDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: playAfterRotation
        )
        wait(for: [menuDismissed], timeout: 5)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
