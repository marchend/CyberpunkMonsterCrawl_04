import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t4` (PR 4): gate-5 pickup-visibility integration checks,
/// pinning gate 5's claims against a **real generated city** rather than a
/// hand-built fixture -- closing a gap `PickupManagerTests`'s otherwise
/// exhaustive coverage leaves open. Every building-adjacency-exclusion test
/// there (`test_obstructedNeighbourTile_...`,
/// `test_obstructionOnTheCandidateTileItself_...`) drives `PickupManager`
/// against a single hand-built `BuildingPlacementRecord` fixture -- never a
/// real generated chunk's building layout. A bug that only manifested
/// against `BuildingPlacement`'s actual footprint shapes (a 2x2 building's
/// four tiles, a block's several buildings whose neighbour rings overlap
/// each other) would pass every existing fixture-driven test while still
/// placing a pickup where a player can see it standing on or against a
/// building in a real run.
///
/// Two things this file deliberately does **not** do (PR #67 review):
///
/// - It does not use `BuildingObstruction.isObstructed(_:byAnyOf:)` -- the
///   production predicate -- as its own oracle. `PickupManager
///   .isLegalPlacement` already consults exactly that function over exactly
///   these records, so an assertion spelled that way proves only that the
///   neighbour loop ran: if `BuildingPlacementRecord.footprintTiles`
///   derived a 2x2 building's four tiles wrongly, production and test would
///   consult the same wrong set and stay green together -- precisely the
///   footprint-shape bug class named above. The occupied-tile set is
///   therefore rebuilt here from `lotTile` + `BuildingFootprintSize
///   .tileSpan` instead, independently of the placement output being
///   audited.
/// - It does not leave `PickupManager`'s `isVisibleOnScreen` predicate at
///   its `nil` default. `visibleRect` alone is the axis-aligned bounding
///   box of the visible diamond -- roughly 70% of it is off camera at a
///   phone viewport (`PickupManager`'s own doc comment, `GameScene
///   .pickupVisibleTileRect()`'s derivation) -- so with `nil` every spawn
///   here could legitimately land where the player cannot see it, and the
///   half of gate 5 that is literally about *visibility* would get no
///   coverage from a file named `PickupVisibilityTests`. Both tests below
///   drive the production predicate,
///   `RaccoonSpawnDirector.isOnScreen(tile:cameraPosition:viewportSize:)`,
///   the same one `GameScene.commonInit()` hands over.
final class PickupVisibilityTests: XCTestCase {

    /// A seed and a region wide enough to contain many real, generated
    /// buildings -- so this file's placement sweep exercises actual
    /// `BuildingPlacement` footprints (1x1 and 2x2 alike) rather than a
    /// synthetic single-tile fixture.
    private let seed = WorldSeed(rawValue: 0x9BAD_F00D)

    /// The camera position and viewport every spawn below is judged
    /// against: a stationary camera at the tile-space origin and a phone
    /// viewport (the 390x844pt device `GameScene.pickupVisibleTileRect()`'s
    /// own worked example uses), so the screen-space predicate and the
    /// sampling rect are derived from one consistent camera rather than two
    /// unrelated hand-picked numbers.
    private let cameraPosition = TilePoint(x: 0, y: 0)
    private let viewportSize = CGSize(width: 390, height: 844)

    /// The tile-space sampling rect production would pass for that camera
    /// and viewport -- the same algebra `GameScene.pickupVisibleTileRect()`
    /// derives (half-extent `width / (4 * tileHalfWidth) + height / (4 *
    /// tileHalfHeight)` on both axes, centred on the camera), rather than a
    /// hand-picked square. Restated from the projection constants so a
    /// retune of the diamond size moves this window with production instead
    /// of leaving a stale literal here.
    private func visibleTileRect() -> CGRect {
        let halfExtent = Double(viewportSize.width) / (4 * IsometricProjection.tileHalfWidth)
            + Double(viewportSize.height) / (4 * IsometricProjection.tileHalfHeight)
        return CGRect(
            x: CGFloat(cameraPosition.x - halfExtent),
            y: CGFloat(cameraPosition.y - halfExtent),
            width: CGFloat(halfExtent * 2),
            height: CGFloat(halfExtent * 2)
        )
    }

    /// Every tile a real generated building actually covers, derived
    /// **without consulting `BuildingPlacementRecord.footprintTiles`**:
    /// each record's own `lotTile` origin walked over its catalog entry's
    /// `footprintSize.tileSpan` (1 tile for a 1x1, four for a 2x2 --
    /// `lotTile ... lotTile + span - 1` on each axis, the same shape
    /// `BuildingPlacementTests
    /// .test_generate_farCornerAndFootprintTiles_agreeWithTheChosenBuildingsSpan`
    /// pins `farCornerTile` to). This is the independent oracle the
    /// adjacency assertion below needs: it comes from the *catalog's*
    /// footprint column, not from the placement output under audit.
    private func independentlyDerivedOccupiedTiles(
        _ records: [BuildingPlacementRecord]
    ) -> Set<TileCoordinate> {
        var tiles: Set<TileCoordinate> = []
        for record in records {
            let span = record.building.footprintSize.tileSpan
            for dx in 0..<span {
                for dy in 0..<span {
                    tiles.insert(
                        TileCoordinate(tileX: record.lotTile.tileX + dx, tileY: record.lotTile.tileY + dy)
                    )
                }
            }
        }
        return tiles
    }

    /// Every building placement `ChunkGenerator` itself would produce for a
    /// wide swept region around the origin, under `seed` -- the same
    /// production entry point `GroundPlaneStreamer` drives, restated here
    /// directly against `BuildingPlacement` rather than through a mounted
    /// scene (`PickupIntegrationTests` already covers the full scene-wiring
    /// path end to end; this file isolates the placement-validation claim
    /// against real building shapes).
    private func realGeneratedObstructions() -> [BuildingPlacementRecord] {
        var records: [BuildingPlacementRecord] = []
        for blockX in -8...8 {
            for blockY in -8...8 {
                let block = BlockCoordinate(x: blockX, y: blockY)
                records.append(contentsOf: BuildingPlacement.generate(forBlock: block, seed: seed))
            }
        }
        return records
    }

    /// Wired exactly as `GameScene.commonInit()` wires production: the
    /// obstruction list is read live, and `isVisibleOnScreen` is
    /// `RaccoonSpawnDirector.isOnScreen(tile:cameraPosition:viewportSize:)`
    /// against this file's own camera/viewport -- never left `nil`, which
    /// would accept the ~70% of `visibleTileRect()` the camera does not
    /// show.
    private func makeManager(obstructions: [BuildingPlacementRecord]) -> PickupManager {
        let camera = cameraPosition
        let viewport = viewportSize
        return PickupManager(
            worldSeed: seed,
            obstructionsProvider: { obstructions },
            isVisibleOnScreen: { tile in
                RaccoonSpawnDirector.isOnScreen(tile: tile, cameraPosition: camera, viewportSize: viewport)
            },
            rng: SplitMix64RandomNumberGenerator(seed: 7)
        )
    }

    // MARK: - Building-adjacency exclusion against real generated buildings

    func test_manySpawnsAgainstARealGeneratedCity_neverLandOnOrAdjacentToARealBuilding() {
        let obstructions = realGeneratedObstructions()
        XCTAssertGreaterThan(
            obstructions.count, 20,
            "sample region too small to contain a meaningful number of real buildings"
        )

        // The independently-derived oracle: catalog footprint spans walked
        // from each record's own lot origin, never the placement output's
        // `footprintTiles`. Asserted to agree with `footprintTiles` first,
        // so a divergence is reported as the footprint-derivation bug it is
        // rather than surfacing later as a confusing adjacency failure.
        let occupied = independentlyDerivedOccupiedTiles(obstructions)
        XCTAssertEqual(
            Set(obstructions.flatMap(\.footprintTiles)), occupied,
            "BuildingPlacementRecord.footprintTiles disagrees with the tiles the catalog's own "
                + "footprintSize span covers from lotTile -- production's obstruction check reads "
                + "footprintTiles, so a building would occupy ground no placement check knows about."
        )

        let manager = makeManager(obstructions: obstructions)
        // The production-shaped sampling window for this file's camera --
        // real street tiles adjacent to real buildings for the placement
        // search to reject or accept, not one hand-picked tile.
        let rect = visibleTileRect()
        let delay = PickupKind.medKit.tuning.firstSpawnDelay

        var spawnedTileCount = 0
        for _ in 0..<40 {
            manager.reset()
            manager.update(deltaTime: delay + 1, visibleRect: rect)

            for pickup in manager.activePickups {
                let tile = TileCoordinate(
                    tileX: Int(pickup.position.x.rounded()),
                    tileY: Int(pickup.position.y.rounded())
                )
                for dx in -1...1 {
                    for dy in -1...1 {
                        let neighbour = TileCoordinate(tileX: tile.tileX + dx, tileY: tile.tileY + dy)
                        XCTAssertFalse(
                            occupied.contains(neighbour),
                            "a pickup spawned at \(tile) with a real building footprint tile at \(neighbour) "
                                + "in its 3x3 neighbourhood -- gate 5 requires a pickup never sit on or "
                                + "adjacent to a building."
                        )
                    }
                }
                spawnedTileCount += 1
            }
        }

        XCTAssertGreaterThan(
            spawnedTileCount, 0,
            "no pickup ever spawned against the real generated city across 40 attempts -- test is vacuous"
        )
    }

    // MARK: - Spawns land where the camera can actually see them

    /// The half of gate 5 that is literally about visibility: a pickup that
    /// spawns inside `visibleRect` but outside the viewport is a pickup the
    /// player never sees, and "first spawn is visible in normal play" would
    /// be a coin flip. `PickupIntegrationTests
    /// .test_everyPickupMounted_spawnsWhereTheCameraCanSeeIt` pins this on
    /// the mounted-scene path; this restates it against a **real generated
    /// city's** obstruction set, which is this file's own scope.
    func test_everySpawnAgainstARealGeneratedCity_landsWhereTheCameraCanActuallySeeIt() {
        let manager = makeManager(obstructions: realGeneratedObstructions())
        let rect = visibleTileRect()
        let delay = PickupKind.medKit.tuning.firstSpawnDelay

        var auditedSpawnCount = 0
        for _ in 0..<40 {
            manager.reset()
            manager.update(deltaTime: delay + 1, visibleRect: rect)

            for pickup in manager.activePickups {
                let tile = TileCoordinate(
                    tileX: Int(pickup.position.x.rounded()),
                    tileY: Int(pickup.position.y.rounded())
                )
                XCTAssertTrue(
                    RaccoonSpawnDirector.isOnScreen(
                        tile: tile,
                        cameraPosition: cameraPosition,
                        viewportSize: viewportSize
                    ),
                    "a pickup spawned at \(tile), inside the sampling rect but outside the viewport -- "
                        + "the rect is only the bounding box of the visible diamond (roughly 70% of it is "
                        + "off camera), and gate 5 asks about what the player can actually see."
                )
                auditedSpawnCount += 1
            }
        }

        XCTAssertGreaterThan(
            auditedSpawnCount, 0,
            "no pickup ever spawned, so the screen-space visibility claim was never exercised"
        )
    }

    // MARK: - First-spawn window, pinned against the tuning constant by name

    func test_firstSpawn_landsInsideTheDesignatedWindow_neitherEarlyNorIndefinitelyLate() {
        let manager = makeManager(obstructions: realGeneratedObstructions())
        let rect = visibleTileRect()
        let delay = PickupKind.medKit.tuning.firstSpawnDelay

        manager.update(deltaTime: delay - 0.1, visibleRect: rect)
        XCTAssertTrue(manager.activePickups.isEmpty, "no pickup may exist before firstSpawnDelay elapses")

        // A generous but bounded window past the delay: placement can retry
        // across several ticks against a real (non-trivial) city before it
        // finds a legal tile, but it must not take indefinitely long against
        // a real generated obstruction set.
        var elapsed: TimeInterval = delay - 0.1
        var didSpawn = false
        while elapsed < delay + 10 {
            manager.update(deltaTime: 0.5, visibleRect: rect)
            elapsed += 0.5
            if !manager.activePickups.isEmpty {
                didSpawn = true
                break
            }
        }

        XCTAssertTrue(
            didSpawn,
            "no pickup spawned within 10s of the first-spawn delay against a real generated city"
        )
    }
}
