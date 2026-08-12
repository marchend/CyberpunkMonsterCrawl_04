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
        // CYBERPUN-17-4-t4: the first call mounts only the quickstart ring
        // synchronously; flush the deferred remainder to assert the
        // steady-state "every tile has a node" property this test is about.
        streamer.flushPendingMounts()

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
        streamer.flushPendingMounts() // CYBERPUN-17-4-t4: assert the fully-mounted steady state.

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
        // Chunk (0, 0) is within the quickstart ring so it mounts synchronously
        // regardless, but flush anyway so this test does not silently depend
        // on that coincidence.
        streamer.flushPendingMounts()

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
            // CYBERPUN-17-4-t4: flush so every step (including the very
            // first) asserts the steady-state bounded count this test is
            // about, not the quickstart-only partial state the first call
            // now leaves mid-mount.
            streamer.flushPendingMounts()

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
        streamer.flushPendingMounts() // CYBERPUN-17-4-t4: capture the steady state before the no-op re-call.
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
        // The quickstart ring alone is enough to make this nonempty; no
        // flush needed for this assertion.
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
        // CYBERPUN-17-4-t4: the first entry only mounts the quickstart ring
        // synchronously; flush so `firstCount` is the steady state RUN AGAIN
        // is being compared against, not a mid-mount snapshot.
        scene.groundPlane?.flushPendingMounts()
        let firstCount = scene.worldLayer.children.count

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertEqual(scene.worldLayer.children.count, firstCount)
        XCTAssertEqual(scene.worldLayer.children.count, scene.groundPlane?.mountedNodeCount)
    }

    // MARK: - Incremental first mount (CYBERPUN-17-4-t4)

    /// The very first `updateCamera` call on a fresh streamer must mount
    /// only the `ChunkStreamingManager.quickstartRadius` ring synchronously
    /// \u2014 not the entire resident window. That full-window mount (up to
    /// 3,136 `SKSpriteNode`s) inside the same call stack as the PLAY tap is
    /// exactly the main-thread stall the runtime probe caught.
    func test_firstUpdateCamera_synchronouslyMountsOnlyTheQuickstartRing_notTheFullWindow() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let quickstartSide = ChunkStreamingManager.quickstartRadius * 2 + 1
        let expectedQuickstartNodeCount = quickstartSide * quickstartSide * tilesPerChunk
        let fullWindowNodeCount = ChunkStreamingManager.residentWindowSize * tilesPerChunk

        XCTAssertEqual(
            streamer.mountedNodeCount, expectedQuickstartNodeCount,
            "The first updateCamera call must mount exactly the quickstart ring, not more and not less."
        )
        XCTAssertLessThan(
            streamer.mountedNodeCount, fullWindowNodeCount,
            "The first call must defer the rest of the window rather than mounting it all synchronously."
        )
        XCTAssertGreaterThan(
            streamer.mountedNodeCount, 0,
            "The very first rendered frame must already show a street, not an empty world."
        )
        XCTAssertEqual(worldLayer.children.count, streamer.mountedNodeCount)
    }

    /// The remainder of the resident window (everything outside the
    /// quickstart ring) must land within a bounded number of
    /// `advanceIncrementalMount()` ticks \u2014 the stand-in for
    /// `GameScene.update(_:)` calling it once per frame \u2014 and never double-
    /// mount or drop a tile along the way.
    func test_pendingRemainderAfterFirstMount_mountsWithinABoundedNumberOfTicks_withNoDoubleMountOrDrop() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let fullWindowNodeCount = ChunkStreamingManager.residentWindowSize * tilesPerChunk
        XCTAssertLessThan(streamer.mountedNodeCount, fullWindowNodeCount, "Precondition: the first call must defer.")

        var ticks = 0
        let generousTickBound = 50 // far more than any reasonable per-tick budget should need
        while streamer.mountedNodeCount < fullWindowNodeCount, ticks < generousTickBound {
            streamer.advanceIncrementalMount()
            ticks += 1
        }

        XCTAssertLessThan(ticks, generousTickBound, "Incremental mount did not converge within the generous tick bound.")
        XCTAssertEqual(streamer.mountedNodeCount, fullWindowNodeCount)
        XCTAssertEqual(worldLayer.children.count, fullWindowNodeCount)
        XCTAssertEqual(streamer.mountedChunks, Set(streamer.streaming.residentChunks.keys))

        // No double-mount or drop: every mounted sprite maps to a distinct
        // tile, and the set of mounted tiles matches the resident window
        // exactly.
        let sprites = worldLayer.children.compactMap { $0 as? SKSpriteNode }
        let mountedTiles = sprites.map { sprite -> TileCoordinate in
            let owningTile = IsometricProjection.tile(containing: sprite.position)
            return TileCoordinate(tileX: owningTile.tileX, tileY: owningTile.tileY)
        }
        XCTAssertEqual(Set(mountedTiles).count, mountedTiles.count, "A tile was mounted more than once across the incremental boundary.")
    }

    /// `advanceIncrementalMount()` must be a safe no-op once nothing is left
    /// to mount \u2014 `GameScene.update(_:)` calls it unconditionally every
    /// frame for the entire lifetime of a run, long after the initial
    /// remainder has drained.
    func test_advanceIncrementalMount_isANoOp_onceTheQueueIsEmpty() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        streamer.flushPendingMounts()
        let mountedBeforeExtraTicks = worldLayer.children.count

        XCTAssertEqual(streamer.advanceIncrementalMount(), 0, "Nothing left to mount, so this must return 0.")
        XCTAssertEqual(worldLayer.children.count, mountedBeforeExtraTicks)
    }

    /// A RUN AGAIN that reuses the same streamer before its initial
    /// incremental mount has fully drained must still end up with the whole
    /// resident window mounted \u2014 the "steady state" (non-first) path folds
    /// in anything still queued rather than leaving it stranded forever.
    func test_reusingTheStreamer_beforeTheInitialRemainderDrains_stillReachesTheFullWindow() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let fullWindowNodeCount = ChunkStreamingManager.residentWindowSize * tilesPerChunk
        XCTAssertLessThan(streamer.mountedNodeCount, fullWindowNodeCount, "Precondition: the first call must defer.")

        // A second call at the same camera position (nothing evicted, no new
        // residency) is not the "first ever" call anymore, so it must fold in
        // the deferred remainder rather than leaving it queued indefinitely.
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        XCTAssertEqual(streamer.mountedNodeCount, fullWindowNodeCount)
        XCTAssertEqual(worldLayer.children.count, fullWindowNodeCount)
    }
}
