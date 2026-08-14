import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-4-t2 AC7: every one of the six ground tile kinds renders from
/// a *measured* rect — i.e. one that traces back to `AtlasGroundDiamond`'s
/// pixel-alpha measurement (`AtlasSheet.swift`, pinned by
/// `AtlasGroundDiamondTests`) — rather than a `sheetWidth / 6`-style even
/// division, which `AtlasSheet.swift`'s own doc comment proves is wrong
/// (592 / 6 is approximately 98.67px, not a whole pixel count).
final class GroundTileCatalogTests: XCTestCase {

    /// The six diamonds' exact measured rects, copied verbatim from
    /// `AtlasSheet.swift`'s `AtlasGroundDiamond.pixelRect` for an independent
    /// assertion — if `GroundTileCatalog` or `AtlasGroundDiamond` ever drift
    /// from these literals, this test (not just a circular self-comparison)
    /// catches it.
    private static let expectedRectsByDiamond: [AtlasGroundDiamond: CGRect] = [
        .laneEastWest: CGRect(x: 0, y: 0, width: 96, height: 60),
        .laneNorthSouth: CGRect(x: 96, y: 0, width: 96, height: 60),
        .plainLot: CGRect(x: 192, y: 0, width: 96, height: 60),
        .intersection: CGRect(x: 288, y: 0, width: 96, height: 60),
        .kerbTransition: CGRect(x: 384, y: 0, width: 96, height: 60),
        .overhangLot: CGRect(x: 480, y: 0, width: 112, height: 60),
    ]

    /// The exhaustive `GroundTileKind` -> `AtlasGroundDiamond` mapping the
    /// story's asset contract specifies.
    private static let expectedDiamondByKind: [GroundTileKind: AtlasGroundDiamond] = [
        .asphaltEastWest: .laneNorthSouth,
        .asphaltNorthSouth: .laneEastWest,
        .junctionStopLine: .intersection,
        .kerbSidewalk: .kerbTransition,
        .lot: .plainLot,
        .buildingFootprint: .overhangLot,
    ]

    func test_everyGroundTileKind_mapsToItsDocumentedDiamond() {
        for kind in GroundTileKind.allCases {
            XCTAssertEqual(
                GroundTileCatalog.diamond(for: kind),
                Self.expectedDiamondByKind[kind],
                "\(kind) mapped to an unexpected diamond."
            )
        }
    }

    func test_everyGroundTileKind_rendersFromItsMeasuredRect_notAnEvenDivision() {
        for kind in GroundTileKind.allCases {
            let diamond = Self.expectedDiamondByKind[kind]!
            let expectedRect = Self.expectedRectsByDiamond[diamond]!

            XCTAssertEqual(
                GroundTileCatalog.pixelRect(for: kind),
                expectedRect,
                "\(kind) (\(diamond)) did not match its measured pixel rect."
            )
        }
    }

    /// `GroundTileKind` covers the sheet's diamonds exhaustively — exactly
    /// six cases, one per diamond, no gaps and no duplicates.
    func test_groundTileKind_coversAllSixDiamonds_exactlyOnce() {
        XCTAssertEqual(GroundTileKind.allCases.count, 6)

        let mappedDiamonds = GroundTileKind.allCases.map(GroundTileCatalog.diamond(for:))
        XCTAssertEqual(Set(mappedDiamonds).count, 6, "Every diamond must be reachable, and none duplicated.")
        XCTAssertEqual(Set(mappedDiamonds), Set(AtlasGroundDiamond.allCases))
    }

    /// None of the six measured rects collide — catches a copy/paste
    /// mistake that pointed two kinds at the same sub-rect.
    func test_allSixRects_areDistinct() {
        let rects = GroundTileKind.allCases.map(GroundTileCatalog.pixelRect(for:))
        let uniqueRectDescriptions = Set(rects.map { NSCoder.string(for: $0) })
        XCTAssertEqual(uniqueRectDescriptions.count, rects.count, "Two ground tile kinds share the same pixel rect.")
    }
}
