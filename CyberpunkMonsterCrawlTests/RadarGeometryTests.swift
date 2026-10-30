import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-23-t1`: pure tile\u2194radar mapping/scale/classification math,
/// provable entirely from unit tests with no scene construction (AC9/AC12).
final class RadarGeometryTests: XCTestCase {

    private let angleAccuracy = 1e-9

    // MARK: - (a) Direction-matching (AC9)

    /// For a sample of tile offsets, `RadarGeometry.radarPoint(
    /// forTileOffset:scale:)` and `IsometricProjection.tileToScreen` must
    /// agree on direction: the same sign on both axes, and the identical
    /// angle (`atan2`) within tolerance. `radarPoint` is built as a uniform
    /// positive rescaling of `tileToScreen`'s own output, so this is exact,
    /// not merely "close" -- but the test is written against
    /// `IsometricProjection` directly (per the implementation plan) rather
    /// than re-deriving the expectation, so a future change to either
    /// formula's sign convention is caught here.
    func test_radarPoint_matchesIsometricProjectionDirection_forASampleOfTileOffsets() {
        let scale: CGFloat = 10
        let offsets: [(x: Int, y: Int)] = [
            (3, -5), (-3, 5), (7, 7), (-7, -7), (1, 0), (0, 1), (-1, 0), (0, -1), (12, 4), (-4, 12),
        ]

        for offset in offsets {
            let radarPoint = RadarGeometry.radarPoint(forTileOffset: offset, scale: scale)
            let worldPoint = IsometricProjection.tileToScreen(tileX: Double(offset.x), tileY: Double(offset.y))

            XCTAssertEqual(
                radarPoint.x.sign, CGFloat(worldPoint.x).sign,
                "x-axis sign mismatch for offset \(offset)"
            )
            XCTAssertEqual(
                radarPoint.y.sign, CGFloat(worldPoint.y).sign,
                "y-axis sign mismatch for offset \(offset)"
            )

            let radarAngle = atan2(Double(radarPoint.y), Double(radarPoint.x))
            let worldAngle = atan2(Double(worldPoint.y), Double(worldPoint.x))
            XCTAssertEqual(
                radarAngle, worldAngle, accuracy: angleAccuracy,
                "angle mismatch for offset \(offset)"
            )
        }
    }

    // MARK: - (b) Scale invariance across orientation (AC12)

    /// A device rotating between portrait and landscape must not change how
    /// much world the radar shows: `radarScale(for:)` is keyed off
    /// `max(width, height)`, which is symmetric under the portrait/
    /// landscape transpose.
    func test_radarScale_isIdentical_forPortraitAndLandscapeOfTheSameDevice() {
        let portraitSize = CGSize(width: 390, height: 844)
        let landscapeSize = CGSize(width: 844, height: 390)

        XCTAssertEqual(
            RadarGeometry.radarScale(for: portraitSize),
            RadarGeometry.radarScale(for: landscapeSize)
        )
    }

    /// Pins the formula itself (`110 / (2.5 * max(w, h))`), not just the
    /// portrait/landscape symmetry above.
    func test_radarScale_matchesDocumentedFormula() {
        let sceneSize = CGSize(width: 400, height: 200)
        let expected: CGFloat = 110 / (2.5 * 400)

        XCTAssertEqual(RadarGeometry.radarScale(for: sceneSize), expected, accuracy: 1e-12)
    }

    // MARK: - (c) Content-square window-inclusion boundary cases

    func test_isWithinContentSquare_trueAtOrigin() {
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(.zero))
    }

    func test_isWithinContentSquare_trueExactlyOnTheBoundary() {
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: 55, y: 55)))
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: -55, y: -55)))
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: 55, y: 0)))
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: 0, y: -55)))
    }

    func test_isWithinContentSquare_falseJustOutsideTheBoundary() {
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 55.0001, y: 0)))
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 0, y: 55.0001)))
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: -55.0001, y: 0)))
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 0, y: -55.0001)))
    }

    func test_isWithinContentSquare_falseFarOutside() {
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 1000, y: 1000)))
    }

    // MARK: - (d) RadarBackdropRenderer.isTileBlocked

    /// Tile `(3, 3)` is a structural lattice-crossing tile: `xMod == 3` and
    /// `yMod == 3` both put it in the street band on *every* seed
    /// (`CityLatticeGenerator`'s own doc comment -- street-ness is never
    /// seed-driven), so `classify` never reports `.buildingFootprint` here
    /// regardless of which seed is used.
    private let guaranteedStreetTile = (tileX: 3, tileY: 3)

    func test_isTileBlocked_falseWhenNeitherLatticeNorObstructionBlocksIt() {
        let seed = WorldSeed(rawValue: 1)

        XCTAssertFalse(
            RadarBackdropRenderer.isTileBlocked(
                tileX: guaranteedStreetTile.tileX,
                tileY: guaranteedStreetTile.tileY,
                seed: seed,
                buildingRecords: []
            )
        )
    }

    func test_isTileBlocked_trueWhenTheLatticeClassifiesItAsABuildingFootprint() throws {
        // Tile (0, 0) is always a block interior (`xMod == 0`, `yMod == 0`,
        // both below `CityLatticeGenerator.blockSize`), so its kind is
        // entirely decided by block (0, 0)'s own seed-driven
        // empty-lot/building decision. Scan seeds until one lands on
        // "built" -- `CityLatticeGenerator`'s own ~1-in-4-empty ratio means
        // this converges almost immediately.
        var blockedSeed: WorldSeed?
        for candidate in UInt64(0)..<50 {
            let seed = WorldSeed(rawValue: candidate)
            let info = CityLatticeGenerator.classify(tileX: 0, tileY: 0, seed: seed)
            if info.kind == .buildingFootprint {
                blockedSeed = seed
                break
            }
        }
        let seed = try XCTUnwrap(blockedSeed, "expected at least one seed in 0..<50 to build block (0, 0)")

        XCTAssertTrue(
            RadarBackdropRenderer.isTileBlocked(tileX: 0, tileY: 0, seed: seed, buildingRecords: [])
        )
    }

    func test_isTileBlocked_trueWhenAPlacementRecordObstructsIt_evenOnAStreetTile() {
        let seed = WorldSeed(rawValue: 1)
        let tile = TileCoordinate(tileX: guaranteedStreetTile.tileX, tileY: guaranteedStreetTile.tileY)
        let record = BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entries[0],
            footprintTiles: [tile],
            farCornerTile: tile
        )

        // Precondition: the lattice itself does not call this a building --
        // the `true` result below must come from the obstruction check, not
        // from `classify`.
        XCTAssertNotEqual(
            CityLatticeGenerator.classify(
                tileX: guaranteedStreetTile.tileX, tileY: guaranteedStreetTile.tileY, seed: seed
            ).kind,
            .buildingFootprint
        )

        XCTAssertTrue(
            RadarBackdropRenderer.isTileBlocked(
                tileX: guaranteedStreetTile.tileX,
                tileY: guaranteedStreetTile.tileY,
                seed: seed,
                buildingRecords: [record]
            )
        )
    }
}
