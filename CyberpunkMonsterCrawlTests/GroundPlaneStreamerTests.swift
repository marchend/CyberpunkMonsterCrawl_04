import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-4-t2: the ground plane must actually be *mounted*, not just
/// buildable.
///
/// `GroundTileRendererTests` exercises the node factory directly, so it stays
/// green whether or not anything in the app parents those nodes into the
/// scene — which is exactly how a renderer nothing calls ships with a green
/// suite. These tests drive the production mount instead: the resident chunk
/// window from `ChunkStreamingManager`, one ground node per resident tile,
/// parented directly under `GameScene.worldLayer`, and torn down again on
/// eviction.
final class GroundPlaneStreamerTests: XCTestCase {

    private let seed = WorldSeed(rawValue: 4_242)

    private var tilesPerChunk: Int { Chunk.size * Chunk.size }

    private func makeStreamer(worldLayer: SKNode) -> GroundPlaneStreamer {
        GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)
    }

    // MARK: - Mounting

    func test_updateCamera_mountsOneNodePerTileOfEveryResidentChunk() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        XCTAssertEqual(streamer.mountedChunks, Set(streamer.streaming.residentChunks.keys))
        XCTAssertEqual(
            streamer.mountedNodeCount,
            ChunkStreamingManager.residentWindowSize * tilesPerChunk,
            "Every tile of every resident chunk must get a ground node — that is the story's "
                + "\"render every generated ground cell\" AC."
        )
        XCTAssertEqual(worldLayer.children.count, streamer.mountedNodeCount)
    }

    /// The depth scheme only works for a **direct** child of `worldLayer`
    /// (`DepthModel.worldLayerRelativeZ`), so the mount must not tuck the
    /// tiles under an intermediate container.
    func test_everyMountedNode_isADirectChildOfWorldLayer_carryingDepthModelsGroundZ() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let sprites = worldLayer.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(sprites.count, worldLayer.children.count, "Every ground child must be a sprite node.")
        XCTAssertFalse(sprites.isEmpty)

        for sprite in sprites {
            XCTAssertTrue(sprite.parent === worldLayer)
            let owningTile = IsometricProjection.tile(containing: sprite.position)
            let tile = TileCoordinate(tileX: owningTile.tileX, tileY: owningTile.tileY)
            let expected = DepthModel.worldLayerRelativeZ(
                forAbsoluteZ: DepthModel.groundZPosition(forTile: tile)
            )
            XCTAssertEqual(
                sprite.zPosition, expected, accuracy: 1e-9,
                "Ground node at \(sprite.position) (tile \(tile)) did not carry DepthModel's ground depth."
            )
        }
    }

    /// The tile a mounted node covers must render the kind the generator
    /// classified for that tile — the mount is a pass over real generated
    /// content, not a decorative grid.
    func test_mountedNodes_renderTheGeneratedTileKind_forEveryTileOfAChunk() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let nodesByPosition = Dictionary(
            worldLayer.children.compactMap { $0 as? SKSpriteNode }.map { ($0.position, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for tileX in 0..<Chunk.size {
            for tileY in 0..<Chunk.size {
                let tile = TileCoordinate(tileX: tileX, tileY: tileY)
                let generated = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
                let expectedNode = GroundTileRenderer.node(for: generated.kind, at: tile)

                let mounted = nodesByPosition[expectedNode.position]
                XCTAssertNotNil(mounted, "No ground node was mounted for tile \(tile).")
                XCTAssertEqual(
                    mounted?.texture?.textureRect(), expectedNode.texture?.textureRect(),
                    "Tile \(tile) (\(generated.kind)) was mounted cropping a different diamond than "
                        + "GroundTileRenderer produces for it."
                )
                XCTAssertEqual(mounted?.size, expectedNode.size)
            }
        }
    }

    // MARK: - Residency

    func test_mountedNodeCount_staysBounded_asTheCameraRoamsFar() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        let bound = ChunkStreamingManager.residentWindowSize * tilesPerChunk

        for step in stride(from: 0, through: 200, by: 7) {
            streamer.updateCamera(worldPosition: TilePoint(x: Double(step), y: Double(-step)))

            XCTAssertEqual(
                streamer.mountedNodeCount, bound,
                "Mounted node count must track the fixed resident window, not grow with distance roamed."
            )
            XCTAssertEqual(worldLayer.children.count, bound, "Evicted chunks must leave no orphan nodes behind.")
        }
    }

    func test_updateCamera_withinTheSameChunk_doesNotRebuildNodes() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        let firstMount = worldLayer.children.compactMap { $0 as? SKSpriteNode }

        streamer.updateCamera(worldPosition: TilePoint(x: 0.2, y: 0.2))
        let secondMount = worldLayer.children.compactMap { $0 as? SKSpriteNode }

        XCTAssertEqual(firstMount.count, secondMount.count)
        XCTAssertTrue(
            zip(firstMount, secondMount).allSatisfy { $0 === $1 },
            "A camera that has not left its chunk must not churn the scene graph."
        )
    }

    func test_unmountAll_removesEveryGroundNodeFromTheScene() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        XCTAssertFalse(worldLayer.children.isEmpty)

        streamer.unmountAll()

        XCTAssertTrue(worldLayer.children.isEmpty)
        XCTAssertEqual(streamer.mountedNodeCount, 0)
        XCTAssertTrue(streamer.mountedChunks.isEmpty)
    }

    // MARK: - Scene wiring (the AC the doc note used to defer)

    func test_enteringGameplay_mountsTheGroundPlaneIntoWorldLayer() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertNil(scene.groundPlane, "No world content before a run starts.")
        XCTAssertTrue(scene.worldLayer.children.isEmpty)

        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let plane = scene.groundPlane
        XCTAssertNotNil(plane, "Entering .gameplay must start the ground plane.")
        XCTAssertEqual(scene.worldLayer.children.count, plane?.mountedNodeCount)
        XCTAssertGreaterThan(scene.worldLayer.children.count, 0)
    }

    /// The mounted ground must not break either structural invariant the
    /// scene audits — a world node escaping the world band is the v1 failure
    /// (`world paints over UI`) this codebase exists to make impossible.
    func test_mountedGroundPlane_keepsTheSceneInvariants() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "Ground nodes escaped the world band: \(scene.layerBandViolationReport())"
        )
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
    }

    /// Re-entering `.gameplay` (RUN AGAIN on the death screen) must not stack
    /// a second ground plane on top of the first.
    func test_reenteringGameplay_replacesTheGroundPlane_ratherThanStackingOne() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let firstCount = scene.worldLayer.children.count

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertEqual(scene.worldLayer.children.count, firstCount)
        XCTAssertEqual(scene.worldLayer.children.count, scene.groundPlane?.mountedNodeCount)
    }
}
