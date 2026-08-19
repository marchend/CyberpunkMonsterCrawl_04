import CoreGraphics
import SpriteKit
import UIKit
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

    // MARK: - Radial cooldown overlay geometry

    /// The sweeping wedge is the only thing that makes this node more than a
    /// two-value alpha toggle, and it is the only part with real geometry in
    /// it -- so it is asserted through the node's own child rather than
    /// inferred from `alpha`/`isOnCooldown`.
    private func cooldownOverlay(
        of button: PulseButton,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SKShapeNode {
        let overlay = button.childNode(withName: "pulseButton.cooldownOverlay") as? SKShapeNode
        return try XCTUnwrap(overlay, "pulseButton.cooldownOverlay child is missing", file: file, line: line)
    }

    func test_cooldownOverlay_isHiddenWithNoPath_whenReady() throws {
        let button = PulseButton(onPress: {})
        let overlay = try cooldownOverlay(of: button)

        button.setCooldownProgress(1.0)

        XCTAssertTrue(overlay.isHidden)
        XCTAssertNil(overlay.path)
    }

    /// The regression this suite most needed: at `progress == 0` the wedge
    /// spans the whole circle, which as a swept arc would be the ambiguous
    /// `endAngle == startAngle - 2*pi` full turn. If that collapses to a
    /// zero-length sweep, the just-fired button renders with no dark wedge
    /// at all and only the dimmed `cooldownAlpha` -- caught here by the
    /// path's own bounding box, not by any alpha assertion.
    func test_cooldownOverlay_coversTheWholeCircle_immediatelyAfterAFire() throws {
        let button = PulseButton(onPress: {})
        let overlay = try cooldownOverlay(of: button)

        button.setCooldownProgress(0)

        XCTAssertFalse(overlay.isHidden)
        let path = try XCTUnwrap(overlay.path)
        XCTAssertFalse(path.isEmpty)

        let box = path.boundingBox
        XCTAssertEqual(box.width, PulseButton.size.width, accuracy: 1e-3)
        XCTAssertEqual(box.height, PulseButton.size.height, accuracy: 1e-3)

        // A point in the upper-left quadrant is inside a *full* circle but
        // outside every partial wedge (which sweeps clockwise from straight
        // up, so the upper-left is the last region it reaches).
        XCTAssertTrue(path.contains(CGPoint(x: -18, y: 18)))
    }

    /// `setOnCooldown(true)` is the boolean door to that same full-circle
    /// state, so it gets the same geometry assertion rather than only the
    /// derived-bool one.
    func test_cooldownOverlay_coversTheWholeCircle_afterSetOnCooldownTrue() throws {
        let button = PulseButton(onPress: {})
        let overlay = try cooldownOverlay(of: button)

        button.setOnCooldown(true)

        XCTAssertFalse(overlay.isHidden)
        let path = try XCTUnwrap(overlay.path)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.contains(CGPoint(x: -18, y: 18)))
    }

    /// The wedge is swept *away* as the cooldown counts down, so a later
    /// progress value must cover strictly less than an earlier one.
    func test_cooldownOverlay_wedgeShrinksAsTheCooldownCountsDown() throws {
        let button = PulseButton(onPress: {})
        let overlay = try cooldownOverlay(of: button)

        button.setCooldownProgress(0.25)
        let earlyBox = try XCTUnwrap(overlay.path).boundingBox
        // Three quarters remaining still reaches past the circle's centre
        // on both axes.
        XCTAssertTrue(earlyBox.contains(CGPoint(x: -18, y: -18)))

        button.setCooldownProgress(0.75)
        let lateBox = try XCTUnwrap(overlay.path).boundingBox

        XCTAssertLessThan(
            lateBox.width * lateBox.height,
            earlyBox.width * earlyBox.height,
            "the remaining wedge must shrink as cooldownProgress rises"
        )
    }

    // MARK: - Reusable, no gameplay-type dependency

    /// This node must stay presentation-only: no `PulseAbility` or
    /// `GameScene` symbol referenced in its own file. The absence of a
    /// dependency is a compile-time property a test cannot read directly,
    /// so what is asserted instead is the observable consequence: built
    /// with nothing but a plain closure, the button is *already* fully
    /// configured and inert -- it fires nothing on its own, reads ready,
    /// and carries its accessibility identity without any gameplay type
    /// having been consulted.
    func test_isConstructibleWithOnlyAPlainClosure_andIsFullyConfiguredAndInert() {
        var pressCount = 0

        let button = PulseButton(onPress: { pressCount += 1 })

        XCTAssertEqual(pressCount, 0, "construction alone must never fire the press callback")
        XCTAssertFalse(button.isOnCooldown)
        XCTAssertEqual(button.alpha, PulseButton.readyAlpha, accuracy: 1e-6)
        XCTAssertTrue(button.isAccessibilityElement)
        XCTAssertEqual(button.accessibilityIdentifier, "gameplay.pulseButton")
        XCTAssertEqual(button.accessibilityLabel, "Pulse ability")
    }

    // MARK: - Reserved-slot size parity

    /// Pins `PulseButton.size` against `FloatingThumbstickNode
    /// .pulseButtonSlotSize` -- the slot a later wiring PR mounts this node
    /// into -- so the two can never silently drift apart.
    func test_size_matchesTheThumbsticksReservedPulseButtonSlotSize() {
        XCTAssertEqual(PulseButton.size, FloatingThumbstickNode.pulseButtonSlotSize)
    }
}
