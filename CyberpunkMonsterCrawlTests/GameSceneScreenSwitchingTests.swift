import XCTest
import SpriteKit
import UIKit
@testable import CyberpunkMonsterCrawl

/// Exercises `GameScene`'s state-driven screen registry using
/// `PlaceholderScreenNode` doubles \u2014 no concrete screens exist yet (they
/// land in PR 3). Proves a `GameStateMachine` transition correctly calls
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
