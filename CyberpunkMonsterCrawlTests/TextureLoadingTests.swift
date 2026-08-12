import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `TextureLoading.texture(named:)` is the only sanctioned way to build an
/// `SKTexture` from `Assets.xcassets`. These tests load every atlas sheet the
/// contract references through it and prove each one comes back
/// nearest-filtered and mipmap-free, so a future consumer that bypasses the
/// factory (and gets blurry bilinear-filtered pixel art) is the anomaly, not
/// the norm.
final class TextureLoadingTests: XCTestCase {

    /// The image ids under test come from `AtlasSheet` rather than a list
    /// re-typed here: the enum is *the* manifest, and a second copy beside it
    /// would drift the first time a sheet is renamed or an eleventh is added.
    private static var atlasSheetImageIDs: [String] {
        AtlasSheet.allCases.map(\.imageID)
    }

    /// Guards the source above against silently emptying out — a loop over an
    /// empty list passes every assertion in this file vacuously — and pins
    /// the count to the story's required sheet count rather than a second
    /// independently maintained literal.
    func test_atlasSheetImageIDs_coverEveryRequiredSheetFamily() {
        XCTAssertEqual(Self.atlasSheetImageIDs.count, 10)
        XCTAssertEqual(
            Set(Self.atlasSheetImageIDs).count,
            Self.atlasSheetImageIDs.count,
            "Sheet image ids must be unique."
        )
    }

    func test_texture_setsNearestFilteringMode_forEveryImportedAtlasSheet() {
        for imageID in Self.atlasSheetImageIDs {
            let texture = TextureLoading.texture(named: imageID)

            XCTAssertEqual(
                texture.filteringMode,
                .nearest,
                "\(imageID) must be nearest-filtered so pixel-art scaling stays crisp."
            )
        }
    }

    /// The factory's doc comment states "no mipmaps" as a hard invariant; a
    /// documented-but-unasserted invariant is one edit away from flipping, so
    /// it is pinned here exactly the way the filtering mode is.
    func test_texture_neverUsesMipmaps_forEveryImportedAtlasSheet() {
        for imageID in Self.atlasSheetImageIDs {
            let texture = TextureLoading.texture(named: imageID)

            XCTAssertFalse(
                texture.usesMipmaps,
                "\(imageID) must not use mipmaps; mipmapping blends pixel-art texels."
            )
        }
    }

    /// Guards against the factory silently handing back a placeholder-sized
    /// (0×0) texture for a name that isn't actually in the catalog — a
    /// nearest-filtered empty texture would still pass the assertions above.
    func test_texture_resolvesARealNonZeroSizedImage_forEveryImportedAtlasSheet() {
        for imageID in Self.atlasSheetImageIDs {
            let texture = TextureLoading.texture(named: imageID)

            XCTAssertGreaterThan(texture.size().width, 0, "\(imageID) resolved to a zero-width texture.")
            XCTAssertGreaterThan(texture.size().height, 0, "\(imageID) resolved to a zero-height texture.")
        }
    }
}
