import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-8-t1: the raccoon's `Direction8 -> (row, mirrored)` table (5
/// authored rows mirrored to 8), its `(23, 24)` anchor, and its walk (10fps)
/// / attack (12fps) frame-timing cadence.
final class RaccoonAnimationControllerTests: XCTestCase {

    private let accuracy: CGFloat = 1e-9

    // MARK: - Sheet geometry, delegated to AtlasSheet.raccoonWalk

    func test_sheetGeometry_matchesTheDeclaredAtlasContract() {
        XCTAssertEqual(RaccoonAnimationController.cellSize, CGSize(width: 48, height: 28))
        XCTAssertEqual(RaccoonAnimationController.frameCount, 4)
    }

    // MARK: - Row/mirror table: the 5 directly-authored facings

    func test_directlyAuthoredFacings_mapToRowsZeroThroughFour_unmirrored() {
        let expected: [(Direction8, Int)] = [
            (.south, 0),
            (.southeast, 1),
            (.east, 2),
            (.northeast, 3),
            (.north, 4),
        ]

        for (direction, row) in expected {
            let mapping = RaccoonAnimationController.rowMapping(for: direction)
            XCTAssertEqual(mapping.row, row, "\(direction) should map to row \(row).")
            XCTAssertFalse(mapping.mirrored, "\(direction) should not be mirrored.")
        }
    }

    // MARK: - Row/mirror table: the 3 mirrored facings

    func test_mirroredFacings_reuseTheRowOfTheMatchingVerticalComponent_andAreMirrored() {
        let southwest = RaccoonAnimationController.rowMapping(for: .southwest)
        XCTAssertEqual(southwest.row, RaccoonAnimationController.rowMapping(for: .southeast).row)
        XCTAssertTrue(southwest.mirrored)

        let west = RaccoonAnimationController.rowMapping(for: .west)
        XCTAssertEqual(west.row, RaccoonAnimationController.rowMapping(for: .east).row)
        XCTAssertTrue(west.mirrored)

        let northwest = RaccoonAnimationController.rowMapping(for: .northwest)
        XCTAssertEqual(northwest.row, RaccoonAnimationController.rowMapping(for: .northeast).row)
        XCTAssertTrue(northwest.mirrored)
    }

    func test_rowMapping_isExhaustiveOverEveryDirection8Case() {
        for direction in Direction8.allCases {
            // Would trap via preconditionFailure if any case were missing.
            _ = RaccoonAnimationController.rowMapping(for: direction)
        }
    }

    // MARK: - Anchor: resolves to cell pixel (23, 24)

    /// `(23, 24)`, not the story table's `(23, 20)`: the alpha scan in
    /// `RaccoonSpriteSheetPixelTests` measured the south facing's feet on
    /// row 23 of the cell (silhouette rows 8..<24), so row 20 sat inside the
    /// raccoon's legs and floated its shadow and depth sample 4px high. This
    /// assertion is the arithmetic half of that pairing -- it pins the value
    /// against typos; the pixel scan is what pins it against the art.
    func test_anchorPixel_is23_24_theMeasuredGroundLine() {
        XCTAssertEqual(RaccoonAnimationController.anchorPixel, CGPoint(x: 23, y: 24))
    }

    func test_anchorPointNormalized_convertsThePixelAnchorIntoSpriteKitSpace() {
        let anchor = RaccoonAnimationController.anchorPointNormalized
        let cellSize = RaccoonAnimationController.cellSize

        XCTAssertEqual(anchor.x, 23.0 / cellSize.width, accuracy: accuracy)
        XCTAssertEqual(anchor.y, 1 - 24.0 / cellSize.height, accuracy: accuracy)
    }

    // MARK: - Walk cadence: 10 fps (0.1s per frame)

    func test_walk_atTimeZero_returnsFrameZero() {
        XCTAssertEqual(
            RaccoonAnimationController.frameIndex(elapsedTime: 0, framesPerSecond: RaccoonAnimationController.walkFramesPerSecond),
            0
        )
    }

    /// Asserted at the *midpoint* of each frame window (`frame + 0.5`
    /// scaled by `1/fps`), not at the exact boundary. Neither `1/10` nor
    /// `1/12` (this file's two frame rates) are exact binary fractions the
    /// way `PlayerAnimator`'s `1/8` is, so an elapsed time chosen to sit
    /// exactly on a frame boundary is at the mercy of the same rounding
    /// that famously makes `0.3 / 0.1 == 2.9999999999999996` in IEEE754 --
    /// a real risk here, not a theoretical one. The midpoint keeps a full
    /// half-frame of margin from every boundary on both sides, so the
    /// assertion is robust to that rounding regardless.
    func test_walk_advancesOneFramePerTenthOfASecond() {
        let fps = RaccoonAnimationController.walkFramesPerSecond
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(0, fps: fps), framesPerSecond: fps), 0)
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(1, fps: fps), framesPerSecond: fps), 1)
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(2, fps: fps), framesPerSecond: fps), 2)
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(3, fps: fps), framesPerSecond: fps), 3)
        // A full 4-frame cycle at 10fps takes 0.4s and wraps back to frame 0.
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(4, fps: fps), framesPerSecond: fps), 0)
    }

    // MARK: - Attack cadence: 12 fps (1/12s per frame)

    func test_attack_atTimeZero_returnsFrameZero() {
        XCTAssertEqual(
            RaccoonAnimationController.frameIndex(
                elapsedTime: 0,
                framesPerSecond: RaccoonAnimationController.attackFramesPerSecond
            ),
            0
        )
    }

    /// Same midpoint-of-frame reasoning as the walk cadence test above.
    func test_attack_advancesOneFramePerTwelfthOfASecond() {
        let fps = RaccoonAnimationController.attackFramesPerSecond
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(0, fps: fps), framesPerSecond: fps), 0)
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(1, fps: fps), framesPerSecond: fps), 1)
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(2, fps: fps), framesPerSecond: fps), 2)
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(3, fps: fps), framesPerSecond: fps), 3)
        // A full 4-frame cycle at 12fps wraps back to frame 0.
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: midpoint(4, fps: fps), framesPerSecond: fps), 0)
    }

    /// The midpoint-of-frame `(frame + 0.5) / fps` elapsed time for `frame`
    /// at `fps` -- comfortably inside that frame's window regardless of the
    /// small floating-point jitter an exact boundary multiple would risk
    /// (see the doc comments above).
    private func midpoint(_ frame: Int, fps: Double) -> TimeInterval {
        (Double(frame) + 0.5) / fps
    }

    func test_rateConstants_are10fpsWalk_12fpsAttack() {
        XCTAssertEqual(RaccoonAnimationController.walkFramesPerSecond, 10, accuracy: 1e-9)
        XCTAssertEqual(RaccoonAnimationController.attackFramesPerSecond, 12, accuracy: 1e-9)
        XCTAssertEqual(RaccoonAnimationController.framesPerSecond(for: .walk), 10, accuracy: 1e-9)
        XCTAssertEqual(RaccoonAnimationController.framesPerSecond(for: .attack), 12, accuracy: 1e-9)
    }

    func test_negativeElapsedTime_isTreatedAsZero() {
        XCTAssertEqual(RaccoonAnimationController.frameIndex(elapsedTime: -1, framesPerSecond: 10), 0)
    }

    // MARK: - Instance state machine

    func test_setDirection_updatesDirectionAndRowMapping() {
        let controller = RaccoonAnimationController()
        XCTAssertEqual(controller.direction, .south)

        controller.setDirection(.northeast)

        XCTAssertEqual(controller.direction, .northeast)
        XCTAssertEqual(controller.currentRowMapping, RaccoonAnimationController.rowMapping(for: .northeast))
    }

    func test_playWalk_isTheDefaultState() {
        let controller = RaccoonAnimationController()
        XCTAssertEqual(controller.state, .walk)
    }

    func test_playAttack_switchesState_andResetsTheCycle() {
        let controller = RaccoonAnimationController()

        // Advance partway through the walk cycle first.
        controller.advance(deltaTime: 0.3)
        XCTAssertGreaterThan(controller.currentFrameColumn, 0)

        controller.playAttack()

        XCTAssertEqual(controller.state, .attack)
        XCTAssertEqual(controller.elapsedInCurrentState, 0, accuracy: 1e-9)
        XCTAssertEqual(controller.currentFrameColumn, 0)
    }

    /// The hold that makes the attack sheet observable at all: while an
    /// attack cycle is mid-flight `playWalk()` must not reclaim the sprite.
    ///
    /// `RaccoonSeekBehavior.update` calls `playWalk()` every single frame,
    /// *before* `RaccoonNode.update(deltaTime:)` refreshes `body.texture`,
    /// while `BiteComponent` calls `playAttack()` *after* it -- so without
    /// this hold `.attack` was always cleared on the following frame before
    /// one attack cell had ever been assigned, and `sprite_raccoon_attack`
    /// never drew in a real build (PR #35 review).
    func test_playWalk_duringAnAttackCycle_isHeldOff_soTheAttackFramesCanDraw() {
        let controller = RaccoonAnimationController()
        controller.playAttack()

        // One frame of a 60fps run, far inside the 4-frame attack cycle.
        controller.advance(deltaTime: 1.0 / 60.0)
        XCTAssertTrue(controller.isAttackCycleInProgress)

        controller.playWalk()

        XCTAssertEqual(
            controller.state, .attack,
            "walk must not reclaim the sprite mid-attack - that is what kept the attack sheet off screen"
        )
        XCTAssertEqual(controller.elapsedInCurrentState, 1.0 / 60.0, accuracy: 1e-9)
    }

    func test_playWalk_afterTheAttackCycleCompletes_switchesBack_andResetsTheCycle() {
        let controller = RaccoonAnimationController()
        controller.playAttack()

        // Every frame of the attack cycle has now had its turn.
        controller.advance(deltaTime: RaccoonAnimationController.attackCycleDuration)
        XCTAssertFalse(controller.isAttackCycleInProgress)

        controller.playWalk()

        XCTAssertEqual(controller.state, .walk)
        XCTAssertEqual(controller.elapsedInCurrentState, 0, accuracy: 1e-9)
        XCTAssertEqual(controller.currentFrameColumn, 0)
    }

    /// The hold is exactly one cycle long, not open-ended: a raccoon whose
    /// bite cooldown (1s) is far longer than its attack cycle (0.333s) must
    /// spend the rest of that second back on the walk sheet, not frozen
    /// mid-lunge.
    func test_attackCycleDuration_isTheFullFrameCount_atTheAttackCadence() {
        XCTAssertEqual(
            RaccoonAnimationController.attackCycleDuration,
            Double(RaccoonAnimationController.frameCount)
                / RaccoonAnimationController.attackFramesPerSecond,
            accuracy: 1e-9
        )
        XCTAssertLessThan(
            RaccoonAnimationController.attackCycleDuration,
            BiteComponent.biteIntervalSeconds,
            "an attack cycle must fit inside one bite interval, or the walk animation never returns"
        )
    }

    func test_playWalk_whileAlreadyWalking_isANoOp_andDoesNotResetTheCycle() {
        let controller = RaccoonAnimationController()
        controller.advance(deltaTime: 0.3)
        let elapsedBefore = controller.elapsedInCurrentState

        controller.playWalk()

        XCTAssertEqual(controller.elapsedInCurrentState, elapsedBefore, accuracy: 1e-9)
    }

    func test_playAttack_whileAlreadyAttacking_isANoOp_andDoesNotResetTheCycle() {
        let controller = RaccoonAnimationController(initialState: .attack)
        controller.advance(deltaTime: 1.0 / RaccoonAnimationController.attackFramesPerSecond)
        let elapsedBefore = controller.elapsedInCurrentState

        controller.playAttack()

        XCTAssertEqual(controller.elapsedInCurrentState, elapsedBefore, accuracy: 1e-9)
    }

    func test_currentFrameColumn_tracksTheActiveStatesCadence() {
        let controller = RaccoonAnimationController()
        controller.advance(deltaTime: 0.1) // exactly one walk frame (10fps)
        XCTAssertEqual(controller.currentFrameColumn, 1)

        controller.playAttack()
        XCTAssertEqual(controller.currentFrameColumn, 0)

        controller.advance(deltaTime: 1.0 / RaccoonAnimationController.attackFramesPerSecond)
        XCTAssertEqual(controller.currentFrameColumn, 1)
    }
}
