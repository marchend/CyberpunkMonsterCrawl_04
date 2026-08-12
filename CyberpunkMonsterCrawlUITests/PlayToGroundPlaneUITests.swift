import XCTest

/// End-to-end coverage for the regression `CYBERPUN-17-4-t4` fixes: a
/// runtime probe reported "PLAY tapped, screen never visibly left the menu"
/// because the first `.gameplay` entry used to build/mount the *entire*
/// resident chunk window (up to `ChunkStreamingManager.residentWindowSize *
/// Chunk.size * Chunk.size` = 3,136 `SKSpriteNode`s) synchronously, inside
/// the same call stack as the PLAY button tap \u2014 a stall long enough for a
/// scripted probe that taps PLAY and screenshots after a short fixed wait to
/// catch the app mid-stall, before the first `.gameplay` frame had actually
/// presented.
///
/// Nothing before this file drove the real, composed app end to end
/// (`GameViewController` -> a real touch -> a real state-machine transition
/// -> real mounted ground nodes): every other test in the suite either
/// drives `GameScene`/`GroundPlaneStreamer` directly (constructed without an
/// `SKView`, so there is no real touch delivery and no real render loop) or
/// unit-tests `ButtonNode`/`MenuScreenNode` in isolation. This is the first
/// file in the previously-empty `CyberpunkMonsterCrawlUITests` target, and
/// it closes exactly that gap \u2014 at the level the runtime probe itself
/// operates at.
///
/// SpriteKit ground tiles are not individually accessibility-exposed (see
/// `GroundTileRenderer`), so this test asserts screen-level reachability \u2014
/// PLAY actually lands somewhere real and stays there \u2014 rather than
/// inspecting individual ground nodes, which is the same granularity the
/// probe itself measured.
///
/// **Matches by `accessibilityLabel`, not the `menu.playButton` /
/// `gameplay.container` identifier strings named in this story's findings
/// write-up.** `SKNode` never adopts `UIAccessibilityIdentification` (see
/// `SKNodeAccessibilityIdentifier.swift`): an `accessibilityIdentifier` set
/// through that extension is Swift-side bookkeeping only and never reaches
/// the accessibility element `SKView` synthesises, so an XCUITest identifier
/// query against those strings can never match. Only `accessibilityLabel`
/// (`"PLAY"` on the button, `"Gameplay"` on the gameplay screen's container
/// marker) is genuinely forwarded to the accessibility tree \u2014
/// `CyberpunkMonsterCrawlUITests` already establishes this as the working
/// pattern, and this file follows it rather than the identifiers named in
/// the findings prose.
final class PlayToGroundPlaneUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func playButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["PLAY"]
    }

    private func gameplayContainer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["Gameplay"]
    }

    func test_tappingPlay_reachesTheRealMountedGameplayScreen_withoutStallingOnTheMenu() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)

        let play = playButton(in: app)
        XCTAssertTrue(
            play.waitForExistence(timeout: 10),
            "the app must launch into a menu showing a hittable PLAY button"
        )
        XCTAssertTrue(play.isHittable, "PLAY must be hittable before it is tapped")

        play.tap()

        // The exact regression this test guards against: a probe that taps
        // PLAY and catches the app mid-stall, before the menu has actually
        // been dismissed and before the first `.gameplay` frame has
        // presented, so the screen "never visibly left the menu". Waiting
        // for the PLAY button itself to disappear (rather than sleeping a
        // fixed duration and screenshotting) is what makes this assertion
        // meaningful rather than vacuous.
        let menuDismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: play)
        wait(for: [menuDismissed], timeout: 10)

        let gameplay = gameplayContainer(in: app)
        XCTAssertTrue(
            gameplay.waitForExistence(timeout: 10),
            "PLAY must land on a real, reachable gameplay screen \u{2014} not stall on the menu forever"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
