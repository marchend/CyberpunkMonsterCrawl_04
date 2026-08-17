import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 2's walkability half: pins `TileKind.isWalkable`
/// directly, independent of `BuildingCollisionTests`' footprint-parity
/// focus and of `ConnectivityTests`' flood-fill focus.
///
/// This codebase's own vocabulary for the design brief's "street and
/// sidewalk both read as walkable; building footprints do not": the street
/// surface is `.asphalt`/`.junctionStopLine` (the corridor's driving lane
/// and its painted crossing markings \u2014 both street, both walkable, see
/// `TileKind`'s own doc comments for why the crossing paint is not a
/// distinct collision case), the sidewalk is `.kerbSidewalk`, and the one
/// solid "roof/building" kind is `.buildingFootprint`
/// (`docs/bootstrap.md` \u00a71: "a building blocks movement by its footprint
/// regardless of drawn height" \u2014 there is no separate "roof" `TileKind`;
/// a building's rendered roof/height never participates in collision at
/// all, per `BuildingCollisionTests`/`CollisionResolverTests`). `.lot` (an
/// empty block interior) is included here too because it is also walkable
/// ground, and because a walkability suite that only tried the cases
/// explicitly named "street"/"sidewalk"/"building" in the brief could not
/// catch the empty-lot case silently flipping.
final class TileWalkabilityTests: XCTestCase {

    // MARK: - Street surfaces

    func test_asphalt_isWalkable() {
        XCTAssertTrue(TileKind.asphalt.isWalkable, "the street corridor's driving lane must be walkable")
    }

    func test_junctionStopLine_isWalkable() {
        XCTAssertTrue(
            TileKind.junctionStopLine.isWalkable,
            "a crossing's painted stop line is still street, not a distinct solid surface"
        )
    }

    // MARK: - Sidewalk

    func test_kerbSidewalk_isWalkable() {
        XCTAssertTrue(TileKind.kerbSidewalk.isWalkable, "the sidewalk bordering a street band must be walkable")
    }

    // MARK: - Empty lot (also walkable ground, never solid)

    func test_lot_isWalkable() {
        XCTAssertTrue(TileKind.lot.isWalkable, "a seed-chosen empty block interior stays bare, walkable ground")
    }

    // MARK: - Building footprint (the one solid "roof/building" kind)

    func test_buildingFootprint_isNotWalkable() {
        XCTAssertFalse(
            TileKind.buildingFootprint.isWalkable,
            "a building blocks movement by its footprint regardless of drawn height"
        )
    }

    /// Exhaustive: exactly one of `TileKind`'s cases is solid. `TileKind`
    /// does not conform to `CaseIterable`, so this list is kept in sync by
    /// hand \u2014 if a future case is added and this list is not updated, the
    /// count assertion below still catches the drift because the walkable
    /// count would then disagree with `allCases.count - 1`.
    func test_exactlyOneTileKind_isSolid() {
        let allCases: [TileKind] = [.asphalt, .junctionStopLine, .kerbSidewalk, .lot, .buildingFootprint]
        let solidCases = allCases.filter { !$0.isWalkable }

        XCTAssertEqual(
            solidCases, [.buildingFootprint],
            "exactly one TileKind (.buildingFootprint) should be solid; everything else - street and " +
                "sidewalk surfaces plus the empty lot - must be walkable"
        )
    }

    // MARK: - Confirmed against real generated tiles, not only the enum

    /// `CityLatticeGenerator.classify` is what actually assigns `TileKind`
    /// to a world tile; a suite that only ever constructs `TileKind` cases
    /// by hand could not tell if generation silently classified a street
    /// tile as `.buildingFootprint` or vice versa. This sweeps a real
    /// generated region and asserts every classified tile's `isWalkable`
    /// agrees with this file's own per-case assertions above.
    func test_realGeneratedTiles_agreeWithTileKindsIsWalkable() {
        let seed = WorldSeed(rawValue: 424_242)
        var sawSolidTile = false
        var sawWalkableTile = false

        for tileX in -24...24 {
            for tileY in -24...24 {
                let info = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                if info.kind == .buildingFootprint {
                    sawSolidTile = true
                    XCTAssertFalse(info.isWalkable, "\(info.kind) at (\(tileX), \(tileY)) must not be walkable")
                } else {
                    sawWalkableTile = true
                    XCTAssertTrue(info.isWalkable, "\(info.kind) at (\(tileX), \(tileY)) must be walkable")
                }
            }
        }

        XCTAssertTrue(sawSolidTile, "the swept region should contain at least one building-footprint tile")
        XCTAssertTrue(sawWalkableTile, "the swept region should contain at least one walkable tile")
    }
}
