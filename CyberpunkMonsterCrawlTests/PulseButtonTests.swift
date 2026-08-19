import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10` PR 2: `PulseButton` is a self-contained, presentation-
/// only HUD node -- these tests drive it directly through its own public
/// API (`handleTouch()`, `setCooldownProgress(_:)`, `setOnCooldown(_:)`)
/// rather than through a live `SKView`/`GameScene` touch dispatch, exactly
/// like `FloatingThumbstickNodeTests` exercises the thumbstick's producer
/// half in isolation.
///
/// `alpha`/other `SKNode`-backed float quantities are compared with a
/// `1e-6` accuracy per this project's float-comparison convention for
/// values that round through SpriteKit's own (narrower-precision) storage
/// (see `PixelCrispnessTests`), never with exact equality.
final class PulseButtonTests: XCTestCase {

    // MARK: - Press callback fires on every tap (product gate 1)

    func test_handleTouch_firesThePressCallback() {
        var pressCount = 0
        let button = PulseButton(onPress: { pressCount += 1 })

        button.handleTouch()

        XCTAssertEqual(pressCount, 1)
    }

    func test_handleTouch_firesThePressCallback_everyTimeItIsCalled() {
        var pressCount = 0
        let button = PulseButton(onPress: { pressCount += 1 })

        button.handleTouch()
        button.handleTouch()
        button.handleTouch()

        XCTAssertEqual(pressCount, 3)
    }

    /// Product gate 1: "must respond to every press" -- even while the
    /// button's own cooldown visual reads "on cooldown". This node never
    /// gates a press on its own cooldown state; that decision belongs to
    /// whatever the `onPress` closure is wired to in a later PR.
    func test_handleTouch_firesThePressCallback_evenWhileOnCooldown() {
        var pressCount = 0
        let button = PulseButton(onPress: { pressCount += 1 })
        button.setCooldownProgress(0)

        button.handleTouch()

        XCTAssertEqual(pressCount, 1)
    }

    // MARK: - Cooldown state at boundary values

    func test_freshButton_startsReady() {
        let button = PulseButton(onPress: {})

        XCTAssertFalse(button.isOnCooldown)
        XCTAssertEqual(button.cooldownProgress, 1.0, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, PulseButton.readyAlpha, accuracy: 1e-6)
    }

    func test_setCooldownProgress_zero_readsAsOnCooldown() {
        let button = PulseButton(onPress: {})

        button.setCooldownProgress(0)

        XCTAssertTrue(button.isOnCooldown)
        XCTAssertEqual(button.cooldownProgress, 0, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, PulseButton.cooldownAlpha, accuracy: 1e-6)
    }

    func test_setCooldownProgress_mid_readsAsOnCooldown() {
        let button = PulseButton(onPress: {})

        button.setCooldownProgress(0.5)

        XCTAssertTrue(button.isOnCooldown)
        XCTAssertEqual(button.cooldownProgress, 0.5, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, PulseButton.cooldownAlpha, accuracy: 1e-6)
    }

    func test_setCooldownProgress_full_readsAsReady() {
        let button = PulseButton(onPress: {})
        button.setCooldownProgress(0)

        button.setCooldownProgress(1.0)

        XCTAssertFalse(button.isOnCooldown)
        XCTAssertEqual(button.cooldownProgress, 1.0, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, PulseButton.readyAlpha, accuracy: 1e-6)
    }

    /// Out-of-range input is clamped, never left to produce a degenerate
    /// visual (a negative progress or > 1 progress should behave exactly
    /// like their nearest boundary).
    func test_setCooldownProgress_clampsOutOfRangeValues() {
        let button = PulseButton(onPress: {})

        button.setCooldownProgress(-0.5)
        XCTAssertEqual(button.cooldownProgress, 0, accuracy: 1e-6)
        XCTAssertTrue(button.isOnCooldown)

        button.setCooldownProgress(1.5)
        XCTAssertEqual(button.cooldownProgress, 1.0, accuracy: 1e-6)
        XCTAssertFalse(button.isOnCooldown)
    }

    // MARK: - setOnCooldown(_:) boolean convenience

    func test_setOnCooldown_true_snapsToTheFullyOnCooldownBoundary() {
        let button = PulseButton(onPress: {})

        button.setOnCooldown(true)

        XCTAssertTrue(button.isOnCooldown)
        XCTAssertEqual(button.cooldownProgress, 0, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, PulseButton.cooldownAlpha, accuracy: 1e-6)
    }

    func test_setOnCooldown_false_snapsToTheReadyBoundary() {
        let button = PulseButton(onPress: {})
        button.setOnCooldown(true)

        button.setOnCooldown(false)

        XCTAssertFalse(button.isOnCooldown)
        XCTAssertEqual(button.cooldownProgress, 1.0, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, PulseButton.readyAlpha, accuracy: 1e-6)
    }

    // MARK: - Reusable, no gameplay-type dependency

    /// This node must stay presentation-only: no `PulseAbility` or
    /// `GameScene` symbol referenced in its own file. That's inherently
    /// something a test can't assert directly (a compile-time property, not
    /// a runtime one), so it is instead just constructed here with nothing
    /// but a plain closure -- if `PulseButton` ever grew a hidden gameplay
    /// dependency, this initializer call site is the first thing that would
    /// need to change to keep compiling.
    func test_isConstructibleWithOnlyAPlainClosure_noGameplayTypesInvolved() {
        let button = PulseButton(onPress: {})

        XCTAssertNotNil(button)
    }

    // MARK: - Reserved-slot size parity

    /// Pins `PulseButton.size` against `FloatingThumbstickNode
    /// .pulseButtonSlotSize` -- the slot a later wiring PR mounts this node
    /// into -- so the two can never silently drift apart.
    func test_size_matchesTheThumbsticksReservedPulseButtonSlotSize() {
        XCTAssertEqual(PulseButton.size, FloatingThumbstickNode.pulseButtonSlotSize)
    }
}
