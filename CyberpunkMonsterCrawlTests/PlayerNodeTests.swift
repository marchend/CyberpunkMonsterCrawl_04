import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6-t2: `PlayerNode` composes the atlas-sliced body sprite,
/// `PlayerAnimator`, `Direction8` and the separate `ActorShadowNode` into a
/// live SpriteKit node graph.
final class PlayerNodeTests: XCTestCase {

    // MARK: - SpriteKit-space (y-up) vectors for every Direction8 case
    //
    // `Direction8.from(spriteKitVector:)` negates `dy` before delegating to
    // `from(vector:)`, whose screen-space (y-down) mapping is pinned by
    // `Direction8Tests`. These are that same table, restated in SpriteKit's
    // y-up space, so this file never re-derives the trigonometry itself.

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

    // MARK: - Facing/mirror mapping, across every direction

    func test_update_setsBodyTextureAndXScale_forEveryDirection8Case() {
        for (direction, vector) in Self.spriteKitVectors {
            let player = PlayerNode()
            player.update(deltaTime: 0, movementVector: vector)

            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            let expectedTexture = PlayerNode.texture(row: mapping.row, column: PlayerAnimator.frameContactFirst)

            XCTAssertTrue(
                player.body.texture === expectedTexture,
                "\(direction): body texture did not match row \(mapping.row), frame 0."
            )

            let expectedScale = PlayerSpriteSheet.xScale(for: direction)
            XCTAssertEqual(player.body.xScale, expectedScale, accuracy: 1e-9, "\(direction): xScale mismatch.")
            XCTAssertEqual(player.facing, direction)
        }
    }

    // MARK: - Idle: freezes to frame 0, keeps the last facing

    func test_update_idle_freezesAtFrameZero_andKeepsLastFacing() {
        let player = PlayerNode()

        // Walk east for a while, so the walk cycle is mid-stride.
        player.update(deltaTime: 0, movementVector: CGVector(dx: 1, dy: 0))
        player.update(deltaTime: 0.25, movementVector: CGVector(dx: 1, dy: 0))

        // Then stop.
        player.update(deltaTime: 0.5, movementVector: .zero)

        XCTAssertFalse(player.isMoving)
        XCTAssertEqual(player.facing, .east, "Idle must keep the last facing, not reset it.")

        let mapping = PlayerSpriteSheet.rowMapping(for: .east)
        let expectedTexture = PlayerNode.texture(row: mapping.row, column: PlayerAnimator.frameContactFirst)
        XCTAssertTrue(player.body.texture === expectedTexture, "Idle must freeze to frame 0.")
        XCTAssertEqual(player.body.xScale, PlayerSpriteSheet.xScale(for: .east), accuracy: 1e-9)
    }

    func test_update_zeroVector_neverResolvesADirection_soFacingStaysAtDefault() {
        // A fresh node has never moved, so its default facing (.south) must
        // survive an all-idle update sequence untouched.
        let player = PlayerNode()
        player.update(deltaTime: 0, movementVector: .zero)
        player.update(deltaTime: 0.1, movementVector: .zero)

        XCTAssertEqual(player.facing, .south)
        XCTAssertFalse(player.isMoving)
    }

    // MARK: - Walk-cycle timing while continuously moving

    func test_update_whileContinuouslyMoving_advancesFrames_perPlayerAnimatorTiming() {
        let player = PlayerNode()
        let eastVector = CGVector(dx: 1, dy: 0)
        let eastRow = PlayerSpriteSheet.rowMapping(for: .east).row

        player.update(deltaTime: 0, movementVector: eastVector)
        XCTAssertTrue(player.body.texture === PlayerNode.texture(row: eastRow, column: 0))

        player.update(deltaTime: PlayerAnimator.secondsPerFrame, movementVector: eastVector)
        XCTAssertTrue(player.body.texture === PlayerNode.texture(row: eastRow, column: 1))

        player.update(deltaTime: PlayerAnimator.secondsPerFrame, movementVector: eastVector)
        XCTAssertTrue(player.body.texture === PlayerNode.texture(row: eastRow, column: 2))
    }

    func test_update_restartingMovement_resetsTheWalkCycle_toFrameZero() {
        let player = PlayerNode()
        let eastVector = CGVector(dx: 1, dy: 0)
        let eastRow = PlayerSpriteSheet.rowMapping(for: .east).row

        // Walk far enough into the cycle that frame is no longer 0.
        player.update(deltaTime: 0, movementVector: eastVector)
        player.update(deltaTime: PlayerAnimator.secondsPerFrame, movementVector: eastVector)
        XCTAssertTrue(player.body.texture === PlayerNode.texture(row: eastRow, column: 1))

        // Stop, then start walking again: the new walk segment must begin
        // at frame 0, not resume mid-cycle.
        player.update(deltaTime: 0.5, movementVector: .zero)
        player.update(deltaTime: 0, movementVector: eastVector)
        XCTAssertTrue(player.body.texture === PlayerNode.texture(row: eastRow, column: 0))
    }

    // MARK: - Hitbox geometry

    func test_hitbox_is14By10_anchoredAtThisNodesPosition() {
        let player = PlayerNode()
        player.position = CGPoint(x: 123, y: -45)

        let expected = PlayerSpriteSheet.hitboxRect(anchoredAt: player.position)
        XCTAssertEqual(player.hitbox, expected)
        XCTAssertEqual(player.hitbox.width, PlayerNode.hitboxSize.width, accuracy: 1e-9)
        XCTAssertEqual(player.hitbox.height, PlayerNode.hitboxSize.height, accuracy: 1e-9)
    }

    // MARK: - Body anchor point

    func test_body_anchorPoint_matchesPlayerSpriteSheet() {
        let player = PlayerNode()
        XCTAssertEqual(player.body.anchorPoint, PlayerSpriteSheet.anchorPointNormalized)
    }

    // MARK: - Shadow: a distinct node, never baked into the body texture

    func test_shadow_isADistinctChildNode_fromTheBody() {
        let player = PlayerNode()

        XCTAssertTrue(player.children.contains { $0 === player.shadow })
        XCTAssertTrue(player.children.contains { $0 === player.body })
        XCTAssertNotEqual(
            ObjectIdentifier(player.shadow),
            ObjectIdentifier(player.body),
            "The shadow must be its own node, never merged into the body sprite."
        )
        XCTAssertNotNil(player.shadow.path, "The shadow must draw its own ellipse geometry.")
    }

    func test_shadow_isZOrderedBeneathTheBody_andNotBelowGround() {
        let player = PlayerNode()

        XCTAssertLessThan(
            player.shadow.zPosition,
            player.body.zPosition,
            "The shadow must draw beneath the body."
        )
        XCTAssertGreaterThanOrEqual(
            player.shadow.zPosition,
            0,
            "The shadow's relative zPosition must never sink below this node's own depth (the ground)."
        )
    }

    // MARK: - Pixel crispness (docs/bootstrap.md section 1)

    func test_body_isPixelCrisp() {
        let player = PlayerNode()

        XCTAssertEqual(player.body.texture?.filteringMode, .nearest)
        XCTAssertEqual(player.body.texture?.usesMipmaps, false)
        XCTAssertEqual(abs(player.body.xScale), abs(player.body.xScale).rounded(), accuracy: 1e-6)
    }
}
