import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-8` PR 2: `RaccoonSeekBehavior` -- per-frame steering toward
/// the player's tile, driving `RaccoonNode`'s facing/animation from the
/// result.
final class RaccoonSeekBehaviorTests: XCTestCase {

    // MARK: - The movement vector points toward the player

    func test_seekVector_pointsTowardThePlayer_inEveryQuadrant() {
        let current = TilePoint(x: 0, y: 0)

        let east = RaccoonSeekBehavior.seekVector(currentPosition: current, playerPosition: TilePoint(x: 5, y: 0))
        XCTAssertGreaterThan(east.dx, 0)
        XCTAssertEqual(east.dy, 0, accuracy: 1e-9)

        let northwestish = RaccoonSeekBehavior.seekVector(currentPosition: current, playerPosition: TilePoint(x: -3, y: 4))
        XCTAssertLessThan(northwestish.dx, 0)
        XCTAssertGreaterThan(northwestish.dy, 0)

        let southeastish = RaccoonSeekBehavior.seekVector(currentPosition: current, playerPosition: TilePoint(x: 6, y: -2))
        XCTAssertGreaterThan(southeastish.dx, 0)
        XCTAssertLessThan(southeastish.dy, 0)
    }

    func test_seekVector_isZero_whenAlreadyOnThePlayersTile() {
        let point = TilePoint(x: 2, y: 2)
        XCTAssertEqual(RaccoonSeekBehavior.seekVector(currentPosition: point, playerPosition: point), .zero)
    }

    // MARK: - Facing tracks the player, and updates continuously as the player moves

    func test_facing_differsBetweenOppositeSidesOfTheRaccoon() {
        let raccoonPosition = TilePoint(x: 0, y: 0)

        let east = RaccoonSeekBehavior.facing(fromCurrentPosition: raccoonPosition, toPlayerPosition: TilePoint(x: 5, y: 0))
        let west = RaccoonSeekBehavior.facing(fromCurrentPosition: raccoonPosition, toPlayerPosition: TilePoint(x: -5, y: 0))
        let north = RaccoonSeekBehavior.facing(fromCurrentPosition: raccoonPosition, toPlayerPosition: TilePoint(x: 0, y: 5))
        let south = RaccoonSeekBehavior.facing(fromCurrentPosition: raccoonPosition, toPlayerPosition: TilePoint(x: 0, y: -5))

        XCTAssertNotNil(east)
        XCTAssertNotNil(west)
        XCTAssertNotNil(north)
        XCTAssertNotNil(south)

        let facings = Set([east, west, north, south].compactMap { $0 })
        XCTAssertGreaterThan(
            facings.count, 1,
            "facing must differ as the player moves to opposite sides of the raccoon, got \(facings)"
        )
    }

    func test_facing_isNil_whenTheRaccoonIsAlreadyOnThePlayersTile() {
        let point = TilePoint(x: 3, y: 3)
        XCTAssertNil(RaccoonSeekBehavior.facing(fromCurrentPosition: point, toPlayerPosition: point))
    }

    /// Drives a live `RaccoonNode` through several frames of a player
    /// visiting four different quadrants around it, and asserts the node's
    /// own `facing` (not just the pure helper) keeps tracking the player
    /// continuously rather than freezing after the first frame.
    func test_update_drivesRaccoonNodeFacing_continuouslyAsThePlayerMoves() {
        let raccoon = RaccoonNode(tier: .base)
        var position = TilePoint(x: 0, y: 0)
        var observedFacings: Set<Direction8> = []

        let playerPositions: [TilePoint] = [
            TilePoint(x: 500, y: 0),
            TilePoint(x: 0, y: 500),
            TilePoint(x: -500, y: 0),
            TilePoint(x: 0, y: -500),
        ]

        for playerPosition in playerPositions {
            // Many small frames so the raccoon never actually reaches the
            // (far-away) player tile mid-sweep, keeping the facing purely a
            // function of this step's direction rather than converging.
            for _ in 0..<3 {
                position = RaccoonSeekBehavior.update(
                    raccoon: raccoon,
                    currentPosition: position,
                    playerPosition: playerPosition,
                    obstructions: [],
                    deltaTime: 1.0 / 60.0
                )
            }
            observedFacings.insert(raccoon.facing)
        }

        XCTAssertGreaterThan(
            observedFacings.count, 1,
            "the raccoon's facing never changed as the player visited 4 different quadrants: \(observedFacings)"
        )
    }

    // MARK: - update(...) walks the raccoon toward the player

    func test_update_withNoObstructions_neverIncreasesDistanceToThePlayer() {
        let raccoon = RaccoonNode(tier: .base)
        let playerPosition = TilePoint(x: 20, y: 0)
        var position = TilePoint(x: 0, y: 0)

        func distanceToPlayer() -> Double {
            hypot(playerPosition.x - position.x, playerPosition.y - position.y)
        }

        var previousDistance = distanceToPlayer()
        for _ in 0..<30 {
            position = RaccoonSeekBehavior.update(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: playerPosition,
                obstructions: [],
                deltaTime: 1.0 / 10.0
            )
            let distance = distanceToPlayer()
            XCTAssertLessThanOrEqual(distance, previousDistance + 1e-9)
            previousDistance = distance
        }

        XCTAssertLessThan(previousDistance, 20.0, "the raccoon must have made real progress toward the player")
    }

    func test_update_neverOvershootsThePlayersTile_onAStalledFrame() {
        let raccoon = RaccoonNode(tier: .base)
        let playerPosition = TilePoint(x: 1, y: 0)
        let position = TilePoint(x: 0, y: 0)

        // A large deltaTime -- a stalled frame -- would overshoot a naive
        // fixed-speed step; `update` must clamp to land exactly on the
        // player's tile instead.
        let resolved = RaccoonSeekBehavior.update(
            raccoon: raccoon,
            currentPosition: position,
            playerPosition: playerPosition,
            obstructions: [],
            deltaTime: 5.0
        )

        XCTAssertEqual(resolved.x, playerPosition.x, accuracy: 1e-9)
        XCTAssertEqual(resolved.y, playerPosition.y, accuracy: 1e-9)
    }

    // MARK: - update(...) plays the walk animation

    func test_update_switchesTheRaccoonToTheWalkAnimation() {
        let raccoon = RaccoonNode(tier: .base)
        raccoon.playAttack()
        XCTAssertEqual(raccoon.animationController.state, .attack)

        _ = RaccoonSeekBehavior.update(
            raccoon: raccoon,
            currentPosition: TilePoint(x: 0, y: 0),
            playerPosition: TilePoint(x: 5, y: 5),
            obstructions: [],
            deltaTime: 1.0 / 60.0
        )

        XCTAssertEqual(raccoon.animationController.state, .walk)
    }

    // MARK: - A zero deltaTime is a no-op

    func test_update_withZeroDeltaTime_returnsCurrentPositionUnchanged() {
        let raccoon = RaccoonNode(tier: .base)
        let position = TilePoint(x: 4, y: 4)

        let resolved = RaccoonSeekBehavior.update(
            raccoon: raccoon,
            currentPosition: position,
            playerPosition: TilePoint(x: 9, y: 9),
            obstructions: [],
            deltaTime: 0
        )

        XCTAssertEqual(resolved, position)
    }

    // MARK: - obstructions: BuildingAvoidance is actually consulted

    /// A raccoon walking straight at a player positioned directly through a
    /// building (a dead-on, axis-aligned approach -- exactly the case
    /// `CollisionResolver` alone cannot resolve without help) must still
    /// never enter the footprint, across many frames.
    func test_update_withObstructions_neverEntersTheFootprint() {
        let footprintOrigin = TileCoordinate(tileX: 10, tileY: 0)
        let record = BuildingPlacementRecord(
            lotTile: footprintOrigin,
            building: BuildingCatalog.entry(atIndex: 3),
            footprintTiles: [footprintOrigin],
            farCornerTile: footprintOrigin
        )
        let bounds = CollisionResolver.footprintBounds(for: record)

        let raccoon = RaccoonNode(tier: .base)
        let playerPosition = TilePoint(x: 20, y: 0) // straight through the footprint
        var position = TilePoint(x: 0, y: 0)

        for tick in 0..<200 {
            position = RaccoonSeekBehavior.update(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: playerPosition,
                obstructions: [bounds],
                deltaTime: 1.0 / 10.0
            )
            XCTAssertFalse(
                bounds.contains(x: position.x, y: position.y),
                "tick \(tick): resolved position \(position) entered the footprint"
            )
        }
    }
}
