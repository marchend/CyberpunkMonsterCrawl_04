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

    /// `MenuScreenNode`'s `menu.container` anchor (label "Menu"). Unlike
    /// `GameplayScreenNode`'s deleted `gameplay.container` marker, this one is
    /// a **durable shipping accessibility contract** - see `MenuScreenNode`'s
    /// doc comment, which says in as many words that the identifier is to stay
    /// stable across restyles - so asserting on it here creates no future
    /// removal debt the way asserting on scaffolding did.
    /// `AppLaunchAndRotationUITests` matches the same anchor by identifier,
    /// which is what proves the query resolves at runtime (`AccessibleSKView`
    /// republishes `uiLayer` markers as real elements carrying their
    /// identifier).
    private func menuContainer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["menu.container"]
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

        // Pinned *before* the tap on purpose: it is what keeps the
        // disappearance assertion below non-vacuous. A query that could never
        // resolve (the failure mode the deleted `gameplay.container` comment
        // described) satisfies "exists == false" trivially, so the anchor has
        // to be observed present first for its absence to mean anything.
        let menuAnchor = menuContainer(in: app)
        XCTAssertTrue(
            menuAnchor.waitForExistence(timeout: 10),
            "the menu's durable menu.container anchor must be present before PLAY is tapped"
        )

        play.tap()

        let menuDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: play
        )
        // The whole menu unmounted, not just its button: PLAY vanishing alone
        // also matches a restyle that drops the button while leaving the menu
        // mounted.
        let menuAnchorDismissed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: menuAnchor
        )
        wait(for: [menuDismissed, menuAnchorDismissed], timeout: 5)
        XCTAssertEqual(app.state, .runningForeground)

        // Deliberate, reviewed gap - read this before "strengthening" the
        // assertions above with a new marker.
        //
        // `GameplayScreenNode` mounts no accessibility anchor of its own (the
        // skeleton screen mounts no content at all until the real HUD,
        // CYBERPUN-17-12 - see that type's doc comment), and its former
        // `gameplay.container` marker was scaffolding deleted in
        // CYBERPUN-17-7-t5. So the strongest thing this end-to-end test can
        // honestly say today is "the menu unmounted and the app is still
        // running": it cannot, in a real app process, distinguish `.gameplay`
        // from `.highScores` or a blank `uiLayer`. Do not re-add a marker to
        // close that gap - a UI test asserting a scaffolding node's presence
        // is precisely how scaffolding outlives the ticket meant to remove it.
        //
        // What does pin the destination, in-process:
        //   - `GameViewControllerCompositionTests`
        //     `.test_compositionRoot_playButton_isWiredToTheStateMachine`
        //     pins PLAY -> `.gameplay` through the real composition root.
        //   - `ThumbstickSceneWiringTests` pins `isRunActive`, i.e. that the
        //     run really started rather than the menu merely unmounting.
        // The residual gap is therefore "nothing proves the destination
        // end-to-end in a real app process", and it closes for free once
        // CYBERPUN-17-12 gives the gameplay screen durable HUD content to
        // match on.
    }
}
