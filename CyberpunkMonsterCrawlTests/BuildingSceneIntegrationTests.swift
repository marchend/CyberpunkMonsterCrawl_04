import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-5-t3's building-scene smoke check: loads real generated
/// chunks into a live SpriteKit node tree — through `GroundPlaneStreamer`,
/// the actual production mount, not `TileFieldRenderer` called in
/// isolation — and asserts building nodes are actually present, carry a
/// real (non-nil) texture, and render from transparent-background art
/// rather than an opaque "navy placeholder box".
///
/// This is AC1's "the city reads visually" claim taken as far as it can be
/// checked off-device: no simulator, no screenshot, no pixel-perfect
/// on-screen judgment (that is a human/product-gate concern) — only the
/// measurable, off-device-checkable facts that a rendering bug would
/// violate: nodes exist, textures are non-nil, and the underlying art
/// actually carries transparency rather than filling its bounding box
/// opaquely.
final class BuildingSceneIntegrationTests: XCTestCase {

    /// Picked only for determinism: `ChunkGenerator.generate` is a pure
    /// function of `(chunkCoordinate, seed)`, so any fixed seed reproduces
    /// the exact same buildings on every run.
    private let seed = WorldSeed(rawValue: 909_090)

    private func makeStreamer(worldLayer: SKNode) -> GroundPlaneStreamer {
        GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)
    }

    private func drain(_ streamer: GroundPlaneStreamer, tickBound: Int = 200) {
        var ticks = 0
        while streamer.advanceIncrementalMount() > 0, ticks < tickBound {
            ticks += 1
        }
        XCTAssertLessThan(ticks, tickBound, "Incremental mount did not converge.")
    }

    private func buildingSprites(in worldLayer: SKNode) -> [SKSpriteNode] {
        worldLayer.children
            .compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == TileFieldRenderer.buildingNodeName }
    }

    // MARK: - Building nodes are actually mounted, with real textures

    /// Exercised through the real streaming + rendering pipeline rather than
    /// by calling `TileFieldRenderer` alone: a chunk actually loaded into a
    /// live scene graph produces one building node per resident
    /// `Chunk.buildingPlacements` record, each with a real, non-nil texture.
    func test_loadingAChunk_intoALiveSceneGraph_mountsBuildingNodesWithNonNilTextures() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drain(streamer)

        let residentPlacementCount = streamer.streaming.residentChunks.values
            .reduce(0) { $0 + $1.buildingPlacements.count }
        XCTAssertGreaterThan(
            residentPlacementCount, 0,
            "Precondition: this seed's resident window must actually contain some buildings, or the rest "
                + "of this test proves nothing."
        )

        let sprites = buildingSprites(in: worldLayer)
        XCTAssertEqual(
            sprites.count, residentPlacementCount,
            "One building node must be mounted per resident Chunk.buildingPlacements record — a factory "
                + "nothing calls renders nothing in a real build."
        )

        for sprite in sprites {
            guard let texture = sprite.texture else {
                XCTFail("Mounted building node carries no texture — would render as an empty/placeholder box.")
                continue
            }
            XCTAssertGreaterThan(texture.size().width, 0)
            XCTAssertGreaterThan(texture.size().height, 0)
            XCTAssertEqual(sprite.size, texture.size())
        }
    }

    // MARK: - Building art is not an opaque placeholder

    /// The other half of AC1: mounted building art must not be an opaque
    /// placeholder rectangle (the "navy box" failure mode) — it must carry
    /// an alpha channel and have at least one fully transparent pixel
    /// outside its silhouette. Checked here against exactly the assets the
    /// resident window's *real* generated placements actually used, so this
    /// is a statement about the live pipeline rather than merely "every
    /// `BuildingSprite` case" (which `BuildingCatalogTests` already covers,
    /// independently of any streaming/generation code path).
    func test_mountedBuildingArt_isNotAnOpaquePlaceholder_carriesTransparentBackground() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drain(streamer)

        let usedAssetNames = Set(
            streamer.streaming.residentChunks.values
                .flatMap(\.buildingPlacements)
                .map(\.building.assetName)
        )
        XCTAssertGreaterThan(usedAssetNames.count, 0, "Precondition: some building asset must actually be in play.")

        for assetName in usedAssetNames {
            guard let alphaInfo = ImagePixelSampling.sourceAlphaInfo(ofImageNamed: assetName) else {
                XCTFail("\(assetName) is referenced by a mounted building record but is not in Assets.xcassets.")
                continue
            }
            XCTAssertTrue(
                ImagePixelSampling.alphaCarryingInfos.contains(alphaInfo),
                "\(assetName) decoded with no alpha channel — a flattened/opaque re-export renders as a "
                    + "solid box behind every ground tile it stands on."
            )

            guard let pixels = ImagePixelSampling.pixels(ofImageNamed: assetName) else {
                XCTFail("\(assetName) could not be decoded from Assets.xcassets.")
                continue
            }
            XCTAssertGreaterThan(
                pixels.fullyTransparentPixelCount, 0,
                "\(assetName) has no transparent pixel in its bounding box — it would draw as a solid "
                    + "navy/placeholder rectangle rather than a building silhouette sitting on the ground."
            )
        }

        // The SKTexture actually mounted in the scene resolves nearest-
        // filtered with no mipmaps — the same crispness contract every
        // other production sprite in this codebase goes through.
        for sprite in buildingSprites(in: worldLayer) {
            guard let texture = sprite.texture else { continue }
            XCTAssertEqual(texture.filteringMode, .nearest)
            XCTAssertFalse(texture.usesMipmaps)
        }
    }

    // MARK: - Bounded, no orphans

    /// The mounted building population must not silently include content
    /// this test isn't accounting for — every building sprite in
    /// `worldLayer` must trace back to a resident `buildingPlacements`
    /// record's screen point, so a rendering bug that mounts an extra,
    /// untracked node would be caught here rather than only inflating a
    /// count elsewhere.
    func test_everyMountedBuildingSprite_positionsAtAResidentPlacementsScreenPoint() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drain(streamer)

        let expectedPoints = Set(
            streamer.streaming.residentChunks.values
                .flatMap(\.buildingPlacements)
                .map { record -> CGPoint in
                    let screenPoint = IsometricProjection.tileToScreen(
                        tileX: Double(record.lotTile.tileX),
                        tileY: Double(record.lotTile.tileY)
                    )
                    return CGPoint(x: screenPoint.x.rounded(), y: screenPoint.y.rounded())
                }
        )

        for sprite in buildingSprites(in: worldLayer) {
            XCTAssertTrue(
                expectedPoints.contains(sprite.position),
                "Mounted building sprite at \(sprite.position) does not match any resident placement's screen point."
            )
        }
    }
}
