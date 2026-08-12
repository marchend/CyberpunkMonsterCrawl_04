import XCTest
@testable import CyberpunkMonsterCrawl

/// AC4/AC5: the street lattice must be one connected component reaching
/// every intersection tile, for many seeds, over a region large enough
/// (>= 12x12 blocks) that a boundary bug or an accidentally seed-dependent
/// street tile would show up as an unreached intersection.
///
/// This calls `CityLatticeGenerator.classify` tile-by-tile with no notion
/// of chunking, per this PR's scope ("no chunking, no streaming" \u2014
/// chunk-boundary agreement is `CYBERPUN-17-3-t3`'s concern once chunking
/// exists).
final class ConnectivityTests: XCTestCase {

    private struct Coord: Hashable {
        let x: Int
        let y: Int
    }

    /// Blocks are `CityLatticeGenerator.period` tiles wide/tall; 12 blocks
    /// per axis is the AC's stated minimum region size.
    private let blocksPerSide = 12

    private var regionTileRange: Range<Int> {
        0..<(blocksPerSide * CityLatticeGenerator.period)
    }

    func test_streetLattice_isOneConnectedComponent_reachingEveryIntersectionTile_acrossManySeeds() {
        let seeds: [WorldSeed] = (0..<20).map { WorldSeed(rawValue: UInt64($0) &* 998_244_353 &+ 12_345) }

        for seed in seeds {
            var walkable: Set<Coord> = []
            var intersections: [Coord] = []

            for tileX in regionTileRange {
                for tileY in regionTileRange {
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    let coord = Coord(x: tileX, y: tileY)
                    if info.isWalkable {
                        walkable.insert(coord)
                    }
                    if isIntersectionBand(tileX) && isIntersectionBand(tileY) {
                        intersections.append(coord)
                    }
                }
            }

            XCTAssertFalse(
                intersections.isEmpty,
                "Test region produced no intersection tiles - check the region size/period math"
            )

            guard let start = intersections.first else { continue }
            let reachable = floodFill(from: start, walkable: walkable)

            for intersection in intersections {
                XCTAssertTrue(
                    reachable.contains(intersection),
                    "Seed \(seed.rawValue): intersection tile (\(intersection.x), \(intersection.y)) " +
                    "is not reachable from (\(start.x), \(start.y))"
                )
            }
        }
    }

    /// Every intersection tile is walkable street (AC5) \u2014 pinned again
    /// here alongside the connectivity assertion since it's the property
    /// that makes the flood-fill start point valid in the first place.
    func test_everyIntersectionTileInRegion_isWalkable_acrossManySeeds() {
        let seeds: [WorldSeed] = (0..<20).map { WorldSeed(rawValue: UInt64($0) &* 998_244_353 &+ 12_345) }

        for seed in seeds {
            for tileX in regionTileRange where isIntersectionBand(tileX) {
                for tileY in regionTileRange where isIntersectionBand(tileY) {
                    let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                    XCTAssertTrue(
                        info.isWalkable,
                        "Intersection tile (\(tileX), \(tileY)) under seed \(seed.rawValue) is not walkable"
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    /// Source-independent re-derivation of "is this coordinate in the
    /// street band", matching `CityLatticeGeneratorTests`'s helper.
    private func isIntersectionBand(_ coordinate: Int) -> Bool {
        let period = CityLatticeGenerator.period
        let remainder = ((coordinate % period) + period) % period
        return remainder >= CityLatticeGenerator.blockSize
    }

    /// Plain BFS over a `Set` of walkable tile coordinates \u2014 the private
    /// flood-fill helper the PR's plan calls for. 4-connected (N/E/S/W);
    /// the lattice's street bands are always at least 1 tile wide in every
    /// direction, so 4-connectivity is sufficient to prove the corridor
    /// network connects.
    private func floodFill(from start: Coord, walkable: Set<Coord>) -> Set<Coord> {
        guard walkable.contains(start) else { return [] }

        var visited: Set<Coord> = [start]
        var frontier: [Coord] = [start]

        while !frontier.isEmpty {
            var next: [Coord] = []
            for current in frontier {
                let neighbors = [
                    Coord(x: current.x + 1, y: current.y),
                    Coord(x: current.x - 1, y: current.y),
                    Coord(x: current.x, y: current.y + 1),
                    Coord(x: current.x, y: current.y - 1)
                ]
                for neighbor in neighbors {
                    if walkable.contains(neighbor), !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        next.append(neighbor)
                    }
                }
            }
            frontier = next
        }

        return visited
    }
}
