import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t4` (PR 4): gate-4 city-read structural assertions,
/// supplementing the manual mock comparison recorded in
/// `docs/evidence/gate-04-city-read-audit.txt`.
///
/// Three claims gate 4 makes that no earlier PR pinned together in one
/// place:
///
/// - **"whole buildings spanning 1-4 storeys"** -- an estimated-storey-count
///   bound derived from `BuildingSprite`'s own measured pixel heights,
///   anchored at the `.lowest`/`.tall` classes' own documented "~1 storey"/
///   "~4 storey" text (`BuildingSprite.HeightClass`'s doc comments), rather
///   than an invented "pixels per storey" constant nobody has measured off
///   the art.
/// - A generated city sample actually contains a **mix** of height classes
///   -- a "reads as a city" claim a single-building-repeated city would
///   violate even though `BuildingPlacementTests`'s existing coverage (fair
///   distribution, no-overlap, fallback-when-2x2-doesn't-fit) stays green
///   either way.
/// - Every placed building footprint tile classifies solid (`.buildingFootprint`,
///   never a street sub-kind) across a wide seed/block sweep -- restating
///   the lattice-connectivity half of gate 4 against real
///   `BuildingPlacement` *output*, not just `CityLatticeGenerator.classify`
///   in isolation (`CityLatticeGeneratorTests`/`ConnectivityTests`'s own
///   scope), so a placement bug that scribbled a footprint onto a street
///   tile would be caught even though `classify` itself was never wrong.
final class CityReadComparisonTests: XCTestCase {

    // MARK: - "1-4 storeys" -- an estimated storey count from measured pixel height

    /// Storey-height estimate anchored at the two classes the story's own
    /// height-class table names by an explicit storey count: `.lowest`
    /// ("~1 storey", `building_10`) and `.tall` ("~4 storey", `building_05`).
    /// A linear fit between those two anchors turns every other class's
    /// declared pixel height into an estimated storey count without
    /// inventing a new measured constant -- the same "derive from
    /// measured/declared facts, never invent a number" discipline this
    /// codebase applies throughout
    /// (`BuildingSpriteBaseAlignmentTests`/`RooftopSignSpriteAlignmentTests`).
    private static func estimatedStoreys(forDeclaredHeight height: CGFloat) -> Double {
        let lowestHeight = BuildingSprite.building10.declaredPixelSize.height // .lowest, ~1 storey
        let tallHeight = BuildingSprite.building05.declaredPixelSize.height // .tall, ~4 storey
        let heightPerStorey = (tallHeight - lowestHeight) / 3
        return 1 + Double((height - lowestHeight) / heightPerStorey)
    }

    func test_everyBuilding_estimatesWithinTheOneToFourStoreySpanTheGateNames() {
        for sprite in BuildingSprite.allCases {
            let storeys = Self.estimatedStoreys(forDeclaredHeight: sprite.declaredPixelSize.height)
            XCTAssertTrue(
                (0.5...4.5).contains(storeys),
                "\(sprite.imageID) (\(sprite.heightClass)) estimates to \(storeys) storeys, outside gate 4's "
                    + "'1-4 storeys' span -- either the art was re-imported at a very different height, or "
                    + "this is a genuine new landmark exception that needs recording as an accepted deviation."
            )
        }
    }

    func test_heightClassesAreOrderedByDeclaredHeight_lowestToTall() {
        let lowest = BuildingSprite.building10.declaredPixelSize.height
        let low = BuildingSprite.building00.declaredPixelSize.height
        let mid = BuildingSprite.building06.declaredPixelSize.height
        let tall = BuildingSprite.building05.declaredPixelSize.height

        XCTAssertLessThan(lowest, low, ".lowest must read visually shorter than .low")
        XCTAssertLessThan(low, mid, ".low must read visually shorter than .mid")
        XCTAssertLessThan(mid, tall, ".mid must read visually shorter than .tall")
    }

    // MARK: - A generated sample actually reads as a city, not one building repeated

    /// A label for `BuildingCatalog.HeightClass` -- that type conforms only
    /// to `Equatable` (not `Hashable`), so this sweep collects a `Set<String>`
    /// of labels rather than requiring a protocol conformance change just for
    /// this test's own bookkeeping.
    private static func label(for heightClass: BuildingCatalog.HeightClass) -> String {
        switch heightClass {
        case .lowest: return "lowest"
        case .low: return "low"
        case .mid: return "mid"
        case .tall: return "tall"
        case .large: return "large"
        }
    }

    func test_aTypicalCitySample_containsAMixOfHeightClasses_notOneBuildingRepeated() {
        let seed = WorldSeed(rawValue: 0xC17_15EED)
        var seenClassLabels: Set<String> = []

        for blockX in -15...15 {
            for blockY in -15...15 {
                let block = BlockCoordinate(x: blockX, y: blockY)
                for record in BuildingPlacement.generate(forBlock: block, seed: seed) {
                    seenClassLabels.insert(Self.label(for: record.building.heightClass))
                }
            }
        }

        XCTAssertGreaterThanOrEqual(
            seenClassLabels.count, 3,
            "a 31x31-block sample saw only \(seenClassLabels.count) distinct height class(es) "
                + "(\(seenClassLabels.sorted())) -- the city should read with visual variety, not as one "
                + "building repeated across every block."
        )
    }

    // MARK: - Every placed footprint tile classifies solid, never street

    func test_everyPlacedBuildingFootprint_classifiesAsBuildingFootprint_neverStreet_acrossAWideSweep() {
        let rawSeeds: [UInt64] = [1, 42, 999, 31_337, 0xC17_15EED]
        let seeds: [WorldSeed] = rawSeeds.map { WorldSeed(rawValue: $0) }
        var checkedFootprintTileCount = 0

        for seed in seeds {
            for blockX in -10...10 {
                for blockY in -10...10 {
                    let block = BlockCoordinate(x: blockX, y: blockY)
                    for record in BuildingPlacement.generate(forBlock: block, seed: seed) {
                        for tile in record.footprintTiles {
                            let info = CityLatticeGenerator.classify(
                                tileX: tile.tileX,
                                tileY: tile.tileY,
                                seed: seed
                            )
                            XCTAssertEqual(
                                info.kind, .buildingFootprint,
                                "\(record.building.assetName)'s footprint tile \(tile) under seed "
                                    + "\(seed.rawValue) classifies as \(info.kind), not .buildingFootprint -- "
                                    + "a building has been placed on street, breaking the lattice's "
                                    + "connectivity guarantee the mock's unbroken street grid depends on."
                            )
                            checkedFootprintTileCount += 1
                        }
                    }
                }
            }
        }

        XCTAssertGreaterThan(checkedFootprintTileCount, 1_000, "sample too small to make this claim reliably")
    }
}
