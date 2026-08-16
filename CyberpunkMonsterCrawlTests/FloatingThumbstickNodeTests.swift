import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 1: `FloatingThumbstickNode` is the input *producer*
/// half of the floating-thumbstick story -- self-contained and driven
/// directly through `beginTouch(at:)`/`updateTouch(at:)`/`endTouch()` rather
/// than through a live `SKView`/`UITouch`, since this PR does not yet wire
/// the node into `GameScene`'s touch dispatch (see the type's own doc
/// comment for that scope note).
///
/// SKNode-backed quantities (`alpha`, positions derived through them) are
/// compared with a `1e-6` accuracy rather than exact/`1e-9` equality,
/// per this project's float-comparison convention for values that round
/// through SpriteKit's own (narrower-precision) storage -- see
/// `PixelCrispnessTests` for the same treatment of `xScale`.
final class FloatingThumbstickNodeTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)
    private let insets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    private func makeLaidOutStick() -> FloatingThumbstickNode {
        let stick = FloatingThumbstickNode()
        stick.layout(for: sceneSize, safeAreaInsets: insets)
        return stick
    }

    // MARK: - Left-region-only touch acceptance

    func test_beginTouch_acceptsATouchInsideTheLeftRegion() {
        let stick = makeLaidOutStick()
        let point = CGPoint(x: stick.restPosition.x, y: stick.restPosition.y + 40)

        XCTAssertTrue(stick.beginTouch(at: point))
    }

    func test_beginTouch_rejectsATouchInsideTheRightHalf() {
        let stick = makeLaidOutStick()

        XCTAssertFalse(stick.beginTouch(at: CGPoint(x: 50, y: 0)))
    }

    /// The motivating case for the exclusion: the reserved pulse-button slot
    /// sits *inside* the stick's own left-region touch box (both live in the
    /// bottom-left "thumb quadrant"), so accepting a touch there would be a
    /// real bug, not one already prevented by the plain left/right split.
    func test_beginTouch_rejectsATouchInsideThePulseButtonReservedSlot() {
        let stick = makeLaidOutStick()
        let slot = FloatingThumbstickNode.reservedPulseButtonSlot(forSize: sceneSize, safeAreaInsets: insets)
        let point = CGPoint(x: slot.midX, y: slot.midY)

        // Sanity: prove this test exercises the exclusion, not the
        // already-covered right-half rejection.
        XCTAssertTrue(
            FloatingThumbstickNode.leftRegion(forSize: sceneSize, safeAreaInsets: insets).contains(point),
            "the reserved slot must sit inside the stick's own left-region touch box for this test to be meaningful"
        )

        XCTAssertFalse(stick.beginTouch(at: point))
    }

    func test_reservedPulseButtonSlot_doesNotOverlapTheSticksOwnRestCircle() {
        let slot = FloatingThumbstickNode.reservedPulseButtonSlot(forSize: sceneSize, safeAreaInsets: insets)
        let rest = FloatingThumbstickNode.restingPosition(forSize: sceneSize, safeAreaInsets: insets)

        XCTAssertGreaterThanOrEqual(
            slot.minY, rest.y + FloatingThumbstickNode.maxRadius,
            "the reserved slot must sit clear above the stick's own drag radius"
        )
    }

    // MARK: - Touch-down appears at the touch location, not at rest

    func test_beginTouch_placesTheStickAtTheTouchLocation() {
        let stick = makeLaidOutStick()
        let point = CGPoint(x: stick.restPosition.x - 10, y: stick.restPosition.y + 15)

        XCTAssertTrue(stick.beginTouch(at: point))
        // No drag has happened yet, so the reading is still centred/resting.
        XCTAssertEqual(stick.stickState, .resting)
    }

    // MARK: - Drag tracking

    func test_updateTouch_tracksADragWithinTheMaxRadius() {
        let stick = makeLaidOutStick()
        let origin = stick.restPosition
        XCTAssertTrue(stick.beginTouch(at: origin))

        stick.updateTouch(at: CGPoint(x: origin.x + 20, y: origin.y))

        let expectedMagnitude = 20 / FloatingThumbstickNode.maxRadius
        XCTAssertEqual(stick.stickState.magnitude, expectedMagnitude, accuracy: 1e-6)
        XCTAssertEqual(stick.stickState.direction.dx, 1, accuracy: 1e-6)
        XCTAssertEqual(stick.stickState.direction.dy, 0, accuracy: 1e-6)
    }

    func test_updateTouch_tracksADiagonalDrag() {
        let stick = makeLaidOutStick()
        let origin = stick.restPosition
        XCTAssertTrue(stick.beginTouch(at: origin))

        let offset: CGFloat = 30
        stick.updateTouch(at: CGPoint(x: origin.x + offset, y: origin.y + offset))

        let expectedMagnitude = (offset * CGFloat(2).squareRoot()) / FloatingThumbstickNode.maxRadius
        XCTAssertEqual(stick.stickState.magnitude, expectedMagnitude, accuracy: 1e-6)
        XCTAssertEqual(stick.stickState.direction.dx, CGFloat(2).squareRoot() / 2, accuracy: 1e-6)
        XCTAssertEqual(stick.stickState.direction.dy, CGFloat(2).squareRoot() / 2, accuracy: 1e-6)
    }

    // MARK: - Clamp to max radius

    func test_updateTouch_clampsMagnitudeAtOne_beyondMaxRadius() {
        let stick = makeLaidOutStick()
        let origin = stick.restPosition
        XCTAssertTrue(stick.beginTouch(at: origin))

        stick.updateTouch(at: CGPoint(x: origin.x + FloatingThumbstickNode.maxRadius * 5, y: origin.y))

        XCTAssertEqual(stick.stickState.magnitude, 1, accuracy: 1e-6)
        XCTAssertEqual(stick.stickState.direction.dx, 1, accuracy: 1e-6)
        XCTAssertEqual(stick.stickState.direction.dy, 0, accuracy: 1e-6)
    }

    // MARK: - Dead zone threshold

    func test_stickState_isBeyondDeadZone_falseJustBelowThreshold_trueJustBeyondIt() {
        // Deliberately not testing bit-exact equality *at* the mathematical
        // threshold (`maxRadius * deadZoneFraction`): that distance is
        // itself a product of two `CGFloat` constants, and comparing a
        // round-tripped (multiply-then-divide) value back against
        // `deadZoneFraction` with a strict `>` risks a false result driven
        // by which side of a single ULP the rounding happens to land on,
        // not by the dead-zone logic under test. A clear margin on both
        // sides exercises the same gate without that risk.
        let stick = makeLaidOutStick()
        let origin = stick.restPosition
        XCTAssertTrue(stick.beginTouch(at: origin))

        let thresholdDistance = FloatingThumbstickNode.maxRadius * FloatingThumbstickNode.deadZoneFraction

        stick.updateTouch(at: CGPoint(x: origin.x + thresholdDistance - 2, y: origin.y))
        XCTAssertFalse(stick.stickState.isBeyondDeadZone, "A drag comfortably short of the threshold must not count as beyond it.")

        stick.updateTouch(at: CGPoint(x: origin.x + thresholdDistance + 2, y: origin.y))
        XCTAssertTrue(stick.stickState.isBeyondDeadZone, "A drag comfortably past the threshold must count as beyond it.")
    }

    // MARK: - Rest/dimmed vs active vs hidden

    func test_stick_isFullyHidden_whileNoRunIsActive() {
        let stick = makeLaidOutStick()
        XCTAssertTrue(stick.isHidden)
    }

    func test_stick_isDimmedButVisible_atRest_duringAnActiveRun() {
        let stick = makeLaidOutStick()
        stick.isRunActive = true

        XCTAssertFalse(stick.isHidden)
        XCTAssertEqual(stick.alpha, FloatingThumbstickNode.restAlpha, accuracy: 1e-6)
        XCTAssertGreaterThan(stick.alpha, 0, "the stick must never be fully invisible during an active run")
    }

    func test_stick_isMoreOpaque_whileATouchIsActive() {
        let stick = makeLaidOutStick()
        stick.isRunActive = true
        XCTAssertTrue(stick.beginTouch(at: stick.restPosition))

        XCTAssertEqual(stick.alpha, FloatingThumbstickNode.activeAlpha, accuracy: 1e-6)
        XCTAssertFalse(stick.isHidden)
    }

    func test_endTouch_returnsToRestPosition_andRestAlpha() {
        let stick = makeLaidOutStick()
        stick.isRunActive = true
        let origin = stick.restPosition
        XCTAssertTrue(stick.beginTouch(at: CGPoint(x: origin.x + 100, y: origin.y)))
        stick.updateTouch(at: CGPoint(x: origin.x + 200, y: origin.y))

        stick.endTouch()

        XCTAssertEqual(stick.stickState, .resting)
        XCTAssertEqual(stick.alpha, FloatingThumbstickNode.restAlpha, accuracy: 1e-6)
    }

    func test_runEnding_cancelsAnInProgressTouch_andHidesTheStick() {
        let stick = makeLaidOutStick()
        stick.isRunActive = true
        XCTAssertTrue(stick.beginTouch(at: stick.restPosition))

        stick.isRunActive = false

        XCTAssertTrue(stick.isHidden)
        XCTAssertEqual(stick.stickState, .resting)
    }

    // MARK: - Safe-area clearance

    func test_restPosition_staysClearOfSafeAreaInsets_onLeftAndBottomEdges() {
        let stick = makeLaidOutStick()
        let minX = -sceneSize.width / 2 + insets.left
        let minY = -sceneSize.height / 2 + insets.bottom

        XCTAssertGreaterThan(stick.restPosition.x - FloatingThumbstickNode.maxRadius, minX)
        XCTAssertGreaterThan(stick.restPosition.y - FloatingThumbstickNode.maxRadius, minY)
    }

    func test_restPosition_shiftsWithSafeAreaInsets() {
        let stickNoInsets = FloatingThumbstickNode()
        stickNoInsets.layout(for: sceneSize, safeAreaInsets: .zero)

        let stickWithInsets = makeLaidOutStick()

        XCTAssertGreaterThan(stickWithInsets.restPosition.y, stickNoInsets.restPosition.y)
    }

    func test_layout_reCentresAnIdleStick_onRotation() {
        let stick = makeLaidOutStick()
        let portraitRest = stick.restPosition

        let landscapeSize = CGSize(width: sceneSize.height, height: sceneSize.width)
        let landscapeInsets = UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)
        stick.layout(for: landscapeSize, safeAreaInsets: landscapeInsets)

        XCTAssertNotEqual(stick.restPosition, portraitRest)
    }
}
