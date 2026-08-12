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
        XCTAssertTrue(scene.activeScreen is MenuScreen, "the app must launch into the menu screen")
        XCTAssertTrue(scene.screens[.menu] is MenuScreen)
        XCTAssertTrue(scene.activeScreen?.node.parent === scene.uiLayer, "the menu must be mounted in uiLayer")
    }

    func test_compositionRoot_scene_satisfiesTheLayerAndDispatchInvariants() {
        let scene = makeScene()

        XCTAssertTrue(scene.nodesEscapingTheirLayerBand().isEmpty)
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
    }

    func test_compositionRoot_playButton_isWiredToTheStateMachine() throws {
        let scene = makeScene()
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreen)

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
}
