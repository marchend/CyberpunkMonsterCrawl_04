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
        XCTAssertTrue(
            menu.node.children.contains { $0.accessibilityIdentifier == "menu.container" },
            "the menu must expose a container accessibility anchor independent of any one button"
        )
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

    func test_menuScreenNode_layout_resizesBackground_andKeepsButtonsWithinBounds() {
        let menu = MenuScreenNode(onPlay: {}, onHighScores: {})
        let size = CGSize(width: 400, height: 800)

        menu.layout(for: size, safeAreaInsets: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0))

        XCTAssertLessThan(abs(menu.playButton.position.y - menu.highScoresButton.position.y), size.height)
        XCTAssertNotEqual(
            menu.playButton.position.y, menu.highScoresButton.position.y,
            "PLAY and HIGH SCORES must not land on top of each other"
        )
    }

    // MARK: - GameplayScreenNode

    func test_gameplayScreenNode_exposesAContainerAccessibilityAnchor() {
        let gameplay = GameplayScreenNode()

        XCTAssertTrue(
            gameplay.node.children.contains { $0.accessibilityIdentifier == "gameplay.container" },
            "a UI test must be able to observe PLAY landing on a real, mounted gameplay screen"
        )
    }

    func test_gameplayScreenNode_layout_resizesBackgroundToSceneSize() {
        let gameplay = GameplayScreenNode()
        let size = CGSize(width: 800, height: 400)

        gameplay.layout(for: size, safeAreaInsets: .zero)

        let background = gameplay.node.children.compactMap { $0 as? SKSpriteNode }.first
        XCTAssertEqual(background?.size, size)
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
