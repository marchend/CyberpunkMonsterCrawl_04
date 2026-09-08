import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 2: `HUDLayer.bind(to:)`/`refresh()` forward a
/// `HUDRunModel`'s live values straight into each of the six mounted
/// elements' own `update(...)`, with no intermediate cached state living on
/// `HUDLayer` itself -- mutating the bound model and calling `refresh()`
/// again must always reflect the model's *current* reading, never a stale
/// snapshot taken at `bind(to:)` time.
final class HUDRunModelBindingTests: XCTestCase {

    /// A minimal `HUDRunModel` conformer driven entirely by the test, so
    /// these tests exercise `HUDLayer`'s own binding/forwarding logic in
    /// isolation from `GameScene`'s much larger composition -- the same
    /// "test the wiring against a hand-built double" shape
    /// `PulseSceneWiringTests`/`RaccoonSpawnDirectorTests` already use.
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

    // MARK: - bind(to:) forwards the model's values into every element

    func test_bind_forwardsTheModelsInitialValues_intoEveryElement() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        model.currentHP = 40
        model.maxHP = 100
        model.level = 3
        model.currentXP = 25
        model.xpForNextLevel = 100
        model.elapsedSeconds = 65
        model.kills = 7
        model.pulseCooldownFraction = 0.5
        model.isPulseReady = false

        hud.bind(to: model)

        XCTAssertEqual(hud.hpBar.currentHP, 40)
        XCTAssertEqual(hud.hpBar.maxHP, 100)
        XCTAssertEqual(hud.levelXPBar.level, 3)
        XCTAssertEqual(hud.levelXPBar.currentXP, 25)
        XCTAssertEqual(hud.levelXPBar.xpForNextLevel, 100)
        XCTAssertEqual(hud.runTimer.formattedText, "01:05")
        XCTAssertEqual(hud.killCount.kills, 7)
        XCTAssertEqual(hud.pulseButton.cooldownFraction, 0.5, accuracy: 1e-6)
        XCTAssertFalse(hud.pulseButton.isReady)
    }

    // MARK: - refresh() reflects the model's latest reading -- no stale cache

    func test_refresh_reflectsTheModelsLatestValues_withNoStaleCachedCopy() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)
        XCTAssertEqual(hud.killCount.kills, 0)

        model.currentHP = 10
        model.kills = 12
        model.elapsedSeconds = 5
        hud.refresh()

        XCTAssertEqual(hud.hpBar.currentHP, 10)
        XCTAssertEqual(hud.killCount.kills, 12)
        XCTAssertEqual(hud.runTimer.formattedText, "00:05")

        // A further, unrelated mutation must still show up on the very
        // next refresh -- proving there is no independent stored copy
        // anywhere on HUDLayer that could go stale between updates.
        model.kills = 13
        model.level = 4
        hud.refresh()

        XCTAssertEqual(hud.killCount.kills, 13)
        XCTAssertEqual(hud.levelXPBar.level, 4)
        // Untouched fields must still read the last value written, not
        // reset or drift as a side effect of the unrelated mutation.
        XCTAssertEqual(hud.hpBar.currentHP, 10)
    }

    // MARK: - The pulse button's press reaches the model's triggerPulse()

    func test_pulseButtonPress_invokesTheModelsTriggerPulse() {
        let hud = HUDLayer()
        let model = MockHUDRunModel()
        hud.bind(to: model)

        hud.pulseButton.handleTouch()

        XCTAssertEqual(model.triggerPulseCount, 1, "PulseButton.onPress must invoke the bound model's triggerPulse()")
    }

    func test_rebinding_toADifferentModel_retargetsThePulseButtonsTrigger() {
        let hud = HUDLayer()
        let firstModel = MockHUDRunModel()
        let secondModel = MockHUDRunModel()
        hud.bind(to: firstModel)

        hud.bind(to: secondModel)
        hud.pulseButton.handleTouch()

        XCTAssertEqual(secondModel.triggerPulseCount, 1)
        XCTAssertEqual(firstModel.triggerPulseCount, 0, "a press after rebinding must not reach the old model")
    }

    // MARK: - Rebinding never leaves a stale reading from the old model

    func test_rebinding_toADifferentModel_stopsForwardingFromTheOldOne() {
        let hud = HUDLayer()
        let firstModel = MockHUDRunModel()
        firstModel.kills = 5
        hud.bind(to: firstModel)
        XCTAssertEqual(hud.killCount.kills, 5)

        let secondModel = MockHUDRunModel()
        secondModel.kills = 99
        hud.bind(to: secondModel)
        XCTAssertEqual(hud.killCount.kills, 99)

        firstModel.kills = 1_000
        hud.refresh()

        XCTAssertEqual(
            hud.killCount.kills, 99,
            "refresh() must read the currently bound model, not a model this layer was previously bound to"
        )
    }

    // MARK: - The live scene's own conformance reads its run state directly

    /// The production end of the same contract: `GameScene`'s `HUDRunModel`
    /// conformance must report *this* run's live state, so a real run's
    /// mutations (a kill recorded on `runStats`, the run clock advancing)
    /// reach the mounted elements on the next `refresh()` with no snapshot
    /// in between.
    func test_theLiveScene_bindsItsOwnRunState_intoTheMountedHUD() throws {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount HUDLayer")
        XCTAssertTrue(hud.runModel === scene, "the mounted HUD must be bound to the scene itself")

        let player = try XCTUnwrap(scene.player, "entering .gameplay must mount the player")
        XCTAssertEqual(hud.hpBar.currentHP, player.hp, "a fresh run's HUD must already read the player's real HP")
        XCTAssertEqual(hud.hpBar.maxHP, player.maxHP)
        XCTAssertEqual(hud.killCount.kills, 0)

        scene.runStats.recordKill()
        hud.refresh()

        XCTAssertEqual(hud.killCount.kills, 1, "a kill recorded on the run's own stats must reach the HUD")
    }
}
