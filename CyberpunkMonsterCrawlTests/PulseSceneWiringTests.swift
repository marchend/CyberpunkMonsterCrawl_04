import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10-t3`: the pulse ability's *scene* wiring -- `PulseButton`
/// press -> `PulseAbility.trigger(...)` -> applied positions/damage on live
/// `RaccoonNode`s -> `PulseRingNode` spawn/replay -> per-frame cooldown
/// display. Mirrors the shape `PlayerCombatSceneWiringTests` established
/// for the auto-fire weapon: assert on the scene's own mounted state
/// (`pulseButton`, `pulseRing`, `pulseAbility`) and drive
/// `applyPulseTrigger(raccoons:)` directly against a hand-built swarm
/// rather than waiting on `RaccoonSpawnDirector`'s own spawn timing/
/// randomness, exactly the "test the wiring, not the spawn director's
/// randomness" shape that type's tests already use.
final class PulseSceneWiringTests: XCTestCase {

    private let sceneSize = CGSize(width: 400, height: 800)

    private func makeGameplayScene() -> GameScene {
        let scene = GameScene(size: sceneSize)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    /// The exact screen-position projection `GameScene.applyPulseHit(_:)`
    /// applies -- restated here (not reached into, since that method is
    /// private) so a test can compute the same expected value rather than
    /// duplicating a looser tolerance-based comparison.
    private func expectedScreenPosition(for tile: TilePoint) -> CGPoint {
        PixelCrispness.snappedPosition(for: IsometricProjection.tileToScreen(tile), scale: 1)
    }

    // MARK: - Mount / layout / visibility

    func test_pulseButton_isMountedAtTheReservedSlotsCentre() {
        let scene = GameScene(size: sceneSize)
        let slot = FloatingThumbstickNode.reservedPulseButtonSlot(forSize: scene.size, safeAreaInsets: .zero)
        XCTAssertEqual(scene.pulseButton.position, CGPoint(x: slot.midX, y: slot.midY))
    }

    func test_pulseButton_isHiddenBeforeAnyRun_shownDuringGameplay_hiddenAgainOutsideIt() {
        let scene = GameScene(size: sceneSize)
        XCTAssertTrue(scene.pulseButton.isHidden, "no run is active before the first .gameplay entry")

        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertFalse(scene.pulseButton.isHidden, "the button must be visible during a run")

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.pulseButton.isHidden, "the button must hide again once the run has ended")
    }

    func test_pulseRing_startsHidden_underEffectsLayer() {
        let scene = GameScene(size: sceneSize)
        XCTAssertTrue(scene.pulseRing.isHidden)
        XCTAssertTrue(scene.pulseRing.parent === scene.effectsLayer)
    }

    // MARK: - Structural invariants still hold with the pulse mounted

    func test_pulseWiring_keepsTheScenesLayerAndDispatchInvariantsIntact() {
        let scene = makeGameplayScene()

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "the pulse button/ring escaped their layer band: \(scene.layerBandViolationReport())"
        )
        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().isEmpty,
            "the pulse button opted into UIKit touch delivery and would bypass the scene's dispatch."
        )
    }

    // MARK: - Pressing the real button fires the real ability

    func test_pressingThePulseButton_firesTheAbility_evenWithNoRaccoonsInRange() {
        let scene = makeGameplayScene()
        XCTAssertFalse(scene.pulseAbility.isOnCooldown, "a fresh ability is ready immediately")

        scene.pulseButton.handleTouch()

        XCTAssertTrue(
            scene.pulseAbility.isOnCooldown,
            "PulseButton.onPress must actually invoke PulseAbility.trigger(...) in a real build."
        )
        XCTAssertFalse(
            scene.pulseRing.isHidden,
            "firing must play the ring even when PulseAbility.Result.hits is empty -- the pulse itself still fired."
        )
    }

    // MARK: - Product gate 1's routing half: the touch reaches the button

    /// The half `handleTouch()` alone cannot prove (PR #48 review): that a
    /// touch landing on the button's own slot actually *resolves* to
    /// `pulseButton` rather than being swallowed by another `uiLayer` node
    /// or handed to `thumbstick` -- the slot sits inside
    /// `FloatingThumbstickNode.leftRegion`, and only
    /// `canBeginTouch(at:)`'s reserved-slot exclusion keeps the stick off
    /// it. `dispatchTouch(atScenePoint:)` is the documented seam for this
    /// (`UITouch` cannot be constructed with a location in a unit test),
    /// and is also what `SceneAccessibilityContainerView.forwardTouch`
    /// funnels the journey's vision-driven tap into.
    func test_aTouchAtThePulseButtonsSlot_routesToTheButton_andFiresTheAbility() {
        let scene = makeGameplayScene()
        XCTAssertFalse(scene.pulseAbility.isOnCooldown, "precondition: a fresh ability is ready.")

        let responder = scene.dispatchTouch(atScenePoint: scene.pulseButton.position)

        XCTAssertTrue(
            responder === scene.pulseButton,
            "a touch on the reserved slot must resolve to PulseButton, not to another uiLayer node."
        )
        XCTAssertTrue(
            scene.pulseAbility.isOnCooldown,
            "the routed touch must reach PulseAbility.trigger(...), not merely hit-test the button."
        )
        XCTAssertFalse(scene.pulseRing.isHidden, "a routed press must play the ring.")
    }

    /// The other side of the same seam: the movement stick must refuse the
    /// button's slot, so a press can never be stolen mid-routing by the
    /// thumbstick that surrounds it.
    func test_theThumbstick_refusesATouchOnThePulseButtonsSlot() {
        let scene = makeGameplayScene()

        XCTAssertFalse(
            scene.thumbstick.canBeginTouch(at: scene.uiLayer.convert(scene.pulseButton.position, from: scene)),
            "the stick must exclude the reserved pulse-button slot, or a press would start a drag instead."
        )
    }

    // MARK: - Off cooldown: push + damage + ring, all in the same tick

    func test_applyPulseTrigger_whenOffCooldown_pushesAndDamagesRaccoons_andSpawnsTheRing_inOneCall() throws {
        let scene = makeGameplayScene()
        let origin = try XCTUnwrap(scene.playerWorldPosition)

        let raccoon = RaccoonNode(tier: .base)
        let candidatePosition = TilePoint(x: origin.x + 1, y: origin.y)

        let result = try XCTUnwrap(
            scene.applyPulseTrigger(raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: candidatePosition)]),
            "an off-cooldown trigger must return a Result."
        )

        XCTAssertEqual(result.hits.count, 1)
        let hit = try XCTUnwrap(result.hits.first)
        XCTAssertTrue(hit.raccoon === raccoon)

        XCTAssertLessThan(raccoon.hp, RaccoonNode.baseMaxHP, "the raccoon must have taken damage.")
        XCTAssertEqual(raccoon.hp, RaccoonNode.baseMaxHP - hit.damage)

        XCTAssertEqual(
            raccoon.position, expectedScreenPosition(for: hit.newPosition),
            "the raccoon's on-screen position must reflect the pulse's pushed tile position."
        )

        XCTAssertFalse(scene.pulseRing.isHidden, "a successful trigger must play the ring.")
        XCTAssertNotNil(
            scene.pulseRing.action(forKey: PulseRingNode.animationActionKey),
            "the ring animation must be running."
        )
        XCTAssertTrue(scene.pulseAbility.isOnCooldown, "a successful trigger must start the cooldown.")
    }

    // MARK: - On cooldown: nothing observable happens

    func test_applyPulseTrigger_whileOnCooldown_doesNothingObservable_whileTheButtonShowsCooldown() throws {
        let scene = makeGameplayScene()
        let origin = try XCTUnwrap(scene.playerWorldPosition)

        // Burn the cooldown with an empty swarm.
        XCTAssertNotNil(scene.applyPulseTrigger(raccoons: []))
        XCTAssertTrue(scene.pulseAbility.isOnCooldown)

        let raccoon = RaccoonNode(tier: .base)
        let candidatePosition = TilePoint(x: origin.x + 1, y: origin.y)
        let positionBefore = raccoon.position
        let hpBefore = raccoon.hp

        let result = scene.applyPulseTrigger(
            raccoons: [TargetSelection.Candidate(raccoon: raccoon, position: candidatePosition)]
        )

        XCTAssertNil(result, "a trigger while on cooldown must return nil.")
        XCTAssertEqual(raccoon.hp, hpBefore, "no damage may be applied while on cooldown.")
        XCTAssertEqual(raccoon.position, positionBefore, "no push may be applied while on cooldown.")

        // Drive real frames so the cooldown display is refreshed, then run
        // long enough for it to fully elapse.
        var now: TimeInterval = 1
        scene.update(now)
        XCTAssertTrue(scene.pulseButton.isOnCooldown, "the button must show cooldown once a frame has run.")
        XCTAssertLessThan(scene.pulseButton.cooldownProgress, 1)

        while now < 1 + PulseAbility.cooldownSeconds + 1 {
            now += 0.5
            scene.update(now)
        }
        XCTAssertFalse(
            scene.pulseButton.isOnCooldown,
            "the button must read ready again once PulseAbility's cooldown has fully elapsed."
        )
    }

    // MARK: - Dead raccoons are unaffected end-to-end

    func test_applyPulseTrigger_leavesADeadRaccoonWhollyUnaffected() throws {
        let scene = makeGameplayScene()
        let origin = try XCTUnwrap(scene.playerWorldPosition)

        let deadRaccoon = RaccoonNode(tier: .base, hp: 0)
        XCTAssertTrue(deadRaccoon.isDead, "precondition: the raccoon must already be dead.")
        let positionBefore = deadRaccoon.position

        let result = try XCTUnwrap(
            scene.applyPulseTrigger(
                raccoons: [TargetSelection.Candidate(raccoon: deadRaccoon, position: TilePoint(x: origin.x + 1, y: origin.y))]
            )
        )

        XCTAssertTrue(result.hits.isEmpty, "a dead raccoon must never produce a Hit.")
        XCTAssertEqual(deadRaccoon.hp, 0, "a dead raccoon's hp must never change.")
        XCTAssertEqual(deadRaccoon.position, positionBefore, "a dead raccoon must never be pushed.")
    }

    // MARK: - No mounted player yet: a no-op, never a crash

    func test_applyPulseTrigger_withNoRunMounted_isANoOp() {
        let scene = GameScene(size: sceneSize)
        XCTAssertNil(scene.playerWorldPosition, "precondition: no run has started yet.")

        XCTAssertNil(scene.applyPulseTrigger(raccoons: []))
    }
}
