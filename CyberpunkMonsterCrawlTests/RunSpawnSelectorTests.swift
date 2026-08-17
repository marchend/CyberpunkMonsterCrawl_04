import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 3: run-start spawn selection.
///
/// `RunSpawnSelector.selectSpawnTile(seed:)` must always land on a street
/// intersection tile (`CityLatticeGenerator`'s "every intersection tile is
/// street under every seed" invariant), and different seeds must
/// overwhelmingly choose different junctions, or every run would start in
/// the same place regardless of its seed.
final class RunSpawnSelectorTests: XCTestCase {

    private func seeds(_ count: Int) -> [WorldSeed] {
        (0..<count).map { WorldSeed(rawValue: UInt64($0) &* 998_244_353 &+ 7) }
    }

    // MARK: - Always an intersection

    func test_selectedSpawnTile_isAlwaysAnIntersectionTile_acrossManySeeds() {
        for seed in seeds(200) {
            let tile = RunSpawnSelector.selectSpawnTile(seed: seed)
            XCTAssertTrue(
                RunSpawnSelector.isIntersectionTile(tileX: tile.tileX, tileY: tile.tileY),
                "seed \(seed.rawValue): spawn tile (\(tile.tileX), \(tile.tileY)) is not an intersection tile"
            )
        }
    }

    // MARK: - Always street-walkable

    func test_selectedSpawnTile_isAlwaysStreetWalkable_acrossManySeeds() {
        for seed in seeds(200) {
            let tile = RunSpawnSelector.selectSpawnTile(seed: seed)
            let info = CityLatticeGenerator.classify(tileX: tile.tileX, tileY: tile.tileY, seed: seed)

            XCTAssertTrue(info.isWalkable, "seed \(seed.rawValue): spawn tile is not walkable")
            XCTAssertEqual(
                info.kind, .asphalt,
                "seed \(seed.rawValue): spawn tile is not the crossing's driving-lane centre"
            )
        }
    }

    // MARK: - Different seeds, different junctions

    func test_differentSeeds_produceDifferentJunctions() {
        let tiles = seeds(50).map { RunSpawnSelector.selectSpawnTile(seed: $0) }
        let uniqueTiles = Set(tiles)

        XCTAssertGreaterThan(
            uniqueTiles.count, 1,
            "50 distinct seeds must not all land on the same spawn junction"
        )
        // The overwhelming majority should be distinct; a handful of
        // coincidental collisions across 50 draws over a >1000-block-wide
        // grid is not itself a bug, but every seed landing on the same
        // handful of junctions would be.
        XCTAssertGreaterThan(uniqueTiles.count, tiles.count / 2)
    }

    // MARK: - Determinism

    func test_selectSpawnTile_isDeterministic_forTheSameSeed() {
        let seed = WorldSeed(rawValue: 123_456)
        XCTAssertEqual(RunSpawnSelector.selectSpawnTile(seed: seed), RunSpawnSelector.selectSpawnTile(seed: seed))
    }

    // MARK: - isIntersectionTile itself

    func test_isIntersectionTile_rejectsABlockInteriorTile() {
        // Both axes inside the block interior band (0..<blockSize) is a
        // building lot, not a crossing.
        XCTAssertFalse(RunSpawnSelector.isIntersectionTile(tileX: 1, tileY: 1))
    }

    func test_isIntersectionTile_rejectsAStreetCorridorOnOnlyOneAxis() {
        // Street on the X axis only (Y is block interior) is a straight
        // corridor segment, not a crossing.
        XCTAssertFalse(RunSpawnSelector.isIntersectionTile(tileX: 4, tileY: 1))
        XCTAssertFalse(RunSpawnSelector.isIntersectionTile(tileX: 1, tileY: 4))
    }

    func test_isIntersectionTile_acceptsBothAxesInTheStreetBand() {
        XCTAssertTrue(RunSpawnSelector.isIntersectionTile(tileX: 4, tileY: 4))
        // Also holds on the negative side of the origin.
        XCTAssertTrue(RunSpawnSelector.isIntersectionTile(tileX: -2, tileY: -2))
    }
}
