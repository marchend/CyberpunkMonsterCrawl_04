import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Unit coverage for the concrete `ScreenNode` conformers this PR ships:
/// `MenuScreenNode` (real PLAY/HIGH SCORES wiring, accessibility surface)
/// and the three skeleton screens (`GameplayScreenNode`, `DeathScreenNode`,
/// `HighScoresScreenNode`), whose *navigation* is real even though their
/// visual content is `// SCAFFOLDING:`-marked. `GameSceneScreenSwitchingTests`
/// and `GameViewControllerCompositionTests` already exercise these through
/// `GameScene`'s registry and touch dispatch; these tests drive the screens
/// directly so a regression in a screen's own wiring or layout is pinned
/// independent of the scene plumbing around it.
final class ScreensTests: XCTestCase {

    // MARK: - ButtonNode

    func test_buttonNode_defaultsAccessibilityIdentifier_toItsTitle() {
        let button = ButtonNode(title: "PLAY", size: CGSize(width: 100, height: 40)) {}
        XCTAssertEqual(button.accessibilityIdentifier, "PLAY")
        XCTAssertEqual(button.accessibilityLabel, "PLAY")
        XCTAssertTrue(button.isAccessibilityElement)
    }

    func test_buttonNode_usesExplicitAccessibilityIdentifier_whenSupplied() {
        let button = ButtonNode(
            title: "PLAY",
            size: CGSize(width: 100, height: 40),
            accessibilityIdentifier: "menu.playButton"
        ) {}
        XCTAssertEqual(button.accessibilityIdentifier, "menu.playButton")
    }

    func test_buttonNode_withAccentColor_addsAnAccentFrameChild() {
        let plain = ButtonNode(title: "BACK", size: CGSize(width: 100, height: 40)) {}
        let accented = ButtonNode(
            title: "PLAY",
            size: CGSize(width: 100, height: 40),
            accentColor: PixelGritPalette.neonAccent
        ) {}

        XCTAssertFalse(
            plain.children.contains { $0.name == "button.BACK.accentFrame" }
        )
        XCTAssertTrue(
            accented.children.contains { $0.name == "button.PLAY.accentFrame" },
            "an accent color must add a neon frame node behind the plate"
        )
    }

    // MARK: - MenuScreenNode

    func test_menuScreenNode_exposesAccessibilityIdentifiers_onPlayAndContainer() {
        let menu = MenuScreenNode(onPlay: {}, onHighScores: {})

        XCTAssertEqual(menu.playButton.accessibilityIdentifier, "menu.playButton")
        XCTAssertEqual(menu.highScoresButton.accessibilityIdentifier, "menu.highScoresButton")
        let marker = menu.node.children.first { $0.accessibilityIdentifier == "menu.container" }
        XCTAssertNotNil(
            marker,
            "the menu must expose a container accessibility anchor independent of any one button"
        )
        // As with `gameplay.container`: the identifier is Swift-side
        // bookkeeping only (see `SKNodeAccessibilityIdentifier`), so the label
        // is what any UI test or VoiceOver can actually observe.
        XCTAssertTrue(marker?.isAccessibilityElement == true)
        XCTAssertEqual(marker?.accessibilityLabel, "Menu")
    }

    func test_menuScreenNode_playButton_runsTheSuppliedClosure() {
        var playTapped = false
        let menu = MenuScreenNode(onPlay: { playTapped = true }, onHighScores: {})

        menu.playButton.handleTouch()

        XCTAssertTrue(playTapped)
    }

    func test_menuScreenNode_highScoresButton_runsTheSuppliedClosure() {
        var highScoresTapped = false
        let menu = MenuScreenNode(onPlay: {}, onHighScores: { highScoresTapped = true })

        menu.highScoresButton.handleTouch()

        XCTAssertTrue(highScoresTapped)
    }

    /// AC5: "rotation re-lays out the current screen with no clipped or
    /// off-screen controls." The screen is camera-pinned, so its own
    /// coordinate space is centred on `(0, 0)` and the visible viewport is
    /// `size` centred on the origin - a control is on-screen exactly when
    /// its accumulated frame sits inside that rect. Driven in both a
    /// portrait and a landscape size so a layout that only holds in one
    /// orientation fails here.
    func test_menuScreenNode_layout_resizesBackground_andKeepsButtonsWithinBounds() {
        let orientations: [(name: String, size: CGSize, insets: UIEdgeInsets)] = [
            ("portrait", CGSize(width: 400, height: 800), UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0)),
            ("landscape", CGSize(width: 800, height: 400), UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)),
        ]

        for orientation in orientations {
            let menu = MenuScreenNode(onPlay: {}, onHighScores: {})

            menu.layout(for: orientation.size, safeAreaInsets: orientation.insets)

            let background = menu.node.children.compactMap { $0 as? SKSpriteNode }.first
            XCTAssertEqual(
                background?.size, orientation.size,
                "\(orientation.name): the full-bleed backdrop must be resized to the scene size, or "
                    + "rotation leaves SpriteKit's default background showing at the edges"
            )

            let viewport = CGRect(
                x: -orientation.size.width / 2, y: -orientation.size.height / 2,
                width: orientation.size.width, height: orientation.size.height
            )
            for button in [menu.playButton, menu.highScoresButton] {
                let frame = button.calculateAccumulatedFrame()
                XCTAssertFalse(
                    frame.isEmpty,
                    "\(orientation.name): \(button.title) has an empty frame, so containment below "
                        + "would pass vacuously"
                )
                XCTAssertTrue(
                    viewport.contains(frame),
                    "\(orientation.name): \(button.title) at \(frame) is clipped or off-screen "
                        + "relative to the \(viewport) viewport"
                )
            }

            XCTAssertNotEqual(
                menu.playButton.position.y, menu.highScoresButton.position.y,
                "\(orientation.name): PLAY and HIGH SCORES must not land on top of each other"
            )
        }
    }

    // MARK: - GameplayScreenNode

    /// The identifier assertion alone would only prove
    /// `SKNodeAccessibilityIdentifier` stored and handed back a string:
    /// `SKNode` has no real `accessibilityIdentifier`, so that value never
    /// reaches UIKit and XCUITest can never match it. The marker must also be
    /// an accessibility element carrying an `accessibilityLabel`, because the
    /// label is the property SpriteKit genuinely forwards and therefore the
    /// only thing `CyberpunkMonsterCrawlUITests` can actually query when it
    /// checks that PLAY landed on a real screen.
    func test_gameplayScreenNode_exposesAContainerAccessibilityAnchor() {
        let gameplay = GameplayScreenNode()

        let marker = gameplay.node.children.first { $0.accessibilityIdentifier == "gameplay.container" }
        XCTAssertNotNil(
            marker,
            "a UI test must be able to observe PLAY landing on a real, mounted gameplay screen"
        )
        XCTAssertTrue(
            marker?.isAccessibilityElement == true,
            "the container marker must be an accessibility element or UIKit will not surface it at all"
        )
        XCTAssertEqual(
            marker?.accessibilityLabel, "Gameplay",
            "the UI test matches this marker by accessibility label - the identifier is invisible to XCUITest"
        )
    }

    /// The gameplay screen is the one screen the world must show *through*,
    /// so unlike menu/death/high-scores it must mount nothing that blankets
    /// the viewport: `GameScene.routeTouch(at:)` returns any non-`uiLayer`
    /// hit before it looks at `worldLayer`, so a full-bleed backdrop here
    /// would swallow every touch (AC4) and paint over `worldLayer` from
    /// CYBERPUN-17-3 on.
    /// `TouchRoutingTests.test_mountedGameplayScreen_doesNotBlockWorldTouches`
    /// pins the routing consequence; this pins the structure.
    func test_gameplayScreenNode_mountsNoViewportBlanketingBackdrop() {
        let gameplay = GameplayScreenNode()
        let size = CGSize(width: 800, height: 400)

        gameplay.layout(for: size, safeAreaInsets: .zero)

        let viewport = CGRect(
            x: -size.width / 2, y: -size.height / 2,
            width: size.width, height: size.height
        )
        for child in gameplay.node.children {
            let frame = child.calculateAccumulatedFrame()
            XCTAssertFalse(
                frame.contains(viewport),
                "\(child.name ?? "\(type(of: child))") blankets the viewport; the world must stay "
                    + "reachable behind the gameplay screen"
            )
        }

        // The loop above is a containment check, and this screen's only child
        // is the frameless container marker - so state the structural fact
        // directly rather than letting the gate pass because there was
        // nothing with a frame to measure: unlike menu / death /
        // high-scores, this screen mounts no backdrop sprite at all.
        XCTAssertFalse(
            gameplay.node.children.contains { $0 is SKSpriteNode },
            "the gameplay screen must mount no backdrop sprite; the scene's own backgroundColor "
                + "supplies the dark base and the world renders through this screen"
        )
    }

    /// The gameplay screen used to mount a neon "GAMEPLAY - WORLD COMING
    /// SOON" label from the days when `worldLayer` was empty on entry to
    /// `.gameplay`. The streamed ground plane (CYBERPUN-17-4), the building
    /// and rooftop-sign nodes (CYBERPUN-17-5) and the player actor
    /// (CYBERPUN-17-6) now all render there, so that label sat on top of the
    /// very content it denied - a screen that visually contradicts itself
    /// reads as "feature not delivered" to a human or a screenshot-driven
    /// verification, however correct the rendering behind it is.
    ///
    /// This pins the removal (CYBERPUN-17-5-t4) rather than trusting a
    /// deleted line to stay deleted. It walks the whole subtree, not just the
    /// immediate children, so re-introducing the text inside a HUD container
    /// fails here too. It deliberately does *not* forbid `SKLabelNode`
    /// outright: CYBERPUN-17-7 / CYBERPUN-17-12 add real HUD text (HP, XP,
    /// timer), which must not have to fight this gate.
    func test_gameplayScreenNode_mountsNoComingSoonText() {
        let gameplay = GameplayScreenNode()

        // Both before and after layout: the removal must not be something a
        // layout pass could put back.
        for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 20, left: 0, bottom: 40, right: 0)] {
            gameplay.layout(for: CGSize(width: 800, height: 400), safeAreaInsets: insets)

            for label in Self.labelNodes(in: gameplay.node) {
                let text = label.text ?? ""
                XCTAssertFalse(
                    text.uppercased().contains("COMING SOON"),
                    "the gameplay screen must not mount placeholder text over the rendered city: "
                        + "found \"\(text)\" on \(label.name ?? "an unnamed SKLabelNode")"
                )
            }
        }
    }

    /// Anti-vacuity guard for the gate above: `GameplayScreenNode` mounts no
    /// labels at all now, so that assertion iterates an empty collection and
    /// would stay green even if `labelNodes(in:)` were blind. This proves the
    /// walk really does surface a label, including one nested inside a
    /// container (the shape a future HUD would use).
    func test_labelNodeWalk_findsNestedLabels_soTheComingSoonGateIsNotVacuous() {
        let root = SKNode()
        let container = SKNode()
        let nested = SKLabelNode(text: "WORLD COMING SOON")
        nested.name = "nestedPlaceholder"
        container.addChild(nested)
        root.addChild(container)
        root.addChild(SKLabelNode(text: "TOP LEVEL"))

        let found = Self.labelNodes(in: root)

        XCTAssertEqual(
            Set(found.map { $0.text ?? "" }), ["WORLD COMING SOON", "TOP LEVEL"],
            "the label walk must reach both a direct child and one nested inside a container"
        )
    }

    /// Recursive so a label nested inside a future HUD container is still
    /// seen by the gate above.
    private static func labelNodes(in root: SKNode) -> [SKLabelNode] {
        root.children.flatMap { child -> [SKLabelNode] in
            let nested = labelNodes(in: child)
            return (child as? SKLabelNode).map { [$0] + nested } ?? nested
        }
    }

    func test_gameplayScreenNode_willEnterAndWillExit_areNoOps() {
        let gameplay = GameplayScreenNode()
        gameplay.willEnter()
        gameplay.willExit()
        // Nothing to assert beyond "did not crash" \u2014 the skeleton screen has
        // no state machine of its own yet.
    }

    // MARK: - DeathScreenNode

    func test_deathScreenNode_runAgainButton_runsTheSuppliedClosure() {
        var runAgainTapped = false
        let death = DeathScreenNode(onRunAgain: { runAgainTapped = true }, onBackToMenu: {})

        death.runAgainButton.handleTouch()

        XCTAssertTrue(runAgainTapped)
    }

    func test_deathScreenNode_backToMenuButton_runsTheSuppliedClosure() {
        var backToMenuTapped = false
        let death = DeathScreenNode(onRunAgain: {}, onBackToMenu: { backToMenuTapped = true })

        death.backToMenuButton.handleTouch()

        XCTAssertTrue(backToMenuTapped)
    }

    func test_deathScreenNode_layout_keepsButtonsDistinct() {
        let death = DeathScreenNode(onRunAgain: {}, onBackToMenu: {})

        death.layout(for: CGSize(width: 400, height: 800), safeAreaInsets: .zero)

        XCTAssertNotEqual(death.runAgainButton.position.y, death.backToMenuButton.position.y)
    }

    // MARK: - HighScoresScreenNode

    func test_highScoresScreenNode_backToMenuButton_runsTheSuppliedClosure() {
        var backToMenuTapped = false
        let highScores = HighScoresScreenNode(onBackToMenu: { backToMenuTapped = true })

        highScores.backToMenuButton.handleTouch()

        XCTAssertTrue(backToMenuTapped)
    }

    func test_highScoresScreenNode_layout_resizesBackgroundToSceneSize() {
        let highScores = HighScoresScreenNode(onBackToMenu: {})
        let size = CGSize(width: 400, height: 800)

        highScores.layout(for: size, safeAreaInsets: .zero)

        let background = highScores.node.children.compactMap { $0 as? SKSpriteNode }.first
        XCTAssertEqual(background?.size, size)
    }
}
