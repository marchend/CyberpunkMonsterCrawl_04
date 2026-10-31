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

    // MARK: - Visual occlusion (CYBERPUN-17-19): the real check

    /// A synthetic building record occupying a single footprint tile, built
    /// the same way other test suites fabricate one (`CollisionResolverTests
    /// .makeRecord`) -- via `BuildingCatalog.entry(atIndex:)` so the
    /// `heightClass` is a real catalog entry, not a hand-invented value.
    private func makeRecord(atTile tile: TileCoordinate, buildingIndex: Int) -> BuildingPlacementRecord {
        BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entry(atIndex: buildingIndex),
            footprintTiles: [tile],
            farCornerTile: tile
        )
    }

    /// Index 5 is `.tall` (`building_05`, 240px) -- the tallest single-tile
    /// catalog entry, and the one `RunSpawnSelector
    /// .approximatePixelHeight(forHeightClass:)` gives the most screen
    /// reach.
    private static let tallBuildingIndex = 5
    /// Index 0 is `.low` (`building_00`, 112px) -- a much shorter building,
    /// used to prove the occlusion check actually consults height and does
    /// not just fire for any nearby building.
    private static let lowBuildingIndex = 0

    func test_isTileVisuallyOccluded_trueForATallBuilding_inFrontAndScreenAligned() {
        // tile (10, 10): tile sum 20, screen-x diff 0.
        // building (6, 6): tile sum 12 (8 less -- 8 * tileHalfHeight(24) =
        // 192px vertical gap), screen-x diff 0 (perfectly aligned). A
        // `.tall` (240px) building's sprite clears that 192px gap.
        let tile = TileCoordinate(tileX: 10, tileY: 10)
        let building = makeRecord(atTile: TileCoordinate(tileX: 6, tileY: 6), buildingIndex: Self.tallBuildingIndex)

        XCTAssertTrue(RunSpawnSelector.isTileVisuallyOccluded(tile, byAnyOf: [building]))
    }

    func test_isTileVisuallyOccluded_falseForAShorterBuilding_atTheIdenticalAlignedPosition() {
        // Identical geometry to the test above (192px vertical gap, exact
        // screen alignment) but a `.low` (112px) building, which cannot
        // clear a 192px gap -- proving the check actually consults height,
        // not just "is any building nearby and aligned".
        let tile = TileCoordinate(tileX: 10, tileY: 10)
        let building = makeRecord(atTile: TileCoordinate(tileX: 6, tileY: 6), buildingIndex: Self.lowBuildingIndex)

        XCTAssertFalse(RunSpawnSelector.isTileVisuallyOccluded(tile, byAnyOf: [building]))
    }

    func test_isTileVisuallyOccluded_falseWhenHorizontallyMisaligned() {
        // Same tile sums (and so the same 192px vertical gap) as the
        // occluding case above, but shifted so the building's screen-x no
        // longer lines up with the target tile's -- a tall building off to
        // the side must not occlude a tile it never actually covers on
        // screen.
        let tile = TileCoordinate(tileX: 10, tileY: 10)
        let building = makeRecord(atTile: TileCoordinate(tileX: 11, tileY: 1), buildingIndex: Self.tallBuildingIndex)

        XCTAssertFalse(RunSpawnSelector.isTileVisuallyOccluded(tile, byAnyOf: [building]))
    }

    func test_isTileVisuallyOccluded_falseWhenTheBuildingIsNotStrictlyInFront() {
        // Same screen-x alignment as the occluding case, but the
        // "building" sits on (and beyond) the target tile's own tile sum --
        // `DepthModel`'s band ordering means it never draws on top of the
        // target, however tall, so it can never occlude it.
        let tile = TileCoordinate(tileX: 10, tileY: 10)
        let sameBand = makeRecord(atTile: TileCoordinate(tileX: 10, tileY: 10), buildingIndex: Self.tallBuildingIndex)
        let behind = makeRecord(atTile: TileCoordinate(tileX: 11, tileY: 11), buildingIndex: Self.tallBuildingIndex)

        XCTAssertFalse(RunSpawnSelector.isTileVisuallyOccluded(tile, byAnyOf: [sameBand]))
        XCTAssertFalse(RunSpawnSelector.isTileVisuallyOccluded(tile, byAnyOf: [behind]))
    }

    /// The 4 blocks `RunSpawnSelector.neighboringBlocks(blockX:blockY:)`
    /// would hand a `buildingsProvider` for the junction at block
    /// `(blockX, blockY)` -- duplicated here (that helper is private) so
    /// this test can ask a fallback candidate's own obstructions after the
    /// fact, exactly as `selectSpawnTile` itself does internally.
    private func neighboringBlocks(blockX: Int, blockY: Int) -> [BlockCoordinate] {
        [
            BlockCoordinate(x: blockX, y: blockY),
            BlockCoordinate(x: blockX + 1, y: blockY),
            BlockCoordinate(x: blockX, y: blockY + 1),
            BlockCoordinate(x: blockX + 1, y: blockY + 1)
        ]
    }

    /// The block coordinate a junction tile `selectSpawnTile` could have
    /// returned was derived from -- the exact inverse of
    /// `junctionCentreOffset`'s forward arithmetic. Exact (no truncation
    /// surprises) because `tile - junctionCentreOffset` is always a whole
    /// multiple of `CityLatticeGenerator.period` by construction, on
    /// either side of the origin.
    private func owningBlockCoordinate(forJunctionTileAxis axisValue: Int) -> Int {
        (axisValue - RunSpawnSelector.junctionCentreOffset) / CityLatticeGenerator.period
    }

    /// A tall (`.tall`, 240px) building placed at a block's interior corner
    /// nearest the street -- `blockSize - 1` local offset on each axis --
    /// which this file's own geometry tests above already establish
    /// occludes that block's own junction (a 192px vertical gap, exact
    /// screen alignment, well within `.tall`'s 240px reach).
    private func tallOccludingRecord(forBlock block: BlockCoordinate) -> BuildingPlacementRecord {
        let lotTile = TileCoordinate(
            tileX: block.x * CityLatticeGenerator.period + CityLatticeGenerator.blockSize - 1,
            tileY: block.y * CityLatticeGenerator.period + CityLatticeGenerator.blockSize - 1
        )
        return makeRecord(atTile: lotTile, buildingIndex: Self.tallBuildingIndex)
    }

    /// The regression this whole gate exists for: construct a tall building
    /// that visually occludes a seed's default spawn junction, and prove
    /// `selectSpawnTile` moves the spawn to a different, clear junction
    /// instead of returning the occluded one -- exactly what the old
    /// "tile + 8 neighbours" rule could never detect (`junctionCentreOffset`
    /// sits 2 tiles clear of any building footprint, so that rule saw
    /// nothing wrong no matter how tall or close a building was).
    func test_selectSpawnTile_fallsBackDeterministically_whenTheDefaultJunctionIsVisuallyOccludedByATallBuilding() {
        let seed = WorldSeed(rawValue: 42)

        // The seed's naive candidate junction, with no buildings generated
        // at all -- the baseline this test then deliberately occludes.
        let clearTile = RunSpawnSelector.selectSpawnTile(seed: seed) { _, _ in [] }
        let occludedBlock = BlockCoordinate(
            x: owningBlockCoordinate(forJunctionTileAxis: clearTile.tileX),
            y: owningBlockCoordinate(forJunctionTileAxis: clearTile.tileY)
        )

        // Sanity check on the test's own fixture: the synthetic building
        // really does occlude the naive candidate, or the rest of this test
        // would pass for the wrong reason.
        XCTAssertTrue(
            RunSpawnSelector.isTileVisuallyOccluded(clearTile, byAnyOf: [tallOccludingRecord(forBlock: occludedBlock)]),
            "test setup bug: the synthetic tall building must actually occlude the default candidate junction"
        )

        // A `buildingsProvider` that reports the occluding tall building for
        // exactly the default candidate's own block, and nothing anywhere
        // else -- so any fallback candidate the selector reaches is
        // genuinely clear, not just clear of this one hand-placed building.
        func occludingProvider(_ block: BlockCoordinate, _ seed: WorldSeed) -> [BuildingPlacementRecord] {
            guard block.x == occludedBlock.x, block.y == occludedBlock.y else { return [] }
            return [tallOccludingRecord(forBlock: block)]
        }

        let fallbackTile = RunSpawnSelector.selectSpawnTile(seed: seed, buildingsProvider: occludingProvider)

        XCTAssertNotEqual(
            fallbackTile, clearTile,
            "selectSpawnTile must not return a junction it knows is visually occluded"
        )
        XCTAssertTrue(
            RunSpawnSelector.isIntersectionTile(tileX: fallbackTile.tileX, tileY: fallbackTile.tileY),
            "the fallback candidate must still be a genuine lattice crossing"
        )

        let fallbackBlock = BlockCoordinate(
            x: owningBlockCoordinate(forJunctionTileAxis: fallbackTile.tileX),
            y: owningBlockCoordinate(forJunctionTileAxis: fallbackTile.tileY)
        )
        let fallbackObstructions = neighboringBlocks(blockX: fallbackBlock.x, blockY: fallbackBlock.y)
            .flatMap { occludingProvider($0, seed) }
        XCTAssertFalse(
            RunSpawnSelector.isTileVisuallyOccluded(fallbackTile, byAnyOf: fallbackObstructions),
            "the fallback candidate must itself be visually clear, not just different from the occluded one"
        )
    }

    /// `selectSpawnTile`'s fallback loop is a pure function of `(seed,
    /// attempt)` -- repeating the exact same occluded-default scenario
    /// twice must walk the exact same fallback sequence and land on the
    /// exact same junction both times.
    func test_selectSpawnTile_fallbackIsDeterministic_forTheSameOccludedScenario() {
        let seed = WorldSeed(rawValue: 42)
        let clearTile = RunSpawnSelector.selectSpawnTile(seed: seed) { _, _ in [] }
        let occludedBlock = BlockCoordinate(
            x: owningBlockCoordinate(forJunctionTileAxis: clearTile.tileX),
            y: owningBlockCoordinate(forJunctionTileAxis: clearTile.tileY)
        )

        func occludingProvider(_ block: BlockCoordinate, _ seed: WorldSeed) -> [BuildingPlacementRecord] {
            guard block.x == occludedBlock.x, block.y == occludedBlock.y else { return [] }
            return [tallOccludingRecord(forBlock: block)]
        }

        let first = RunSpawnSelector.selectSpawnTile(seed: seed, buildingsProvider: occludingProvider)
        let second = RunSpawnSelector.selectSpawnTile(seed: seed, buildingsProvider: occludingProvider)
        XCTAssertEqual(first, second)
    }
}
