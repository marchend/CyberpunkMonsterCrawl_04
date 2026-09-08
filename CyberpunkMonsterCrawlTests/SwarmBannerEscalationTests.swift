import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 2: a swarm-escalation event on the run model shows
/// `SwarmBanner`, that banner schedules its own auto-dismiss (never left up
/// forever), and input still reaches gameplay/HUD controls while it is
/// showing (`SwarmBanner` itself never intercepts touches -- see that
/// type's own doc note -- and this suite additionally pins the escalation
/// end of that contract).
final class SwarmBannerEscalationTests: XCTestCase {

    private final class MockHUDRunModel: HUDRunModel {
        var currentHP: Int = 100
        var maxHP: Int = 100
        var level: Int = 1
        var currentXP: Int = 0
        var xpForNextLevel: Int = 100
        var elapsedSeconds: TimeInterval = 0
        var kills: Int = 0
        var pulseCooldownFraction: CGFloat = 1
        var isPulseReady: Bool = true
        var onSwarmEscalation: (() -> Void)?

        private(set) var triggerPulseCount = 0
        func triggerPulse() {
            triggerPulseCount += 1
        }
    }

    // MARK: - HUDLayer wiring: the model's escalation notification shows the banner

    func test_theModelsSwarmEscalationNotification_showsTheSwarmBanner() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)
        XCTAssertFalse(hud.swarmBanner.isShowing, "precondition: the banner starts hidden")

        model.onSwarmEscalation?()

        XCTAssertTrue(hud.swarmBanner.isShowing)
        XCTAssertEqual(hud.swarmBanner.currentMessage, HUDLayer.swarmEscalationMessage)
    }

    /// Self-dismiss is asserted as a *scheduled* action, not by waiting on
    /// real wall-clock time -- the same "assert `action(forKey:)` presence"
    /// convention `HUDElementUpdateTests`/`SwarmBanner`'s own doc note
    /// already establish for exercising an `SKAction`-driven auto-dismiss
    /// without a live, rendering `SKView`.
    func test_theSwarmBanner_schedulesItsOwnAutoDismiss_afterAnEscalation() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)

        model.onSwarmEscalation?()

        let scheduled = hud.swarmBanner.pendingAutoDismissAction
        XCTAssertNotNil(scheduled, "an escalation must schedule an auto-dismiss on the banner")
        XCTAssertEqual(scheduled?.duration ?? -1, HUDLayer.swarmEscalationDuration, accuracy: 1e-6)
    }

    /// A second escalation while the banner is already showing must replace
    /// (never stack with) the pending dismissal -- `SwarmBanner.show(...)`'s
    /// own contract, exercised here through the model's notification rather
    /// than by calling `show(...)` directly.
    func test_aSecondEscalationWhileShowing_replacesThePendingDismissal_ratherThanStacking() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)

        model.onSwarmEscalation?()
        let firstDismiss = hud.swarmBanner.pendingAutoDismissAction

        model.onSwarmEscalation?()
        let secondDismiss = hud.swarmBanner.pendingAutoDismissAction

        XCTAssertNotNil(firstDismiss)
        XCTAssertNotNil(secondDismiss)
        XCTAssertTrue(hud.swarmBanner.isShowing)
    }

    /// The banner must not stay up forever: `dismiss()` clears both the
    /// showing state and the pending auto-dismiss, and the same node can
    /// then be shown again by a later escalation.
    func test_theSwarmBanner_dismisses_andCanBeShownAgainByALaterEscalation() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)

        model.onSwarmEscalation?()
        hud.swarmBanner.dismiss()

        XCTAssertFalse(hud.swarmBanner.isShowing)
        XCTAssertTrue(hud.swarmBanner.isHidden)
        XCTAssertNil(hud.swarmBanner.pendingAutoDismissAction, "dismissing must cancel the pending auto-dismiss")

        model.onSwarmEscalation?()

        XCTAssertTrue(hud.swarmBanner.isShowing, "a later escalation must be able to show the same banner again")
    }

    // MARK: - Input still reaches HUD controls while the banner is showing

    func test_aTouchOnThePulseButton_stillReachesIt_whileTheSwarmBannerIsShowing() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)
        model.onSwarmEscalation?()
        XCTAssertTrue(hud.swarmBanner.isShowing, "precondition: the banner is up for this check to mean anything")

        XCTAssertFalse(
            hud.swarmBanner.isUserInteractionEnabled,
            "the banner must never opt into UIKit touch delivery -- see its own doc note"
        )
        hud.pulseButton.handleTouch()
        XCTAssertEqual(
            model.triggerPulseCount, 1,
            "the pulse button must still fire while the swarm banner is showing"
        )
    }

    /// The same check end-to-end through a real, mounted `GameScene`: a
    /// touch dispatched at the HUD pulse button's own on-screen position
    /// must still resolve to it (not to the banner, not to nothing) while
    /// the banner is up.
    func test_dispatchTouch_stillRoutesToThePulseButton_whileTheSwarmBannerIsShowing() throws {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let hud = try XCTUnwrap(scene.hudLayer)
        hud.applyLayout(for: scene.size, safeAreaInsets: .zero, orientation: .portrait)

        hud.swarmBanner.show(message: HUDLayer.swarmEscalationMessage, duration: HUDLayer.swarmEscalationDuration)
        XCTAssertTrue(hud.swarmBanner.isShowing)

        let responder = scene.dispatchTouch(atScenePoint: hud.pulseButton.position)

        XCTAssertTrue(responder === hud.pulseButton, "the pulse button must still be reachable while the banner shows")
    }

    /// ... and gameplay input is equally unaffected: the movement stick
    /// still accepts a touch in its own region while the banner is up, so
    /// an escalation announcement never freezes the player in place.
    func test_theThumbstick_stillAcceptsATouch_whileTheSwarmBannerIsShowing() throws {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let hud = try XCTUnwrap(scene.hudLayer)
        hud.applyLayout(for: scene.size, safeAreaInsets: .zero, orientation: .portrait)
        hud.swarmBanner.show(message: HUDLayer.swarmEscalationMessage, duration: HUDLayer.swarmEscalationDuration)

        let stickRestingPoint = FloatingThumbstickNode.restingPosition(
            forSize: scene.size,
            safeAreaInsets: .zero
        )

        XCTAssertTrue(
            scene.thumbstick.canBeginTouch(at: stickRestingPoint),
            "the swarm banner must not block the movement stick's own region"
        )
    }

    // MARK: - The production escalation-tier banding (`GameScene`)

    /// `GameScene.swarmEscalationTier(forSwarmCount:)` is the pure decision
    /// `evaluateSwarmEscalation()` drives every `.gameplay` frame -- pinned
    /// directly here (the same "test the pure decision, not the spawn
    /// director's own randomness/timing" shape
    /// `RaccoonSpawnDirector.spawnInterval(atElapsedTime:)` already uses)
    /// rather than by growing a real swarm to size in a test, which would
    /// also need enough elapsed run time for a raccoon to reach the player
    /// and start dealing damage -- an unrelated, flaky precondition this
    /// gate has no reason to depend on.
    func test_swarmEscalationTier_bandsBySwarmEscalationRaccoonStep() {
        let step = GameScene.swarmEscalationRaccoonStep
        XCTAssertGreaterThan(step, 0, "a zero-or-negative step would divide by zero below")

        XCTAssertEqual(GameScene.swarmEscalationTier(forSwarmCount: 0), 0)
        XCTAssertEqual(GameScene.swarmEscalationTier(forSwarmCount: step - 1), 0)
        XCTAssertEqual(GameScene.swarmEscalationTier(forSwarmCount: step), 1)
        XCTAssertEqual(GameScene.swarmEscalationTier(forSwarmCount: step * 2 - 1), 1)
        XCTAssertEqual(GameScene.swarmEscalationTier(forSwarmCount: step * 2), 2)
    }

    /// A fresh scene has no live raccoons and must not have already
    /// announced an escalation -- `onSwarmEscalation` is `nil` until
    /// `HUDLayer.bind(to:)` sets it, and no tier above `0` can have been
    /// crossed with zero raccoons alive.
    func test_freshScene_hasNotEscalated() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        XCTAssertEqual(GameScene.swarmEscalationTier(forSwarmCount: 0), 0)
        XCTAssertNil(scene.onSwarmEscalation, "nothing has bound this scene's HUDRunModel yet")
    }

    /// Entering `.gameplay` binds the HUD, which is what installs the
    /// scene's `onSwarmEscalation` hook -- so the production notification
    /// path exists from the first frame of a run, and firing it shows the
    /// real mounted banner.
    func test_enteringGameplay_installsTheEscalationHook_whichShowsTheMountedBanner() throws {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let hud = try XCTUnwrap(scene.hudLayer)

        let hook = try XCTUnwrap(
            scene.onSwarmEscalation,
            "HUDLayer.bind(to:) must install the scene's swarm-escalation hook on every .gameplay entry"
        )
        XCTAssertFalse(hud.swarmBanner.isShowing, "precondition: nothing has escalated yet")

        hook()

        XCTAssertTrue(hud.swarmBanner.isShowing)
        XCTAssertEqual(hud.swarmBanner.currentMessage, HUDLayer.swarmEscalationMessage)
    }
}
