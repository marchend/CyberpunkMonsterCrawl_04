import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10-t3`: the pulse ability's *scene* wiring -- a press on the
/// HUD's `HUDPulseButton` -> `PulseAbility.trigger(...)` -> applied
/// positions/damage on live `RaccoonNode`s -> `PulseRingNode` spawn/replay ->
/// per-frame cooldown display. Mirrors the shape
/// `PlayerCombatSceneWiringTests` established for the auto-fire weapon:
/// assert on the scene's own mounted state
/// (`hudLayer`, `pulseRing`, `pulseAbility`) and drive
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

    func test_pressingThePulseButton_firesTheAbility_evenWithNoRaccoonsInRange() throws {
        let scene = makeGameplayScene()
        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount the HUD")
        XCTAssertFalse(scene.pulseAbility.isOnCooldown, "a fresh ability is ready immediately")

        hud.pulseButton.handleTouch()

        XCTAssertTrue(
            scene.pulseAbility.isOnCooldown,
            "HUDPulseButton.onPress must actually invoke PulseAbility.trigger(...) in a real build."
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
    /// or handed to `thumbstick`. `dispatchTouch(atScenePoint:)` is the
    /// documented seam for this
    /// (`UITouch` cannot be constructed with a location in a unit test),
    /// and is also what `SceneAccessibilityContainerView.forwardTouch`
    /// funnels the journey's vision-driven tap into.
    /// Since PR #63's review decision the *visible* ability control is the
    /// HUD's bottom-right `HUDPulseButton`, so that is the button this
    /// gate now routes to: the older bottom-left mount is hidden for the
    /// whole run and hidden nodes are excluded from routing by
    /// construction. The ability behind both is the same
    /// `handlePulsePress()`, so the gate itself is unchanged -- a touch
    /// where the player sees a button must fire the real pulse.
    func test_aTouchAtTheVisibleAbilityButtonsSlot_routesToIt_andFiresTheAbility() throws {
        let scene = makeGameplayScene()
        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount the HUD")
        XCTAssertFalse(scene.pulseAbility.isOnCooldown, "precondition: a fresh ability is ready.")

        let responder = scene.dispatchTouch(atScenePoint: hud.pulseButton.position)

        XCTAssertTrue(
            responder === hud.pulseButton,
            "a touch on the HUD button's slot must resolve to HUDPulseButton, not to another uiLayer node."
        )
        XCTAssertTrue(
            scene.pulseAbility.isOnCooldown,
            "the routed touch must reach PulseAbility.trigger(...), not merely hit-test the button."
        )
        XCTAssertFalse(scene.pulseRing.isHidden, "a routed press must play the ring.")
    }

    /// `CYBERPUN-17-14` PR 1, at the scene level: the older bottom-left
    /// mount and the 72x72 hole the movement stick kept refusing for it are
    /// both deleted. PR #63 hid that button but left the reservation, so the
    /// tree shipped a patch of the thumb quadrant where neither the stick
    /// nor any visible button took the touch (recorded as outstanding in
    /// AGENT.md, and raised again on PR #64 as live input degraded by a
    /// placeholder). This pins the resolution from both directions: nothing
    /// claims that point as a button any more, and the stick does claim it.
    /// `FloatingThumbstickNodeTests` pins the node's own predicate.
    func test_aTouchWhereTheRemovedButtonSatIsClaimedByTheThumbstick() {
        let scene = makeGameplayScene()
        let rest = FloatingThumbstickNode.restingPosition(forSize: scene.size, safeAreaInsets: .zero)
        // The deleted slot's own centre: 16pt of gap above the stick's drag
        // radius, then half of the 72pt-tall slot.
        let formerSlotCentre = CGPoint(
            x: rest.x,
            y: rest.y + FloatingThumbstickNode.maxRadius + 16 + 36
        )

        XCTAssertNil(
            scene.dispatchTouch(atScenePoint: scene.convert(formerSlotCentre, from: scene.uiLayer)),
            "no UI responder may sit where the deleted bottom-left pulse button used to be"
        )
        XCTAssertTrue(
            scene.thumbstick.canBeginTouch(at: formerSlotCentre),
            "the stick must accept that touch now, rather than refusing it for a control that no longer exists"
        )
        XCTAssertFalse(
            scene.pulseAbility.isOnCooldown,
            "and nothing may fire the ability from a slot with no button in it"
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
