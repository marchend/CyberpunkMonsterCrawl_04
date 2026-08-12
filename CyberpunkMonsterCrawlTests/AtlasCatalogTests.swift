import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// The catalog-existence gate for the 10 non-building atlas sheets
/// (CYBERPUN-17-1 AC 2). `AtlasSheet.allCases` is the manifest under test —
/// rename or drop an imageset the game references and this goes red, rather
/// than the v1 failure class of an empty catalog shipping behind a green
/// suite.
final class AtlasCatalogTests: XCTestCase {

    /// Guards against the loops below vacuously passing if the manifest ever
    /// silently shrank.
    func test_atlasSheet_hasTenDistinctCases_oneForEachPixelGritSheetFamily() {
        XCTAssertEqual(AtlasSheet.allCases.count, 10)
        XCTAssertEqual(
            Set(AtlasSheet.allCases.map(\.imageID)).count,
            10,
            "Every AtlasSheet case must reference a distinct imageset."
        )
    }

    /// Every sheet the contract references must resolve to a real,
    /// non-zero-sized image in `Assets.xcassets` — measured by decoding the
    /// image, not by trusting that the id string looks right.
    func test_everyAtlasSheet_resolvesToARealNonZeroSizedImage_inTheCatalog() {
        for sheetCase in AtlasSheet.allCases {
            let imageID = sheetCase.imageID
            guard let image = UIImage(named: imageID, in: .appModule, compatibleWith: nil),
                  let cgImage = image.cgImage
            else {
                XCTFail("\(imageID) is referenced by AtlasSheet but is not in Assets.xcassets.")
                continue
            }

            XCTAssertGreaterThan(cgImage.width, 0, "\(imageID) resolved to a zero-width image.")
            XCTAssertGreaterThan(cgImage.height, 0, "\(imageID) resolved to a zero-height image.")
        }
    }

    /// Resolving `.sheet` walks `SpriteSheet.init`'s measurement
    /// `precondition`. Existence is proven above through a path independent
    /// of that precondition; this test additionally proves that every
    /// declared dimension in `AtlasSheet` actually matches the shipped art
    /// (a mismatch here would abort the whole test process, which is the
    /// hard-failure behavior CYBERPUN-17-1 requires — not a quietly-skipped
    /// assertion).
    func test_everyAtlasSheet_resolvesWithoutTrippingTheMeasurementPrecondition() {
        for sheetCase in AtlasSheet.allCases {
            _ = sheetCase.sheet
        }
    }
}
