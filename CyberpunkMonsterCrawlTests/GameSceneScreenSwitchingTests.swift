import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Exercises `GameScene`'s state-driven screen registry using
/// `PlaceholderScreenNode` doubles for the slots that have no concrete
/// screen yet (gameplay / death / high scores, which land in
/// CYBERPUN-17-2-t3; `.menu` is a real `MenuScreen` in the composed app -
/// see `GameViewControllerCompositionTests`). Proves a `GameStateMachine`
/// transition correctly calls
/// `willExit()` on the outgoing screen and `willEnter()` on the incoming
/// one, and that the registry's active screen swaps accordingly.
final class GameSceneScreenSwitchingTests: XCTestCase {

    /// Records enter/exit calls in invocation order, independent of
    /// `PlaceholderScreenNode`'s counters, so relative ordering (exit before
    /// enter) is checkable and not just each count individually.
    private final class OrderRecordingScreenNode: ScreenNode {
        let label: String
        let node: SKNode = SKNode()
        private let record: (String) -> Void

        init(label: String, record: @escaping (String) -> Void) {
            self.label = label
            self.record = record
        }

        func willEnter() { record("\(label).willEnter") }
        func willExit() { record("\(label).willExit") }
        func layout(for size: CGSize, safeAreaInsets: UIEdgeInsets) {}
    }

    private func makeScene() -> GameScene {
        GameScene(size: CGSize(width: 400, height: 800))
    }

    // MARK: - Registration-time activation

    func test_registeringScreenForCurrentState_activatesItImmediately() {
        let scene = makeScene() // GameStateMachine starts in .menu
        let menu = PlaceholderScreenNode(label: "menu")

        scene.register(menu, for: .menu)

        XCTAssertEqual(menu.enterCount, 1)
        XCTAssertEqual(menu.exitCount, 0)
        XCTAssertTrue(scene.activeScreen === menu)
        XCTAssertTrue(menu.node.parent === scene.uiLayer)
    }

    func test_registeringScreenForNonCurrentState_doesNotActivateIt() {
        let scene = makeScene() // .menu is current; .gameplay is not
        let gameplay = PlaceholderScreenNode(label: "gameplay")

        scene.register(gameplay, for: .gameplay)

        XCTAssertEqual(gameplay.enterCount, 0)
        XCTAssertNil(gameplay.node.parent)
        XCTAssertNil(scene.activeScreen)
    }

    func test_registeringAReplacementForTheActiveState_swapsTheMountedScreen() {
        let scene = makeScene() // .menu is current
        let original = PlaceholderScreenNode(label: "menu")
        let replacement = PlaceholderScreenNode(label: "menu-v2")
        scene.register(original, for: .menu) // activates immediately

        scene.register(replacement, for: .menu)

        XCTAssertEqual(original.exitCount, 1, "the outgoing screen must receive willExit()")
        XCTAssertNil(original.node.parent, "the outgoing screen must be removed from uiLayer")
        XCTAssertEqual(replacement.enterCount, 1, "the replacement must receive willEnter()")
        XCTAssertTrue(replacement.node.parent === scene.uiLayer, "the replacement must be mounted in uiLayer")
        XCTAssertTrue(
            scene.activeScreen === replacement,
            "registry and scene graph must not disagree after a replace-while-active"
        )
        XCTAssertTrue(scene.screens[.menu] === replacement)
    }

    func test_reRegisteringTheAlreadyActiveScreen_isANoOp() {
        let scene = makeScene()
        let menu = PlaceholderScreenNode(label: "menu")
        scene.register(menu, for: .menu)

        scene.register(menu, for: .menu)

        XCTAssertEqual(menu.enterCount, 1, "a repeat registration must not re-enter the same instance")
        XCTAssertEqual(menu.exitCount, 0, "a repeat registration must not exit the same instance")
        XCTAssertTrue(scene.activeScreen === menu)
        XCTAssertTrue(menu.node.parent === scene.uiLayer)
    }

    func test_registeringAReplacementForANonCurrentState_doesNotMountIt() {
        let scene = makeScene() // .menu is current
        let original = PlaceholderScreenNode(label: "gameplay")
        let replacement = PlaceholderScreenNode(label: "gameplay-v2")
        scene.register(original, for: .gameplay)

        scene.register(replacement, for: .gameplay)

        XCTAssertEqual(original.enterCount, 0)
        XCTAssertEqual(original.exitCount, 0)
        XCTAssertEqual(replacement.enterCount, 0)
        XCTAssertNil(scene.activeScreen)
        XCTAssertTrue(scene.screens[.gameplay] === replacement)
    }

    // MARK: - Legal transition swaps the active screen

    func test_legalTransition_exitsOldScreen_entersNewScreen_swapsActiveScreen() {
        let scene = makeScene()
        let menu = PlaceholderScreenNode(label: "menu")
        let gameplay = PlaceholderScreenNode(label: "gameplay")
        scene.register(menu, for: .menu) // activates immediately
        scene.register(gameplay, for: .gameplay)

        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertEqual(menu.exitCount, 1, "outgoing screen must receive willExit()")
        XCTAssertNil(menu.node.parent, "outgoing screen must be removed from uiLayer")
        XCTAssertEqual(gameplay.enterCount, 1, "incoming screen must receive willEnter()")
        XCTAssertTrue(gameplay.node.parent === scene.uiLayer, "incoming screen must be mounted in uiLayer")
        XCTAssertTrue(scene.activeScreen === gameplay, "registry's active screen must swap")
    }

    func test_transitionToStateWithNoRegisteredScreen_stillExitsOldScreen_leavesNoneActive() {
        let scene = makeScene()
        let menu = PlaceholderScreenNode(label: "menu")
        scene.register(menu, for: .menu)

        // menu -> highScores is legal (docs/bootstrap.md), and .highScores
        // has no registered screen in this PR.
        XCTAssertTrue(scene.stateMachine.transition(to: .highScores))

        XCTAssertEqual(menu.exitCount, 1)
        XCTAssertNil(menu.node.parent)
        XCTAssertNil(scene.activeScreen)
    }

    func test_illegalTransition_leavesActiveScreenUntouched() {
        let scene = makeScene()
        let menu = PlaceholderScreenNode(label: "menu")
        scene.register(menu, for: .menu)

        // menu -> death is illegal.
        XCTAssertFalse(scene.stateMachine.transition(to: .death))

        XCTAssertEqual(menu.exitCount, 0, "a rejected transition must never trigger willExit()")
        XCTAssertTrue(scene.activeScreen === menu)
        XCTAssertTrue(menu.node.parent === scene.uiLayer)
    }

    // MARK: - Ordering: outgoing exit happens before incoming enter

    func test_outgoingWillExit_firesBeforeIncomingWillEnter() {
        let scene = makeScene()
        var order: [String] = []
        let menu = OrderRecordingScreenNode(label: "menu") { order.append($0) }
        let gameplay = OrderRecordingScreenNode(label: "gameplay") { order.append($0) }
        scene.register(menu, for: .menu)
        scene.register(gameplay, for: .gameplay)

        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertEqual(order, ["menu.willExit", "gameplay.willEnter"])
    }

    // MARK: - Layout hook

    func test_activation_callsLayoutWithCurrentSceneSize() {
        let scene = makeScene()
        let menu = PlaceholderScreenNode(label: "menu")

        scene.register(menu, for: .menu)

        XCTAssertEqual(menu.lastLayoutSize, scene.size)
    }

    func test_didChangeSize_relayoutsTheActiveScreen() {
        let scene = makeScene()
        let menu = PlaceholderScreenNode(label: "menu")
        scene.register(menu, for: .menu)
        let oldSize = scene.size

        scene.size = CGSize(width: 800, height: 400)
        scene.didChangeSize(oldSize)

        XCTAssertEqual(menu.lastLayoutSize, scene.size)
    }
}
