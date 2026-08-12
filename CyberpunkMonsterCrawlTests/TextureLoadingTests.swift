import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `TextureLoading.texture(named:)` is the only sanctioned way to build an
/// `SKTexture` from `Assets.xcassets`. These tests load a representative
/// sample of the 10 imported atlas sheets through it and prove every one
/// comes back nearest-filtered, so a future consumer that bypasses the
/// factory (and gets blurry bilinear-filtered pixel art) is the anomaly, not
/// the norm.
final class TextureLoadingTests: XCTestCase {

    /// One imageset per family that PR 2 imports, so this sample genuinely
    /// spans the atlas-sheet family rather than re-checking one lucky name.
    private static let representativeImageIDs = [
        "sprite_player_walk",
        "sprite_player_weapons",
        "sprite_bullets",
        "sprite_raccoon_walk",
        "sprite_raccoon_attack",
        "tileset_ground",
        "sprite_pickups",
        "sprite_pulse",
        "sprite_hit_puff",
        "sprite_signs",
    ]

    func test_texture_setsNearestFilteringMode_forEveryImportedAtlasSheet() {
        for imageID in Self.representativeImageIDs {
            let texture = TextureLoading.texture(named: imageID)

            XCTAssertEqual(
                texture.filteringMode,
                .nearest,
                "\(imageID) must be nearest-filtered so pixel-art scaling stays crisp."
            )
        }
    }

    /// Guards against the factory silently handing back a placeholder-sized
    /// (0\u00d70) texture for a name that isn't actually in the catalog \u2014 a
    /// nearest-filtered empty texture would still pass the assertion above.
    func test_texture_resolvesARealNonZeroSizedImage_forEveryImportedAtlasSheet() {
        for imageID in Self.representativeImageIDs {
            let texture = TextureLoading.texture(named: imageID)

            XCTAssertGreaterThan(texture.size().width, 0, "\(imageID) resolved to a zero-width texture.")
            XCTAssertGreaterThan(texture.size().height, 0, "\(imageID) resolved to a zero-height texture.")
        }
    }
}
