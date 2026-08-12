import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Guards the composition root: the app must actually build and present the
/// layered `GameScene` with a menu registered, rather than shipping an
/// architecture no production code constructs. Without this, every
/// `GameScene` test could stay green while the binary launched into
/// something else entirely - the v1 failure shape.
final class GameViewControllerCompositionTests: XCTestCase {

    private func makeScene() -> GameScene {
        GameViewController().makeGameScene(size: CGSize(width: 400, height: 800))
    }

    func test_compositionRoot_buildsAGameScene_withTheMenuScreenMounted() {
        let scene = makeScene()

        XCTAssertEqual(scene.stateMachine.currentState, .menu)
        XCTAssertTrue(scene.activeScreen is MenuScreenNode, "the app must launch into the menu screen")
        XCTAssertTrue(scene.screens[.menu] is MenuScreenNode)
        XCTAssertTrue(scene.activeScreen?.node.parent === scene.uiLayer, "the menu must be mounted in uiLayer")
    }

    func test_compositionRoot_registersSkeletonScreens_forGameplayDeathAndHighScores() {
        let scene = makeScene()

        XCTAssertTrue(scene.screens[.gameplay] is GameplayScreenNode)
        XCTAssertTrue(scene.screens[.death] is DeathScreenNode)
        XCTAssertTrue(scene.screens[.highScores] is HighScoresScreenNode)
    }

    func test_compositionRoot_scene_satisfiesTheLayerAndDispatchInvariants() {
        let scene = makeScene()

        XCTAssertTrue(scene.nodesEscapingTheirLayerBand().isEmpty)
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
    }

    func test_compositionRoot_playButton_isWiredToTheStateMachine() throws {
        let scene = makeScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        scene.dispatchTouch(atScenePoint: menu.playButton.position)

        XCTAssertEqual(
            scene.stateMachine.currentState,
            .gameplay,
            "tapping PLAY in the composed scene must start a run"
        )
    }

    func test_compositionRoot_usesResizeFill_soTheMenuWorksInBothOrientations() {
        XCTAssertEqual(makeScene().scaleMode, .resizeFill)
    }

    /// The entry-point wiring for the accessibility-frame fix.
    ///
    /// `AccessibleSKView` is what gives every UI node a correct screen-space
    /// `accessibilityFrame`, so a tap driven by accessibility element
    /// (XCUITest, the scripted runtime probe, VoiceOver) lands on the button
    /// instead of missing it - the "tapped PLAY, screen stayed on the menu"
    /// failure. It only helps if the running app actually hosts the scene in
    /// one: reverting `viewDidLoad()` to a plain `SKView` would leave the
    /// class fully tested and completely dead. Asserted against the view
    /// really installed in the hierarchy (not just the declared property
    /// type), so the check cannot pass tautologically.
    func test_compositionRoot_hostsTheSceneInAnAccessibleSKView() throws {
        let controller = GameViewController()
        controller.loadViewIfNeeded()

        let hostedView = try XCTUnwrap(
            controller.view.subviews.first { $0 is SKView } as? SKView,
            "the composition root must install an SKView to host the scene"
        )
        XCTAssertTrue(
            hostedView is AccessibleSKView,
            "the hosted view must be an AccessibleSKView, or accessibility-driven taps miss every button"
        )
        XCTAssertTrue(controller.skView === hostedView)
        XCTAssertTrue(
            hostedView.scene is GameScene,
            "the composition root must present the composed GameScene into that view"
        )
    }

    func test_compositionRoot_menuHighScoresButton_isWiredToTheStateMachine() throws {
        let scene = makeScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        scene.dispatchTouch(atScenePoint: menu.highScoresButton.position)

        XCTAssertEqual(scene.stateMachine.currentState, .highScores)
        XCTAssertTrue(scene.activeScreen is HighScoresScreenNode)
    }

    func test_compositionRoot_deathScreenButtons_areWiredToTheStateMachine() throws {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        let death = try XCTUnwrap(scene.activeScreen as? DeathScreenNode)

        scene.dispatchTouch(atScenePoint: death.runAgainButton.position)

        XCTAssertEqual(
            scene.stateMachine.currentState,
            .gameplay,
            "RUN AGAIN in the composed scene must start a new run"
        )
    }

    func test_compositionRoot_deathScreenBackToMenuButton_isWiredToTheStateMachine() throws {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        let death = try XCTUnwrap(scene.activeScreen as? DeathScreenNode)

        scene.dispatchTouch(atScenePoint: death.backToMenuButton.position)

        XCTAssertEqual(scene.stateMachine.currentState, .menu)
        XCTAssertTrue(scene.activeScreen is MenuScreenNode)
    }

    func test_compositionRoot_highScoresScreenBackToMenuButton_isWiredToTheStateMachine() throws {
        let scene = makeScene()
        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))
        let highScores = try XCTUnwrap(scene.activeScreen as? HighScoresScreenNode)

        scene.dispatchTouch(atScenePoint: highScores.backToMenuButton.position)

        XCTAssertEqual(scene.stateMachine.currentState, .menu)
        XCTAssertTrue(scene.activeScreen is MenuScreenNode)
    }
}
