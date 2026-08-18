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

    /// The exact `Direction8` each cardinal *tile* direction must produce,
    /// derived from `IsometricProjection`'s own basis rather than from what
    /// the code happens to return: a tile delta `(dx, dy)` projects to
    /// SpriteKit (y-up) screen space as `((dx - dy) * 48, (dx + dy) * 24)`,
    /// so tile `+x` points up-and-right on screen (`.northeast`), tile `-x`
    /// down-and-left (`.southwest`), tile `+y` up-and-left (`.northwest`)
    /// and tile `-y` down-and-right (`.southeast`).
    ///
    /// **Pinned exactly, not as "the probes are not all the same value".**
    /// If `facing(...)` were built on `Direction8.from(vector:)` instead of
    /// `from(spriteKitVector:)` -- i.e. the y-flip that type owns dropped --
    /// all four probes would still yield four *distinct* cases, so a
    /// distinctness assertion stays green while every raccoon on a device
    /// faces the wrong way vertically. That is the exact silent failure
    /// `Direction8`'s own doc comment warns about ("north/south flip while
    /// east/west stay right, so a facing-vs-movement bug looks like an art
    /// problem"), and product gate 3 ("every actor faces and animates its
    /// movement") is the AC standing behind it. Asserting the values pins
    /// the y-convention and the tile->screen basis at the same time.
    private struct CardinalProbe {
        /// A unit step along one tile axis.
        let tileDelta: TilePoint
        let expected: Direction8
    }

    private static let cardinalFacings: [CardinalProbe] = [
        CardinalProbe(tileDelta: TilePoint(x: 1, y: 0), expected: .northeast),
        CardinalProbe(tileDelta: TilePoint(x: -1, y: 0), expected: .southwest),
        CardinalProbe(tileDelta: TilePoint(x: 0, y: 1), expected: .northwest),
        CardinalProbe(tileDelta: TilePoint(x: 0, y: -1), expected: .southeast),
    ]

    func test_facing_matchesTheIsometricProjection_inEveryCardinalTileDirection() {
        let raccoonPosition = TilePoint(x: 0, y: 0)

        for probe in Self.cardinalFacings {
            let playerPosition = TilePoint(x: probe.tileDelta.x * 5, y: probe.tileDelta.y * 5)
            XCTAssertEqual(
                RaccoonSeekBehavior.facing(fromCurrentPosition: raccoonPosition, toPlayerPosition: playerPosition),
                probe.expected,
                "a player at tile delta (\(probe.tileDelta.x), \(probe.tileDelta.y)) must be faced as \(probe.expected)"
            )
        }
    }

    func test_facing_isNil_whenTheRaccoonIsAlreadyOnThePlayersTile() {
        let point = TilePoint(x: 3, y: 3)
        XCTAssertNil(RaccoonSeekBehavior.facing(fromCurrentPosition: point, toPlayerPosition: point))
    }

    /// Drives a live `RaccoonNode` through several frames of a player
    /// visiting each cardinal tile direction around it, and asserts the
    /// node's own `facing` (not just the pure helper) tracks the player
    /// continuously *and lands on the exact expected case each time* --
    /// same reasoning as `cardinalFacings`: an "it changed at least once"
    /// assertion cannot see a dropped y-flip.
    func test_update_drivesRaccoonNodeFacing_continuouslyAsThePlayerMoves() {
        let raccoon = RaccoonNode(tier: .base)
        var position = TilePoint(x: 0, y: 0)
        var observedFacings: [Direction8] = []

        for probe in Self.cardinalFacings {
            // 500 tiles out, walked for only a handful of small frames, so
            // the raccoon covers a fraction of a tile and never reaches the
            // player mid-sweep: the facing stays the pure cardinal case
            // rather than converging or being skewed by the previous leg's
            // drift.
            let playerPosition = TilePoint(x: probe.tileDelta.x * 500, y: probe.tileDelta.y * 500)
            for _ in 0..<3 {
                position = RaccoonSeekBehavior.update(
                    raccoon: raccoon,
                    currentPosition: position,
                    playerPosition: playerPosition,
                    obstructions: [],
                    deltaTime: 1.0 / 60.0
                )
            }
            observedFacings.append(raccoon.facing)
        }

        XCTAssertEqual(
            observedFacings,
            Self.cardinalFacings.map(\.expected),
            "the raccoon's facing must follow the player through every cardinal tile direction, in the projection's own screen-space convention"
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

    func test_update_stopsAtTheContactStandoff_andNeverOvershoots_onAStalledFrame() {
        let raccoon = RaccoonNode(tier: .base)
        let playerPosition = TilePoint(x: 1, y: 0)
        let position = TilePoint(x: 0, y: 0)

        // A large deltaTime -- a stalled frame -- would overshoot a naive
        // fixed-speed step; `update` must clamp to land exactly on the
        // contact standoff ring instead, and never step past the player.
        let resolved = RaccoonSeekBehavior.update(
            raccoon: raccoon,
            currentPosition: position,
            playerPosition: playerPosition,
            obstructions: [],
            deltaTime: 5.0
        )

        XCTAssertEqual(
            screenDistance(from: resolved, to: playerPosition),
            RaccoonSeekBehavior.contactStandoffPoints(forTier: .base),
            accuracy: 1e-9,
            "a stalled frame must land the raccoon on the standoff ring, not on the player's tile"
        )
        XCTAssertGreaterThan(resolved.x, position.x, "the raccoon must still have closed on the player")
        XCTAssertLessThan(resolved.x, playerPosition.x, "the raccoon must never step past the player")
        XCTAssertEqual(resolved.y, playerPosition.y, accuracy: 1e-9)
    }

    /// The intermediate-state guard review asked for: with no bite and no
    /// death/despawn in this slice, nothing removes a raccoon that has
    /// reached the player, so without a stop radius all
    /// `RaccoonSpawnDirector.maxConcurrentSwarmSize` raccoons would converge
    /// onto the player's exact tile and stack into what renders as a single
    /// sprite, permanently. Every tier must settle *on* the standoff ring
    /// instead -- reached, and never crossed.
    func test_update_settlesOnTheContactStandoff_andNeverReachesThePlayersTile() {
        for tier in [RaccoonTier.base, .elite] {
            let raccoon = RaccoonNode(tier: tier)
            let playerPosition = TilePoint(x: 3, y: -2)
            var position = TilePoint(x: 0, y: 0)
            let standoff = RaccoonSeekBehavior.contactStandoffPoints(forTier: tier)

            for tick in 0..<200 {
                position = RaccoonSeekBehavior.update(
                    raccoon: raccoon,
                    currentPosition: position,
                    playerPosition: playerPosition,
                    obstructions: [],
                    deltaTime: 1.0 / 10.0
                )
                XCTAssertGreaterThanOrEqual(
                    screenDistance(from: position, to: playerPosition),
                    standoff - 1e-9,
                    "\(tier) tick \(tick): a raccoon must never close inside the contact standoff"
                )
            }

            XCTAssertEqual(
                screenDistance(from: position, to: playerPosition),
                standoff,
                accuracy: 1e-6,
                "\(tier): a raccoon must settle on the standoff ring, not stall short of it"
            )
        }
    }

    /// Screen-space (points) distance between two tile-space positions, via
    /// the same projection the seek step is scaled in -- the space the
    /// standoff is defined in.
    private func screenDistance(from origin: TilePoint, to destination: TilePoint) -> Double {
        let delta = IsometricProjection.tileToScreen(
            tileX: destination.x - origin.x,
            tileY: destination.y - origin.y
        )
        return hypot(Double(delta.x), Double(delta.y))
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
