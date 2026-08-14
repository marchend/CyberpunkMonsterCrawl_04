import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6 PR 1: the walk-cycle frame-timing state machine \u2014 8 fps
/// frame order across multiple elapsed times, and the idle-freezes-to-frame-0
/// behavior.
final class PlayerAnimatorTests: XCTestCase {

    // MARK: - Idle freezes to frame 0

    func test_notMoving_alwaysReturnsFrameZero_regardlessOfElapsedTime() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0, isMoving: false), 0)
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.2, isMoving: false), 0)
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 5.0, isMoving: false), 0)
    }

    // MARK: - 8 fps / 0.125s-per-frame timing while moving

    func test_moving_atTimeZero_returnsFrameZero() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0, isMoving: true), 0)
    }

    func test_moving_withinTheFirstFrameWindow_staysAtFrameZero() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.05, isMoving: true), 0)
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.124, isMoving: true), 0)
    }

    func test_moving_atExactlyOneFrameDuration_advancesToFrameOne() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.125, isMoving: true), 1)
    }

    func test_moving_atExactlyTwoFrameDurations_advancesToFrameTwo() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.25, isMoving: true), 2)
    }

    func test_moving_atExactlyThreeFrameDurations_advancesToFrameThree() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.375, isMoving: true), 3)
    }

    /// A full cycle (4 frames \u00d7 0.125s = 0.5s) wraps back to frame 0 \u2014
    /// `contact\u00b7pass-L\u00b7contact\u00b7pass-R` repeats, it does not run once and
    /// stop.
    func test_moving_afterAFullCycle_wrapsBackToFrameZero() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: 0.5, isMoving: true), 0)
    }

    func test_moving_acrossMultipleCycles_repeatsTheSameFourFrameOrder() {
        let expectedOrder = [0, 1, 2, 3]
        for cycle in 0..<3 {
            for (offset, expectedFrame) in expectedOrder.enumerated() {
                let elapsed = Double(cycle) * 0.5 + Double(offset) * 0.125 + 0.01
                XCTAssertEqual(
                    PlayerAnimator.frameIndex(elapsedTime: elapsed, isMoving: true),
                    expectedFrame,
                    "cycle \(cycle) offset \(offset) (elapsed \(elapsed)s) should be frame \(expectedFrame)."
                )
            }
        }
    }

    // MARK: - Frame order matches contact\u00b7pass-L\u00b7contact\u00b7pass-R

    func test_frameConstants_matchTheContactPassLContactPassROrder() {
        XCTAssertEqual(PlayerAnimator.frameContactFirst, 0)
        XCTAssertEqual(PlayerAnimator.framePassLeft, 1)
        XCTAssertEqual(PlayerAnimator.frameContactSecond, 2)
        XCTAssertEqual(PlayerAnimator.framePassRight, 3)
    }

    // MARK: - Rate constants

    func test_rateConstants_are8fps_pointOneTwoFiveSecondsPerFrame() {
        XCTAssertEqual(PlayerAnimator.framesPerSecond, 8, accuracy: 1e-9)
        XCTAssertEqual(PlayerAnimator.secondsPerFrame, 0.125, accuracy: 1e-9)
        XCTAssertEqual(PlayerAnimator.frameCount, 4)
    }

    // MARK: - Negative elapsed time never traps or goes out of range

    func test_negativeElapsedTime_isTreatedAsZero() {
        XCTAssertEqual(PlayerAnimator.frameIndex(elapsedTime: -1, isMoving: true), 0)
    }
}
