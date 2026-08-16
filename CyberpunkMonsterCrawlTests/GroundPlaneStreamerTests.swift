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

    /// The mounted **ground** nodes among `worldLayer`'s children.
    ///
    /// Since CYBERPUN-17-5-t2 the same layer also carries one building node
    /// per `Chunk.buildingPlacements` record, so every "one node per resident
    /// tile" assertion has to name which population it means rather than
    /// taking every child. Filtered by `GroundPlaneStreamer.nodeName`, the
    /// name the mount stamps for exactly this purpose.
    private func groundSprites(in worldLayer: SKNode) -> [SKSpriteNode] {
        worldLayer.children
            .compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == GroundPlaneStreamer.nodeName }
    }

    /// The mounted building nodes among `worldLayer`'s children.
    private func buildingSprites(in worldLayer: SKNode) -> [SKSpriteNode] {
        worldLayer.children
            .compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == TileFieldRenderer.buildingNodeName }
    }

    /// Every building placement across the currently resident chunks \u2014 the
    /// generator-side ground truth the mount is checked against, derived from
    /// `ChunkStreamingManager` rather than from anything the mount computes.
    private func residentPlacements(of streamer: GroundPlaneStreamer) -> [BuildingPlacementRecord] {
        streamer.streaming.residentChunks.values.flatMap(\.buildingPlacements)
    }

    /// Brings `streamer` to the fully-mounted steady state the way the
    /// shipped code does: repeated `advanceIncrementalMount()` ticks, which
    /// is exactly what `GameScene.update(_:)` drives once per frame.
    ///
    /// CYBERPUN-17-4-t4: deliberately *not* a test-only "mount everything
    /// now" entry point. `updateCamera` mounts only the quickstart ring and
    /// defers the rest, so every steady-state assertion below has to get to
    /// the full window somehow — doing it through the production drain means
    /// the residency and bounded-count invariants stay pinned on the path the
    /// app actually takes.
    private func drainIncrementalMount(
        _ streamer: GroundPlaneStreamer?,
        tickBound: Int = 200,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let streamer else { return XCTFail("No streamer to drain.", file: file, line: line) }
        var ticks = 0
        while streamer.advanceIncrementalMount() > 0, ticks < tickBound {
            ticks += 1
        }
        XCTAssertLessThan(ticks, tickBound, "Incremental mount did not converge.", file: file, line: line)
        XCTAssertEqual(streamer.pendingMountCount, 0, "Drain finished with chunks still queued.", file: file, line: line)
    }

    /// Everything the **streamer** mounted in `scene.worldLayer`: since
    /// `CYBERPUN-17-5-t2` that is the ground nodes *plus* one building node
    /// per resident `Chunk.buildingPlacements` record, i.e. every direct
    /// child except the scene's own player mount. Use `groundSprites(in:)` /
    /// `buildingSprites(in:)` when an assertion means one population
    /// specifically.
    ///
    /// The streamer-only tests above own their own bare `SKNode` layer, so
    /// there `children.count` *is* the mount. A real `GameScene` also mounts
    /// the player directly under `worldLayer` (`CYBERPUN-17-6-t2` — directly,
    /// because `PlayerNode.updateDepth(atTilePosition:)` converts through
    /// `DepthModel.worldLayerRelativeZ`, which is only correct for a direct
    /// child), so a raw `children.count` in the scene-level tests would be
    /// measuring "ground plus whatever else the scene mounts" rather than the
    /// ground plane these assertions exist to pin. The player's own mount
    /// contract — including "exactly one `PlayerNode`, never a second one on
    /// RUN AGAIN" — belongs to `PlayerMountTests`.
    private func groundChildren(of scene: GameScene) -> [SKNode] {
        scene.worldLayer.children.filter { !($0 is PlayerNode) }
    }

    // MARK: - Mounting

    func test_updateCamera_mountsOneNodePerTileOfEveryResidentChunk() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        // CYBERPUN-17-4-t4: `updateCamera` mounts only the quickstart ring
        // synchronously; drain the deferred remainder through the production
        // per-frame path to assert the steady-state "every tile has a node"
        // property this test is about.
        drainIncrementalMount(streamer)

        XCTAssertEqual(streamer.mountedChunks, Set(streamer.streaming.residentChunks.keys))
        XCTAssertEqual(
            streamer.mountedNodeCount,
            ChunkStreamingManager.residentWindowSize * tilesPerChunk,
            "Every tile of every resident chunk must get a ground node — that is the story's "
                + "\"render every generated ground cell\" AC."
        )
        XCTAssertEqual(groundSprites(in: worldLayer).count, streamer.mountedNodeCount)
        XCTAssertEqual(
            worldLayer.children.count,
            streamer.mountedNodeCount + streamer.mountedBuildingNodeCount,
            "worldLayer must hold exactly the ground nodes plus the building nodes this mount reports — "
                + "any extra child is an orphan the eviction bookkeeping lost track of."
        )
    }

    /// The depth scheme only works for a **direct** child of `worldLayer`
    /// (`DepthModel.worldLayerRelativeZ`), so the mount must not tuck the
    /// tiles under an intermediate container.
    func test_everyMountedNode_isADirectChildOfWorldLayer_carryingDepthModelsGroundZ() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drainIncrementalMount(streamer) // CYBERPUN-17-4-t4: assert the fully-mounted steady state.

        XCTAssertEqual(
            worldLayer.children.compactMap { $0 as? SKSpriteNode }.count,
            worldLayer.children.count,
            "Every world child must be a sprite node."
        )
        let sprites = groundSprites(in: worldLayer)
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
        // regardless, but drain anyway so this test does not silently depend
        // on that coincidence.
        drainIncrementalMount(streamer)

        let nodesByPosition = Dictionary(
            groundSprites(in: worldLayer).map { ($0.position, $0) },
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
            // CYBERPUN-17-4-t4: drain so every step asserts the steady-state
            // bounded count this test is about, not the quickstart-only
            // partial state each call now leaves mid-mount.
            drainIncrementalMount(streamer)

            XCTAssertEqual(
                streamer.mountedNodeCount, bound,
                "Mounted node count must track the fixed resident window, not grow with distance roamed."
            )
            XCTAssertEqual(
                groundSprites(in: worldLayer).count, bound,
                "Evicted chunks must leave no orphan nodes behind."
            )
            XCTAssertEqual(
                worldLayer.children.count,
                streamer.mountedNodeCount + streamer.mountedBuildingNodeCount,
                "Building nodes must stream out with their chunk too, not accumulate as the camera roams."
            )
        }
    }

    func test_updateCamera_withinTheSameChunk_doesNotRebuildNodes() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drainIncrementalMount(streamer) // CYBERPUN-17-4-t4: capture the steady state before the no-op re-call.
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

        guard let plane = scene.groundPlane else {
            return XCTFail("Entering .gameplay must start the ground plane.")
        }
        XCTAssertEqual(
            groundSprites(in: scene.worldLayer).count, plane.mountedNodeCount,
            "Every ground node the streamer reports must be in worldLayer, and worldLayer must hold no "
                + "stale ground beyond them."
        )
        XCTAssertEqual(buildingSprites(in: scene.worldLayer).count, plane.mountedBuildingNodeCount)
        XCTAssertEqual(
            groundChildren(of: scene).count,
            plane.mountedNodeCount + plane.mountedBuildingNodeCount,
            "worldLayer must hold exactly the ground nodes plus the building nodes this mount reports "
                + "(beyond the player's own mount) — any extra child is an orphan the mount lost track of."
        )
        XCTAssertGreaterThan(groundSprites(in: scene.worldLayer).count, 0)
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
        // CYBERPUN-17-4-t4: entering `.gameplay` only mounts the quickstart
        // ring synchronously; drain so `firstCount` is the steady state RUN
        // AGAIN is being compared against, not a mid-mount snapshot.
        drainIncrementalMount(scene.groundPlane)
        let firstCount = groundChildren(of: scene).count

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        // The restart re-mounts through the same quickstart split, so it too
        // reaches the full window via the per-frame drain rather than inside
        // the transition itself.
        drainIncrementalMount(scene.groundPlane)

        guard let plane = scene.groundPlane else {
            return XCTFail("Re-entering .gameplay must leave a ground plane mounted.")
        }
        XCTAssertEqual(
            groundChildren(of: scene).count, firstCount,
            "RUN AGAIN stacked a second ground plane on top of the first."
        )
        XCTAssertEqual(groundSprites(in: scene.worldLayer).count, plane.mountedNodeCount)
        XCTAssertEqual(buildingSprites(in: scene.worldLayer).count, plane.mountedBuildingNodeCount)
        XCTAssertEqual(
            groundChildren(of: scene).count,
            plane.mountedNodeCount + plane.mountedBuildingNodeCount,
            "A restart stacked a second ground plane's nodes on top of the first — worldLayer must hold "
                + "exactly one mount's ground plus building nodes."
        )
    }

    // MARK: - Incremental mount (CYBERPUN-17-4-t4)

    /// `updateCamera` must mount only the
    /// `ChunkStreamingManager.quickstartRadius` ring synchronously — not the
    /// entire resident window. That full-window mount (up to 3,136
    /// `SKSpriteNode`s) inside the same call stack as the PLAY tap is exactly
    /// the main-thread stall the runtime probe caught.
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
        XCTAssertEqual(groundSprites(in: worldLayer).count, streamer.mountedNodeCount)
        XCTAssertEqual(buildingSprites(in: worldLayer).count, streamer.mountedBuildingNodeCount)
        XCTAssertEqual(
            worldLayer.children.count,
            streamer.mountedNodeCount + streamer.mountedBuildingNodeCount,
            "The synchronous quickstart mount put a child into worldLayer that neither the ground nor "
                + "the building bookkeeping knows about."
        )
    }

    /// The remainder of the resident window (everything outside the
    /// quickstart ring) must land within a bounded number of
    /// `advanceIncrementalMount()` ticks — the stand-in for
    /// `GameScene.update(_:)` calling it once per frame — and never double-
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
        XCTAssertEqual(groundSprites(in: worldLayer).count, fullWindowNodeCount)
        XCTAssertEqual(
            worldLayer.children.count,
            streamer.mountedNodeCount + streamer.mountedBuildingNodeCount,
            "The drained window must hold exactly the ground nodes plus the building nodes the mount "
                + "reports — any extra child is an orphan."
        )
        XCTAssertEqual(streamer.mountedChunks, Set(streamer.streaming.residentChunks.keys))

        // No double-mount or drop: every mounted ground sprite maps to a
        // distinct tile, and the set of mounted tiles matches the resident
        // window exactly. Buildings are excluded deliberately — several may
        // legitimately share a tile's screen point with the ground under
        // them, so counting them here would report a "duplicate" that is
        // nothing of the sort.
        let sprites = groundSprites(in: worldLayer)
        let mountedTiles = sprites.map { sprite -> TileCoordinate in
            let owningTile = IsometricProjection.tile(containing: sprite.position)
            return TileCoordinate(tileX: owningTile.tileX, tileY: owningTile.tileY)
        }
        XCTAssertEqual(Set(mountedTiles).count, mountedTiles.count, "A tile was mounted more than once across the incremental boundary.")
    }

    /// `advanceIncrementalMount()` must be a safe no-op once nothing is left
    /// to mount — `GameScene.update(_:)` calls it unconditionally every
    /// frame for the entire lifetime of a run, long after the initial
    /// remainder has drained.
    func test_advanceIncrementalMount_isANoOp_onceTheQueueIsEmpty() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drainIncrementalMount(streamer)
        let mountedBeforeExtraTicks = worldLayer.children.count

        XCTAssertEqual(streamer.advanceIncrementalMount(), 0, "Nothing left to mount, so this must return 0.")
        XCTAssertEqual(worldLayer.children.count, mountedBeforeExtraTicks)
    }

    /// A later `updateCamera` call must **not** fold the deferred remainder
    /// in synchronously.
    ///
    /// This is the property `CYBERPUN-17-7` depends on. Nothing in Release
    /// calls `updateCamera` a second time today, but camera-follow makes it
    /// run *every frame*: if a non-first call drained the queue, frame 1
    /// would mount the quickstart ring and frame 2 would mount the entire
    /// remainder (~2,560 `addChild` calls) in one frame, reinstating the
    /// stall one frame later and making the incremental drain dead code.
    func test_aLaterUpdateCamera_doesNotDrainTheDeferredRemainderInOneCall() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        let fullWindowNodeCount = ChunkStreamingManager.residentWindowSize * tilesPerChunk
        let mountedAfterFirstCall = streamer.mountedNodeCount
        let pendingAfterFirstCall = streamer.pendingMountCount
        XCTAssertLessThan(mountedAfterFirstCall, fullWindowNodeCount, "Precondition: the first call must defer.")
        XCTAssertGreaterThan(pendingAfterFirstCall, 0, "Precondition: something must actually be queued.")

        // A second call at the same camera position: nothing evicted, no new
        // residency, and the queued remainder is still outside the quickstart
        // ring, so it must stay queued.
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))

        XCTAssertEqual(
            streamer.mountedNodeCount, mountedAfterFirstCall,
            "A later updateCamera call mounted the deferred remainder synchronously — with per-frame "
                + "camera-follow that is the original single-frame stall, one frame later."
        )
        XCTAssertEqual(streamer.pendingMountCount, pendingAfterFirstCall)

        // And the remainder is not stranded: the per-frame drain still gets
        // the full window mounted.
        drainIncrementalMount(streamer)
        XCTAssertEqual(streamer.mountedNodeCount, fullWindowNodeCount)
        XCTAssertEqual(groundSprites(in: worldLayer).count, fullWindowNodeCount)
        XCTAssertEqual(
            worldLayer.children.count,
            streamer.mountedNodeCount + streamer.mountedBuildingNodeCount
        )
    }

    /// The same property under a per-frame camera-follow (`CYBERPUN-17-7`'s
    /// call pattern): `updateCamera` every frame, one drain tick per frame.
    /// No single frame may mount more than the quickstart ring's worth of
    /// chunks, and the window must still be complete once the camera settles.
    func test_perFrameCameraFollow_neverMountsMoreThanTheQuickstartRingInOneFrame() {
        let worldLayer = SKNode()
        let streamer = makeStreamer(worldLayer: worldLayer)

        let quickstartSide = ChunkStreamingManager.quickstartRadius * 2 + 1
        let quickstartChunkCount = quickstartSide * quickstartSide

        var previousMountedChunkCount = 0
        for frame in 0..<120 {
            // A camera walking forward a fraction of a tile per frame, i.e.
            // crossing chunk boundaries repeatedly over the run.
            streamer.updateCamera(worldPosition: TilePoint(x: Double(frame) * 0.75, y: 0))

            let mountedAfterUpdate = streamer.mountedChunks.count
            XCTAssertLessThanOrEqual(
                mountedAfterUpdate - previousMountedChunkCount, quickstartChunkCount,
                "frame \(frame): one updateCamera call mounted more than the quickstart ring — the "
                    + "synchronous mount per frame must stay bounded, not grow to the full window."
            )

            streamer.advanceIncrementalMount() // exactly what GameScene.update(_:) does, once per frame
            previousMountedChunkCount = streamer.mountedChunks.count
        }

        drainIncrementalMount(streamer)
        XCTAssertEqual(
            streamer.mountedNodeCount,
            ChunkStreamingManager.residentWindowSize * tilesPerChunk,
            "A camera that keeps moving must still converge on a fully mounted resident window."
        )
        XCTAssertEqual(streamer.mountedChunks, Set(streamer.streaming.residentChunks.keys))
    }
}
