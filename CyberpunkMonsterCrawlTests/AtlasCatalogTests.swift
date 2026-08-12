import CoreGraphics
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// The catalog-existence gate for the 10 non-building atlas sheets
/// (CYBERPUN-17-1 AC 2). `AtlasSheet.allCases` is the manifest under test —
/// rename or drop an imageset the game references and this goes red, rather
/// than the v1 failure class of an empty catalog shipping behind a green
/// suite. Existence is not the only measured property: the story specifies
/// **PNG-32** sheets, so the alpha channel is asserted here too.
final class AtlasCatalogTests: XCTestCase {

    /// `CGImageAlphaInfo` values that mean "this decoded image actually
    /// carries an alpha channel". Anything else (`.none`, `.noneSkipFirst`,
    /// `.noneSkipLast`) is an opaque sheet — the usual cause is a re-export
    /// that flattened transparency, whose first symptom at render time is a
    /// black box behind every sprite.
    private static let alphaCarryingInfos: [CGImageAlphaInfo] = [
        .first,
        .last,
        .premultipliedFirst,
        .premultipliedLast,
        .alphaOnly,
    ]

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
    /// non-zero-sized image in `Assets.xcassets` **with an alpha channel** —
    /// all measured off the decoded `CGImage`, not inferred from the id
    /// string looking right.
    ///
    /// The alpha half of this is a specified property of the pack (PNG-32
    /// sheets; `docs/bootstrap.md` requires transparent art), so it is
    /// measured rather than assumed: an opaque re-export of any sheet would
    /// otherwise ship green.
    func test_everyAtlasSheet_resolvesToARealNonZeroSizedImage_withAnAlphaChannel() {
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
            XCTAssertTrue(
                Self.alphaCarryingInfos.contains(cgImage.alphaInfo),
                "\(imageID) decoded with alphaInfo raw value \(cgImage.alphaInfo.rawValue) — no alpha "
                    + "channel. The Pixel Grit sheets are PNG-32; a flattened/opaque re-export renders "
                    + "as a black box behind every sprite. Re-export with transparency, never silence "
                    + "this check."
            )
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
