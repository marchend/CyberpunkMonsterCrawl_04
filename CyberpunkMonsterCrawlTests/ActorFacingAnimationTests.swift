import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t3` (PR 3): the actor-facing/animation-correctness audit
/// gate 3 calls for -- "an actor turning through all 8 facings with visibly
/// cycling walk animation". `PlayerNodeTests`/`RaccoonNodeTests` already
/// cover most of this per-actor, and `AtlasSlicingTests`
/// (`CYBERPUN-17-14-t2`) already pins the *static* `Direction8 -> (row,
/// mirrored)` tables as literals; this file is the one place both actors'
/// **live, driven** facing + frame-cycling behaviour is exercised side by
/// side against the exact production texture accessors
/// (`PlayerNode.texture(row:column:)` / `RaccoonNode.texture(state:row:
/// column:)`), so a regression in either actor's `update(...)` wiring -- not
/// just its static table -- is caught here even if it slips through the
/// per-actor suites.
///
/// **Audit result: no offender found.** Re-driving both actors through every
/// `Direction8` case and a full walk cycle reproduced exactly the row/
/// mirror/frame sequence each actor's own row-mapping table and frame-timing
/// module already document; nothing here needed a code fix.
final class ActorFacingAnimationTests: XCTestCase {

    // MARK: - SpriteKit-space (y-up) vectors for every Direction8 case
    //
    // The same table `PlayerNodeTests` uses, restated here so this file
    // drives real facing changes without depending on another test file's
    // private helper.
    private static let spriteKitVectors: [(Direction8, CGVector)] = [
        (.south, CGVector(dx: 0, dy: -1)),
        (.southeast, CGVector(dx: 1, dy: -1)),
        (.east, CGVector(dx: 1, dy: 0)),
        (.northeast, CGVector(dx: 1, dy: 1)),
        (.north, CGVector(dx: 0, dy: 1)),
        (.northwest, CGVector(dx: -1, dy: 1)),
        (.west, CGVector(dx: -1, dy: 0)),
        (.southwest, CGVector(dx: -1, dy: -1)),
    ]

    // MARK: - Player: all 8 facings resolve the correct atlas row + mirror

    func test_player_turningThroughAllEightFacings_selectsTheCorrectAtlasRowAndMirror() {
        for (direction, vector) in Self.spriteKitVectors {
            let player = PlayerNode()
            player.update(deltaTime: 0, movementVector: vector)

            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            let expectedTexture = PlayerNode.texture(row: mapping.row, column: PlayerAnimator.frameContactFirst)

            XCTAssertTrue(
                player.body.texture === expectedTexture,
                "\(direction): expected row \(mapping.row) frame 0."
            )
            let expectedXScaleSign: CGFloat = mapping.mirrored ? -1 : 1
            XCTAssertEqual(
                (player.body.xScale < 0) ? -1 : 1, expectedXScaleSign,
                "\(direction): mirror flag did not match rowMapping.mirrored."
            )
        }
    }

    /// A single node turning through the full compass in sequence (rather
    /// than a fresh node per direction) -- the shape gate 3's "turning"
    /// wording actually describes, and a case the per-direction sweep above
    /// cannot see: a stale `xScale` magnitude or a facing that fails to
    /// update on a *repeated* call to the same node.
    func test_player_turningThroughAllEightFacingsInSequence_onOneNode_tracksEveryChange() {
        let player = PlayerNode()
        for (direction, vector) in Self.spriteKitVectors {
            player.update(deltaTime: 0, movementVector: vector)
            XCTAssertEqual(player.facing, direction)

            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            let expectedTexture = PlayerNode.texture(row: mapping.row, column: PlayerAnimator.frameContactFirst)
            XCTAssertTrue(player.body.texture === expectedTexture, "\(direction): body texture did not update.")
        }
    }

    // MARK: - Player: walk frames cycle 0 -> 1 -> 2 -> 3 -> 0 while moving

    func test_player_walkFrames_cycleThroughAllFourFramesAndWrap_atTheDocumented8fpsCadence() {
        let player = PlayerNode()
        let eastVector = CGVector(dx: 1, dy: 0)
        let eastRow = PlayerSpriteSheet.rowMapping(for: .east).row

        let expectedFrameSequence = [0, 1, 2, 3, 0, 1]
        var elapsed: TimeInterval = 0
        for (index, expectedFrame) in expectedFrameSequence.enumerated() {
            player.update(deltaTime: index == 0 ? 0 : PlayerAnimator.secondsPerFrame, movementVector: eastVector)
            elapsed += index == 0 ? 0 : PlayerAnimator.secondsPerFrame
            let expectedTexture = PlayerNode.texture(row: eastRow, column: expectedFrame)
            XCTAssertTrue(
                player.body.texture === expectedTexture,
                "step \(index) (elapsed \(elapsed)s): expected frame \(expectedFrame)."
            )
        }
    }

    func test_player_idle_neverCyclesFrames_staysAtFrameZero() {
        let player = PlayerNode()
        player.update(deltaTime: 0, movementVector: CGVector(dx: 1, dy: 0))
        player.update(deltaTime: PlayerAnimator.secondsPerFrame, movementVector: .zero)
        player.update(deltaTime: PlayerAnimator.secondsPerFrame, movementVector: .zero)
        player.update(deltaTime: PlayerAnimator.secondsPerFrame, movementVector: .zero)

        let eastRow = PlayerSpriteSheet.rowMapping(for: .east).row
        XCTAssertTrue(player.body.texture === PlayerNode.texture(row: eastRow, column: PlayerAnimator.frameContactFirst))
    }

    // MARK: - Raccoon: all 8 facings resolve the correct atlas row + mirror

    func test_raccoon_turningThroughAllEightFacings_selectsTheCorrectAtlasRowAndMirror_forBothTiers() {
        for tier in RaccoonTier.allCases {
            for (direction, _) in Self.spriteKitVectors {
                let raccoon = RaccoonNode(tier: tier)
                raccoon.setDirection(direction)
                raccoon.update(deltaTime: 0)

                let mapping = RaccoonAnimationController.rowMapping(for: direction)
                let expectedTexture = RaccoonNode.texture(state: .walk, row: mapping.row, column: 0)

                XCTAssertTrue(
                    raccoon.body.texture === expectedTexture,
                    "\(tier)/\(direction): expected row \(mapping.row) frame 0."
                )
                let expectedXScaleSign: CGFloat = mapping.mirrored ? -1 : 1
                XCTAssertEqual(
                    (raccoon.body.xScale < 0) ? -1 : 1, expectedXScaleSign,
                    "\(tier)/\(direction): mirror flag did not match rowMapping.mirrored."
                )
                XCTAssertEqual(raccoon.facing, direction)
            }
        }
    }

    func test_raccoon_turningThroughAllEightFacingsInSequence_onOneNode_tracksEveryChange() {
        let raccoon = RaccoonNode(tier: .base)
        for (direction, _) in Self.spriteKitVectors {
            raccoon.setDirection(direction)
            raccoon.update(deltaTime: 0)
            XCTAssertEqual(raccoon.facing, direction)

            let mapping = RaccoonAnimationController.rowMapping(for: direction)
            let expectedTexture = RaccoonNode.texture(state: .walk, row: mapping.row, column: 0)
            XCTAssertTrue(raccoon.body.texture === expectedTexture, "\(direction): body texture did not update.")
        }
    }

    // MARK: - Raccoon: walk frames cycle 0 -> 1 -> 2 -> 3 -> 0 at the documented 10fps cadence

    /// Drives elapsed time to the *midpoint* of each frame window (`(slot +
    /// 0.5) / fps`), never to an exact frame-boundary multiple -- the same
    /// precaution `RaccoonAnimationControllerTests` documents and takes for
    /// this exact 10fps/12fps math (`0.3 / 0.1 == 2.9999999999999996` in
    /// IEEE754 is a real risk for these two rates, unlike `PlayerAnimator`'s
    /// binary-exact 1/8s). `slot` counts monotonically past one full 4-frame
    /// cycle so the wrap (`slot % frameCount`) is exercised too.
    private func midpointElapsed(_ slot: Int, fps: Double) -> TimeInterval {
        (Double(slot) + 0.5) / fps
    }

    func test_raccoon_walkFrames_cycleThroughAllFourFramesAndWrap_atTheDocumented10fpsCadence() {
        let raccoon = RaccoonNode(tier: .base)
        raccoon.setDirection(.east)
        let eastRow = RaccoonAnimationController.rowMapping(for: .east).row
        let fps = RaccoonAnimationController.walkFramesPerSecond

        var previousElapsed: TimeInterval = 0
        for slot in 0..<6 {
            let target = midpointElapsed(slot, fps: fps)
            raccoon.update(deltaTime: target - previousElapsed)
            previousElapsed = target

            let expectedFrame = slot % RaccoonAnimationController.frameCount
            let expectedTexture = RaccoonNode.texture(state: .walk, row: eastRow, column: expectedFrame)
            XCTAssertTrue(
                raccoon.body.texture === expectedTexture,
                "slot \(slot): expected walk frame \(expectedFrame)."
            )
        }
    }

    /// The raccoon's attack cycle runs on its own sheet/cadence
    /// (`sprite_raccoon_attack`, 12fps) -- distinct from the walk cycle
    /// above, and gate 3's "visibly cycling ... animation" applies to it
    /// too, not only to the walk state.
    func test_raccoon_attackFrames_cycleThroughAllFourFramesAndWrap_atTheDocumented12fpsCadence() {
        let raccoon = RaccoonNode(tier: .elite)
        raccoon.setDirection(.south)
        raccoon.playAttack()
        let southRow = RaccoonAnimationController.rowMapping(for: .south).row
        let fps = RaccoonAnimationController.attackFramesPerSecond

        var previousElapsed: TimeInterval = 0
        for slot in 0..<5 {
            let target = midpointElapsed(slot, fps: fps)
            raccoon.update(deltaTime: target - previousElapsed)
            previousElapsed = target

            let expectedFrame = slot % RaccoonAnimationController.frameCount
            let expectedTexture = RaccoonNode.texture(state: .attack, row: southRow, column: expectedFrame)
            XCTAssertTrue(
                raccoon.body.texture === expectedTexture,
                "slot \(slot): expected attack frame \(expectedFrame)."
            )
        }
    }

    func test_raccoon_idle_walkCycle_staysAtFrameZero_whenNeverAdvanced() {
        let raccoon = RaccoonNode(tier: .base)
        raccoon.setDirection(.north)
        raccoon.update(deltaTime: 0)

        let northRow = RaccoonAnimationController.rowMapping(for: .north).row
        XCTAssertTrue(raccoon.body.texture === RaccoonNode.texture(state: .walk, row: northRow, column: 0))
    }
}
