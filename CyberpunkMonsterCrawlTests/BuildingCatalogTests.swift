import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// The catalog gate for the 12 building sprites (CYBERPUN-17-1 AC 5, closed
/// out by CYBERPUN-17-1-t4's art import).
///
/// Both gates below ran behind a strict `XCTExpectFailure` tagged
/// `SCAFFOLDING(CYBERPUN-17-1-t4)` until the art landed in this PR — the
/// scaffold is now removed, so a missing, duplicate, or mirrored building
/// sprite fails this suite outright rather than being muted.
final class BuildingCatalogTests: XCTestCase {

    /// Anti-vacuity guard for both gates below.
    func test_buildingSprite_hasTwelveDistinctlyNamedCases() {
        XCTAssertEqual(BuildingSprite.allCases.count, 12)
        XCTAssertEqual(
            Set(BuildingSprite.allCases.map(\.imageID)).count,
            12,
            "Every BuildingSprite case must reference a distinct imageset."
        )
        XCTAssertEqual(BuildingSprite.allCases.first?.imageID, "building_00")
        XCTAssertEqual(BuildingSprite.allCases.last?.imageID, "building_11")
    }

    /// Every building id must resolve to a real imageset in the catalog.
    func test_shippedAssetCatalog_containsEveryBuildingSprite() {
        for building in BuildingSprite.allCases {
            XCTAssertNotNil(
                UIImage(named: building.imageID, in: .appModule, compatibleWith: nil),
                "\(building.imageID) is referenced by BuildingSprite but is not in Assets.xcassets."
            )
        }
    }

    /// The 12 buildings must be 12 pieces of art — not the same PNG imported
    /// twice, and not six originals plus six horizontal flips. Both are
    /// measured off decoded pixels: a content fingerprint per building, and a
    /// mirrored fingerprint compared against every other building's content.
    func test_everyBuildingSprite_isDistinctArt_notADuplicateOrAMirrorOfAnother() {
        var fingerprints: [String: UInt64] = [:]
        var mirroredFingerprints: [String: UInt64] = [:]

        for building in BuildingSprite.allCases {
            guard let pixels = ImagePixelSampling.pixels(ofImageNamed: building.imageID) else {
                XCTFail("\(building.imageID) could not be decoded from Assets.xcassets.")
                continue
            }
            fingerprints[building.imageID] = pixels.fingerprint
            mirroredFingerprints[building.imageID] = pixels.mirroredFingerprint
        }

        XCTAssertEqual(
            fingerprints.count,
            12,
            "Only \(fingerprints.count) of the 12 building sprites decoded; the distinctness "
                + "comparison below would pass on a partial set."
        )

        for (lhsID, lhsFingerprint) in fingerprints {
            for (rhsID, rhsFingerprint) in fingerprints where lhsID < rhsID {
                XCTAssertNotEqual(
                    lhsFingerprint,
                    rhsFingerprint,
                    "\(lhsID) and \(rhsID) ship byte-identical art — the pack is meant to hold 12 "
                        + "distinct buildings."
                )
            }
            for (rhsID, rhsMirrored) in mirroredFingerprints where lhsID != rhsID {
                XCTAssertNotEqual(
                    lhsFingerprint,
                    rhsMirrored,
                    "\(lhsID) is a horizontal mirror of \(rhsID) rather than distinct art."
                )
            }
        }
    }
}
