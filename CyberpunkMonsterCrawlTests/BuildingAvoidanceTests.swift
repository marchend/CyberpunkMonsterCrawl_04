import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-8` PR 2: `BuildingAvoidance`'s AI-specific extension of
/// `CollisionResolver`'s resolve-X-then-Y AABB slide, generalized to 1x1
/// and 2x2 footprints.
final class BuildingAvoidanceTests: XCTestCase {

    private let footprintOrigin = TileCoordinate(tileX: 40, tileY: 40)

    private func makeRecord(buildingIndex: Int, span: Int) -> BuildingPlacementRecord {
        var tiles: [TileCoordinate] = []
        for dx in 0..<span {
            for dy in 0..<span {
                tiles.append(TileCoordinate(tileX: footprintOrigin.tileX + dx, tileY: footprintOrigin.tileY + dy))
            }
        }
        return BuildingPlacementRecord(
            lotTile: footprintOrigin,
            building: BuildingCatalog.entry(atIndex: buildingIndex),
            footprintTiles: tiles,
            farCornerTile: TileCoordinate(
                tileX: footprintOrigin.tileX + span - 1,
                tileY: footprintOrigin.tileY + span - 1
            )
        )
    }

    private let eightDirections: [CGVector] = [
        CGVector(dx: 1, dy: 0),
        CGVector(dx: -1, dy: 0),
        CGVector(dx: 0, dy: 1),
        CGVector(dx: 0, dy: -1),
        CGVector(dx: 1, dy: 1),
        CGVector(dx: 1, dy: -1),
        CGVector(dx: -1, dy: 1),
        CGVector(dx: -1, dy: -1),
    ]

    // MARK: - 8-direction sweep: never enters the footprint (1x1 and 2x2)

    func test_eightDirectionApproach_neverEntersTheFootprint_forA1x1Footprint() {
        assertEightDirectionApproachNeverEntersFootprint(record: makeRecord(buildingIndex: 3, span: 1))
    }

    func test_eightDirectionApproach_neverEntersTheFootprint_forA2x2Footprint() {
        assertEightDirectionApproachNeverEntersFootprint(record: makeRecord(buildingIndex: 8, span: 2))
    }

    private func assertEightDirectionApproachNeverEntersFootprint(
        record: BuildingPlacementRecord, file: StaticString = #filePath, line: UInt = #line
    ) {
        let bounds = CollisionResolver.footprintBounds(for: record)

        for direction in eightDirections {
            let dx = Double(direction.dx)
            let dy = Double(direction.dy)
            var position = TilePoint(x: Double(footprintOrigin.tileX) - dx * 6, y: Double(footprintOrigin.tileY) - dy * 6)
            let step = CGVector(dx: direction.dx * 0.2, dy: direction.dy * 0.2)

            for tick in 0..<200 {
                position = BuildingAvoidance.resolve(currentPosition: position, proposedDelta: step, obstructedBy: [record])
                XCTAssertFalse(
                    bounds.contains(x: position.x, y: position.y),
                    "direction \(direction), tick \(tick): resolved position \(position) entered the footprint",
                    file: file, line: line
                )
            }
        }
    }

    // MARK: - Sustained diagonal push: never enters the footprint, gets close to the vertex

    func test_sustainedDiagonalPush_getsCloseToTheNearVertex_forA1x1Footprint() {
        assertSustainedDiagonalPushBehavior(record: makeRecord(buildingIndex: 3, span: 1))
    }

    func test_sustainedDiagonalPush_getsCloseToTheNearVertex_forA2x2Footprint() {
        assertSustainedDiagonalPushBehavior(record: makeRecord(buildingIndex: 8, span: 2))
    }

    /// Per the prior lesson pinned in `CollisionResolverTests`: a sustained
    /// diagonal push into a footprint's corner does not converge and park
    /// at that vertex forever (once one axis clamps to the boundary, the
    /// other keeps sliding along the tangent wall), so this asserts the
    /// weaker, actually-true properties -- never entering the strict
    /// interior, and reaching a small minimum distance to the vertex --
    /// rather than exact convergence.
    private func assertSustainedDiagonalPushBehavior(record: BuildingPlacementRecord, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CollisionResolver.footprintBounds(for: record)
        let diagonalDirections = eightDirections.filter { $0.dx != 0 && $0.dy != 0 }
        XCTAssertEqual(diagonalDirections.count, 4, "precondition: exactly 4 of the 8 directions are diagonal")

        for direction in diagonalDirections {
            let dx = Double(direction.dx)
            let dy = Double(direction.dy)
            let vertexX = dx > 0 ? bounds.minX : bounds.maxX
            let vertexY = dy > 0 ? bounds.minY : bounds.maxY

            var position = TilePoint(x: vertexX - dx * 5, y: vertexY - dy * 5)
            let step = CGVector(dx: direction.dx * 0.2, dy: direction.dy * 0.2)

            var closestDistanceToVertex = Double.greatestFiniteMagnitude
            for tick in 0..<60 {
                position = BuildingAvoidance.resolve(currentPosition: position, proposedDelta: step, obstructedBy: [record])
                XCTAssertFalse(
                    bounds.contains(x: position.x, y: position.y),
                    "direction \(direction), tick \(tick): resolved position \(position) entered the footprint",
                    file: file, line: line
                )
                closestDistanceToVertex = min(closestDistanceToVertex, hypot(position.x - vertexX, position.y - vertexY))
            }

            XCTAssertLessThan(
                closestDistanceToVertex, 0.25,
                "direction \(direction): the approach never got close to the footprint's near vertex (\(vertexX), \(vertexY))",
                file: file, line: line
            )
        }
    }

    // MARK: - The perpendicular-probe fallback: an axis-aligned dead-on push keeps making progress

    /// `CollisionResolver.resolve` alone returns the position *unchanged*
    /// for a sustained straight push directly into a flat wall the mover
    /// is already flush against -- the "blocked outright" case an
    /// unattended AI cannot self-correct out of (see `BuildingAvoidance`'s
    /// own doc comment). This is the whole reason `BuildingAvoidance`
    /// exists rather than a bare pass-through to `CollisionResolver`.
    func test_axisAlignedDeadOnPush_ontoAFlatWall_stillMakesProgress_whereCollisionResolverAloneWouldNot() {
        let record = makeRecord(buildingIndex: 3, span: 1) // 1x1 at (40, 40), bounds [39.5, 40.5]
        let bounds = CollisionResolver.footprintBounds(for: record)

        // Walk due south (dy < 0) until flush against the footprint's top
        // edge, staying centred on the footprint's x-range (`x = 40`) so
        // the approach is dead-on rather than a corner clip.
        var position = TilePoint(x: Double(footprintOrigin.tileX), y: bounds.maxY + 2)
        let step = CGVector(dx: 0, dy: -0.3)

        for _ in 0..<40 {
            position = CollisionResolver.resolve(currentPosition: position, proposedDelta: step, obstructedBy: [record])
        }
        XCTAssertEqual(position.y, bounds.maxY, accuracy: 1e-9, "precondition: the mover is flush against the wall")

        // Precondition: `CollisionResolver` alone is now stuck.
        let stillStuck = CollisionResolver.resolve(currentPosition: position, proposedDelta: step, obstructedBy: [record])
        XCTAssertEqual(stillStuck, position, "precondition: CollisionResolver alone makes no progress here")

        // `BuildingAvoidance` must make progress instead of repeating that
        // same stall.
        let avoided = BuildingAvoidance.resolve(currentPosition: position, proposedDelta: step, obstructedBy: [record])
        XCTAssertNotEqual(avoided, position, "BuildingAvoidance must not grind against the wall forever")
        XCTAssertFalse(bounds.contains(x: avoided.x, y: avoided.y), "the probe must not have entered the footprint")

        // And repeating this every frame actually walks the raccoon around
        // the corner rather than oscillating in place.
        var walked = position
        for _ in 0..<40 {
            walked = BuildingAvoidance.resolve(currentPosition: walked, proposedDelta: step, obstructedBy: [record])
            XCTAssertFalse(bounds.contains(x: walked.x, y: walked.y))
        }
        XCTAssertGreaterThan(
            abs(walked.x - position.x), 0.5,
            "a sustained dead-on push must walk the raccoon along the wall over many frames"
        )
    }

    // MARK: - No obstruction: identical to CollisionResolver

    func test_noObstruction_matchesCollisionResolverExactly() {
        let start = TilePoint(x: 3, y: -2)
        let delta = CGVector(dx: 0.4, dy: -0.3)

        let resolved = BuildingAvoidance.resolve(currentPosition: start, proposedDelta: delta, obstructions: [])
        let expected = CollisionResolver.resolve(currentPosition: start, proposedDelta: delta, obstructions: [])

        XCTAssertEqual(resolved.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(resolved.y, expected.y, accuracy: 1e-9)
    }

    // MARK: - A zero delta is a no-op

    func test_zeroDelta_returnsCurrentPositionUnchanged() {
        let record = makeRecord(buildingIndex: 3, span: 1)
        let start = TilePoint(x: 10, y: 10)

        let resolved = BuildingAvoidance.resolve(currentPosition: start, proposedDelta: .zero, obstructedBy: [record])

        XCTAssertEqual(resolved, start)
    }
}
