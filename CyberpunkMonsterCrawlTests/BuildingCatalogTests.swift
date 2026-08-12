import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// The catalog gate for the 12 building sprites (CYBERPUN-17-1 scope; art
/// import owned by CYBERPUN-17-1-t4).
///
/// The art is not in the repo yet, so the two gates below are wrapped in a
/// **strict** `XCTExpectFailure` tagged `SCAFFOLDING(CYBERPUN-17-1-t4)`:
///
/// - strict, so the instant `building_00` … `building_11` land in
///   `Assets.xcassets` the expectation stops being met and the suite goes red
///   ("expected failure was not recorded"), forcing the scaffold's removal.
///   A deferral that cannot be forgotten is the point;
/// - scoped to building ids only, so it cannot mute a regression in the 10
///   atlas sheets, which `AtlasCatalogTests` asserts unmuted.
///
/// `test_buildingSprite_hasTwelveDistinctlyNamedCases` is deliberately
/// *outside* the scaffold: the manifest itself must be correct today, so
/// shrinking it cannot make the gate pass vacuously.
final class BuildingCatalogTests: XCTestCase {

    private static func scaffoldOptions() -> XCTExpectFailureOptions {
        let options = XCTExpectFailureOptions()
        options.isStrict = true
        options.isEnabled = true
        return options
    }

    private static let scaffoldReason = """
        SCAFFOLDING(CYBERPUN-17-1-t4): the 12 building PNGs are not imported into Assets.xcassets \
        yet. Delete this XCTExpectFailure as part of the import — it is strict, so it fails the \
        moment the art lands and cannot be left muting the gate.
        """

    /// Anti-vacuity guard for both scaffolded gates below.
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
        XCTExpectFailure(Self.scaffoldReason, options: Self.scaffoldOptions()) {
            for building in BuildingSprite.allCases {
                XCTAssertNotNil(
                    UIImage(named: building.imageID, in: .appModule, compatibleWith: nil),
                    "\(building.imageID) is referenced by BuildingSprite but is not in Assets.xcassets."
                )
            }
        }
    }

    /// The 12 buildings must be 12 pieces of art — not the same PNG imported
    /// twice, and not six originals plus six horizontal flips. Both are
    /// measured off decoded pixels: a content fingerprint per building, and a
    /// mirrored fingerprint compared against every other building's content.
    func test_everyBuildingSprite_isDistinctArt_notADuplicateOrAMirrorOfAnother() {
        XCTExpectFailure(Self.scaffoldReason, options: Self.scaffoldOptions()) {
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
}
