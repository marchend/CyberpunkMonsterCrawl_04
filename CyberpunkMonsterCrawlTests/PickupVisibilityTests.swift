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
final class PickupVisibilityTests: XCTestCase {

    /// A seed and a region wide enough to contain many real, generated
    /// buildings -- so this file's placement sweep exercises actual
    /// `BuildingPlacement` footprints (1x1 and 2x2 alike) rather than a
    /// synthetic single-tile fixture.
    private let seed = WorldSeed(rawValue: 0x9BAD_F00D)

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

    private func makeManager(obstructions: [BuildingPlacementRecord]) -> PickupManager {
        PickupManager(
            worldSeed: seed,
            obstructionsProvider: { obstructions },
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

        let manager = makeManager(obstructions: obstructions)
        // A wide tile-space rect (spans several blocks either side of the
        // origin) so the placement search has real street tiles adjacent to
        // real buildings to reject or accept, not just one hand-picked tile.
        let rect = CGRect(x: -40, y: -40, width: 80, height: 80)
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
                            BuildingObstruction.isObstructed(neighbour, byAnyOf: obstructions),
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

    // MARK: - First-spawn window, pinned against the tuning constant by name

    func test_firstSpawn_landsInsideTheDesignatedWindow_neitherEarlyNorIndefinitelyLate() {
        let manager = makeManager(obstructions: realGeneratedObstructions())
        let rect = CGRect(x: -40, y: -40, width: 80, height: 80)
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
