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

    // MARK: - Always inside the depth model's supported range

    /// The defect `CYBERPUN-17-13` PR 3 exposed: `GameScene.startNewRun()`
    /// draws a *random* `worldSeed` per run, so spawn selection is no longer
    /// only ever asked about the fixed default seed. With the old flat
    /// `selectionRadiusBlocks = 512` the far corner of the selection square
    /// summed to `6_152` against a supported `4_450`, and roughly one seed in
    /// seven spawned the run outside `DepthModel`'s band -- where
    /// `DepthBanding`'s DEBUG precondition trips and the run's nodes would
    /// otherwise draw outside `LayerConstants.worldBand`.
    func test_selectedSpawnTile_isAlwaysWithinTheSupportedDepthRange_acrossManySeeds() {
        for seed in seeds(200) {
            let tile = RunSpawnSelector.selectSpawnTile(seed: seed)
            XCTAssertTrue(
                DepthModel.isWithinSupportedDepthRange(forTile: tile),
                "seed \(seed.rawValue): spawn tile (\(tile.tileX), \(tile.tileY)) sums to "
                    + "\(tile.tileX + tile.tileY), outside DepthModel's supported "
                    + "\(DepthModel.maxSupportedTileSumMagnitude)"
            )
        }
    }

    /// A seed sweep samples the selection square; this pins its *corner*.
    /// Both axes at the far edge of `selectionRadiusBlocks`, offset to the
    /// crossing centre, is the largest tile sum `selectSpawnTile` can return
    /// for any seed whatsoever -- so this fails if the radius ever again
    /// outgrows the depth band, even for seeds no sweep happens to draw.
    func test_theWorstCaseSelectableJunction_isWithinTheSupportedDepthRange() {
        let radius = RunSpawnSelector.selectionRadiusBlocks
        let farCoordinate = radius * CityLatticeGenerator.period + RunSpawnSelector.junctionCentreOffset

        for corner in [
            TileCoordinate(tileX: farCoordinate, tileY: farCoordinate),
            TileCoordinate(tileX: -farCoordinate, tileY: -farCoordinate)
        ] {
            XCTAssertTrue(
                DepthModel.isWithinSupportedDepthRange(forTile: corner),
                "the extreme selectable junction (\(corner.tileX), \(corner.tileY)) must stay "
                    + "inside DepthModel's supported \(DepthModel.maxSupportedTileSumMagnitude)"
            )
        }
    }

    /// The corner alone would be satisfied by a spawn pressed right up
    /// against the edge of the band, which would then break as soon as the
    /// player took a step. The radius must also leave `roamMarginTiles` on
    /// each axis for the run to walk into.
    func test_theWorstCaseSelectableJunction_leavesRoamMarginInsideTheBand() {
        let radius = RunSpawnSelector.selectionRadiusBlocks
        let farCoordinate = radius * CityLatticeGenerator.period + RunSpawnSelector.junctionCentreOffset
        let roamed = farCoordinate + RunSpawnSelector.roamMarginTiles

        XCTAssertTrue(
            DepthModel.isWithinSupportedDepthRange(forTile: TileCoordinate(tileX: roamed, tileY: roamed)),
            "a run spawning at the extreme junction must be able to roam "
                + "\(RunSpawnSelector.roamMarginTiles) tiles on each axis and stay in band"
        )
    }

    /// The bound must not be bought by shrinking spawn variety to nothing:
    /// the surviving selection square still has to hold far more junctions
    /// than any seed sweep can visibly exhaust.
    func test_selectionRadius_stillOffersAmpleSpawnVariety() {
        let junctionsPerAxis = RunSpawnSelector.selectionRadiusBlocks * 2 + 1

        XCTAssertGreaterThan(
            junctionsPerAxis * junctionsPerAxis, 100_000,
            "spawn selection must keep a large candidate set, not just a legal one"
        )
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
        // coincidental collisions across 50 draws over a selection square
        // hundreds of blocks wide is not itself a bug, but every seed
        // landing on the same handful of junctions would be.
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
