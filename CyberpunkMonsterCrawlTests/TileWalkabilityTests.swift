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

    /// Genuinely exhaustive: this sweeps `TileKind.allCases` (the compiler-
    /// synthesized `CaseIterable` list), not a hand-written literal, so a
    /// sixth case added without classifying its walkability fails here
    /// instead of silently going untested -- the same guarantee
    /// `AtlasSheet.allCases` gives the catalog gates. The count assertion
    /// is spelled out too, so the failure message says *how many* cases
    /// drifted rather than only which list disagreed.
    func test_exactlyOneTileKind_isSolid() {
        let solidCases = TileKind.allCases.filter { !$0.isWalkable }
        let walkableCases = TileKind.allCases.filter(\.isWalkable)

        XCTAssertEqual(
            solidCases, [.buildingFootprint],
            "exactly one TileKind (.buildingFootprint) should be solid; everything else - street and " +
                "sidewalk surfaces plus the empty lot - must be walkable"
        )
        XCTAssertEqual(
            walkableCases.count, TileKind.allCases.count - 1,
            "every TileKind except .buildingFootprint must be walkable; a newly added case has to be "
                + "classified (and asserted individually above) rather than inheriting a default"
        )
    }

    /// Guards the per-case assertions above against the same drift: each
    /// case named individually in this file is one of `allCases`, and there
    /// are no *un*-named cases left over.
    func test_everyTileKindCase_isCoveredByAPerCaseAssertionInThisFile() {
        let casesAssertedIndividually: [TileKind] = [
            .asphalt, .junctionStopLine, .kerbSidewalk, .lot, .buildingFootprint,
        ]

        for kind in TileKind.allCases {
            XCTAssertTrue(
                casesAssertedIndividually.contains(kind),
                "\(kind) has no per-case walkability assertion in TileWalkabilityTests - add one"
            )
        }
        XCTAssertEqual(casesAssertedIndividually.count, TileKind.allCases.count)
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
