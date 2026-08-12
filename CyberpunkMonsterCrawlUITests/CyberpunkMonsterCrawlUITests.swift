import XCTest

/// Acceptance-criteria flow for the app shell: the app launches into a menu,
/// the PLAY button is present and hittable (i.e. `uiLayer` really is above
/// `worldLayer` and really does get touches first), and tapping it starts a
/// run. This is the coverage the v1 smoke label never had - a launch-only
/// assertion stays green over an unplayable build.
///
/// **Both tests here run in two configurations** (`CYBERPUN-17-4-t6`): the
/// `CyberpunkMonsterCrawl` scheme runs them against Debug, and the
/// `CyberpunkMonsterCrawl-Release` scheme runs them against **Release** - the
/// configuration the shipped product and the scripted runtime probe actually
/// use. Until that scheme existed, every structural safety net this app
/// relies on was `assert`-based (compiled out of Release) and CI built only
/// Debug, so the one configuration nobody exercised was the one users get.
/// Run the Release pass with:
/// `xcodebuild test -scheme CyberpunkMonsterCrawl-Release`.
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

    /// `GameplayScreenNode`'s container marker, matched on its accessibility
    /// *label* - see the note in
    /// `test_launchesIntoMenu_withAHittablePlayButton_thatStartsARun` for why
    /// an identifier subscript would be a silent no-op here.
    private func gameplayMarker(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["Gameplay"]
    }

    /// Which configuration this bundle - and therefore the app under test -
    /// was built in. Recorded as a test activity so an xcresult makes it
    /// obvious *which* pass produced a result, instead of leaving a reader to
    /// guess whether the Release scheme ran at all.
    private var buildConfigurationName: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
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

    /// The runtime probe's `menu-to-gameplay` journey, step for step, from a
    /// **cold launch with no prior `.gameplay` episode**: wait for PLAY by
    /// accessibility label with a bounded timeout, assert it is hittable, tap
    /// it, then wait for the gameplay marker.
    ///
    /// Why this exists next to the test above, which drives the same flow:
    /// the probe reported "no crash, app responsive, PLAY found and tapped,
    /// screen stayed on the menu" against a **Release** build, while the
    /// Debug suite was green. The two differences between those runs were the
    /// build configuration and the cold-launch-first-tap ordering (the test
    /// above may run after another test has already exercised the app). This
    /// test pins both: it terminates the app first so the tap it makes is the
    /// first touch this process ever receives, and the
    /// `CyberpunkMonsterCrawl-Release` scheme runs it in the configuration the
    /// probe launches - where `assert`-based invariants are compiled out and
    /// every `#if DEBUG` code path is gone.
    ///
    /// Every locator is an accessibility *label*, exactly like the journey's
    /// `{"action": "tap", "target": "PLAY"}`, so this test resolves its
    /// targets through the same `AccessibleSKView` element/frame machinery
    /// the probe does rather than through a path only XCUITest can see.
    func test_coldLaunch_tapPlayByAccessibilityLabel_landsOnGameplay() {
        XCTContext.runActivity(named: "cold launch, \(buildConfigurationName) configuration") { _ in
            let app = XCUIApplication()
            // `terminate()` on a not-running app is a no-op, so this is safe
            // as the first statement and guarantees the launch below is cold
            // however the suite was ordered.
            app.terminate()
            app.launch()
            XCTAssertEqual(app.state, .runningForeground, "the app must survive a cold launch")

            let play = self.playButton(in: app)
            XCTAssertTrue(
                play.waitForExistence(timeout: 20),
                "a cold launch must reach the menu and publish PLAY as an accessibility element "
                    + "within 20s (\(self.buildConfigurationName) build)"
            )
            XCTAssertTrue(
                play.isHittable,
                "PLAY must be hittable on the first frame a driver can see it, not painted over "
                    + "or off-screen"
            )

            play.tap()

            let gameplay = self.gameplayMarker(in: app)
            XCTAssertTrue(
                gameplay.waitForExistence(timeout: 15),
                "the first tap of the process on PLAY must start a run: the gameplay screen must "
                    + "mount in the \(self.buildConfigurationName) build too, which is exactly what "
                    + "the runtime probe reported not happening"
            )

            let menuDismissed = self.expectation(
                for: NSPredicate(format: "exists == false"),
                evaluatedWith: play
            )
            self.wait(for: [menuDismissed], timeout: 5)

            XCTAssertEqual(
                app.state, .runningForeground,
                "the app must still be alive after the transition - a Release build has no "
                    + "`assert` to trip, so a violated scene invariant must not take the process "
                    + "down either"
            )

            // The journey's `02-gameplay-ground-plane` screenshot, kept in the
            // xcresult so a Release pass leaves the same visual evidence the
            // probe collects.
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "gameplay-after-cold-launch-\(self.buildConfigurationName)"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
        }
    }
}
