import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-4-t3: `GroundTileRenderer` (PR 2) is wired into the existing
/// chunk-streaming system (`GroundPlaneStreamer` driving
/// `ChunkStreamingManager`) so ground tiles stream in/out with a bounded,
/// reused node pool and no visible pop-in of already-mounted ground.
///
/// `GroundPlaneStreamerTests` already pins the basic mount/evict contract
/// (one node per resident tile, no rebuild within the same chunk, torn down
/// on `unmountAll`). This suite covers what that one does not: (1) resident
/// node count staying bounded across a genuinely long multi-chunk pan, not
/// just a handful of steps; (2) a chunk that streams out and later streams
/// back in reusing node identities from `GroundPlaneStreamer`'s recycle pool
/// rather than allocating without bound; (3) no gap or duplicate ground node
/// at any tile of the resident window, checked at every step of a sweep that
/// repeatedly crosses chunk boundaries (AC1, the continuous-ground/no-seams
/// criterion, holding across a pan rather than only at a single camera
/// position); (4) the two sequences that are *not* a pan — `unmountAll()`
/// followed by `updateCamera`, and a run restarted through `GameScene` —
/// recycling the same nodes instead of re-allocating a whole window; and
/// (5) CYBERPUN-17-5-t3: a recycled *building* node carrying no stale
/// rooftop-sign child. That last one belongs here rather than in
/// `RooftopSignRenderingTests` precisely because it needs a real
/// evict-then-remount — a fresh mount from an empty pool never reaches
/// `dequeueOrMakeBuildingNode`'s strip, so the regression it guards (a pooled
/// node from a signed lot recycled onto an unsigned one and still rendering
/// the old sign) would ship green behind mount-time assertions.
///
/// Everything here drives the production streaming API. In particular
/// nothing references `GameScene.debugPanEnabled`: the
/// `SCAFFOLDING(CYBERPUN-17-7)` debug pan is a manual-inspection aid, and a
/// test asserting its behaviour would mean `CYBERPUN-17-7` could not remove
/// it without removing a green test.
final class ChunkStreamingGroundTests: XCTestCase {

    private let seed = WorldSeed(rawValue: 90_210)

    private var tilesPerChunk: Int { Chunk.size * Chunk.size }
    private var boundedNodeCount: Int { ChunkStreamingManager.residentWindowSize * tilesPerChunk }

    /// The mounted **ground** nodes among `worldLayer`'s children.
    ///
    /// Since CYBERPUN-17-5-t2 the same layer also carries one building node
    /// per `Chunk.buildingPlacements` record, so every claim in this suite
    /// about "one node per resident tile" has to name which population it
    /// means rather than taking every child \u{2014} a chunk's building count
    /// varies with how many block interiors it owns, so counting both
    /// together against `boundedNodeCount` measures the wrong thing.
    /// Filtered by `GroundPlaneStreamer.nodeName`, the name the mount stamps
    /// for exactly this purpose.
    private func groundSprites(in worldLayer: SKNode) -> [SKSpriteNode] {
        worldLayer.children
            .compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == GroundPlaneStreamer.nodeName }
    }

    /// The object identities of the currently mounted ground nodes \u{2014} the
    /// population the recycle-pool claims below are about (`pool` is
    /// ground-only; building nodes have their own `buildingPool`).
    private func groundIdentities(in worldLayer: SKNode) -> Set<ObjectIdentifier> {
        Set(groundSprites(in: worldLayer).map(ObjectIdentifier.init))
    }

    /// The mounted **building** nodes among `worldLayer`'s children, named
    /// through `TileFieldRenderer.buildingNodeName` for the same reason
    /// `groundSprites(in:)` names the ground population: the two share the
    /// layer, and a claim about one must not silently start measuring both.
    private func buildingSprites(in worldLayer: SKNode) -> [SKSpriteNode] {
        worldLayer.children
            .compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == TileFieldRenderer.buildingNodeName }
    }

    /// Every rooftop-sign child of `buildingNode` — as a list rather than a
    /// single `childNode(withName:)` lookup, so "the strip left the old sign
    /// behind *underneath* a newly attached one" is a detectable state (that
    /// lookup returns only the first match, and both nodes carry the same
    /// name).
    private func signChildren(of buildingNode: SKSpriteNode) -> [SKNode] {
        buildingNode.children.filter { $0.name == RooftopSignRenderer.signNodeName }
    }

    /// The rounded screen point a mounted building node for `lotTile` sits
    /// at, derived the way `TileFieldRenderer.configure` derives it — how a
    /// `RooftopSignRecord`'s carrier lot is matched to the node that carries
    /// it. `IsometricProjection.tileToScreen` is injective over distinct
    /// integer tiles, so this is a unique key per lot.
    private func mountedPosition(ofLotTile lotTile: TileCoordinate) -> CGPoint {
        let screenPoint = IsometricProjection.tileToScreen(
            tileX: Double(lotTile.tileX),
            tileY: Double(lotTile.tileY)
        )
        return CGPoint(x: screenPoint.x.rounded(), y: screenPoint.y.rounded())
    }

    /// Brings `streamer` to the fully-mounted steady state the way the
    /// shipped code does: repeated `advanceIncrementalMount()` ticks, which
    /// is exactly what `GameScene.update(_:)` drives once per frame.
    ///
    /// CYBERPUN-17-4-t4: `updateCamera` mounts only the quickstart ring and
    /// defers the rest, so the residency, reuse and no-gap invariants below
    /// have to reach the full window somehow — going through the production
    /// drain means they stay pinned on the path the app actually takes rather
    /// than on a test-only entry point.
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

    // MARK: - Bounded resident node count across a long pan

    /// Pans the camera far beyond any single chunk (hundreds of tiles, both
    /// along a single axis and diagonally) and asserts the mounted ground
    /// node count never grows past the fixed resident window — in
    /// particular, it must not creep upward the further the camera has
    /// travelled, which is exactly the failure mode a leaking mount/evict
    /// pairing would produce.
    func test_longMultiChunkPan_keepsMountedGroundNodeCountBounded() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        for step in stride(from: 0, through: 600, by: 9) {
            streamer.updateCamera(worldPosition: TilePoint(x: Double(step), y: Double(step) * 0.5))
            // CYBERPUN-17-4-t4: each call only mounts the quickstart ring
            // synchronously; drain through the production per-frame path so
            // every step asserts the steady-state bounded count this test is
            // about, rather than the deliberately-partial mid-mount state.
            drainIncrementalMount(streamer)

            XCTAssertEqual(
                streamer.mountedNodeCount, boundedNodeCount,
                "step \(step): mounted ground node count drifted from the fixed resident window \u{2014} "
                    + "it must stay bounded no matter how far the camera has panned."
            )
            XCTAssertEqual(
                groundSprites(in: worldLayer).count, boundedNodeCount,
                "step \(step): the scene graph itself grew past the bounded window \u{2014} evicted chunks "
                    + "must leave no orphan nodes behind."
            )
        }
    }

    // MARK: - Reuse: a chunk that streams out and back in does not allocate without bound

    /// Drives the camera through a mount -> far-away eviction -> return
    /// cycle and records every distinct `SKSpriteNode` identity that ever
    /// appears in the scene graph along the way. If nodes were freshly
    /// allocated on every mount (rather than recycled from the pool of
    /// nodes freed by eviction), the set of identities ever seen would grow
    /// with each stream-out/stream-in cycle; because eviction always frees
    /// exactly as many nodes as the following mount pass needs (the window
    /// is a fixed size), a correctly pooling implementation never allocates
    /// past the very first full mount.
    func test_chunkStreamingOutAndBackIn_reusesNodeIdentities_neverExceedingTheBoundedWindow() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        // CYBERPUN-17-4-t4: the call defers most of the window; drain to
        // reach the full initial mount this test's identity-reuse claim is
        // built on.
        drainIncrementalMount(streamer)
        var everSeenIdentities = groundIdentities(in: worldLayer)
        XCTAssertEqual(everSeenIdentities.count, boundedNodeCount, "The initial full mount must fill the window.")

        // Move far enough away that every chunk resident at the origin,
        // including the origin chunk itself, is evicted.
        let farOffset = Double((ChunkStreamingManager.residentRadius + 25) * Chunk.size)
        streamer.updateCamera(worldPosition: TilePoint(x: farOffset, y: farOffset))
        everSeenIdentities.formUnion(groundIdentities(in: worldLayer))

        // Wander a little further while away, so more than one eviction
        // cycle has happened before returning.
        streamer.updateCamera(worldPosition: TilePoint(x: farOffset + 40, y: farOffset - 15))
        everSeenIdentities.formUnion(groundIdentities(in: worldLayer))

        // Return to the origin, re-streaming the original chunks back in.
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        everSeenIdentities.formUnion(groundIdentities(in: worldLayer))

        XCTAssertEqual(
            everSeenIdentities.count, boundedNodeCount,
            "A stream-out/stream-in cycle allocated new SKSpriteNode identities instead of reusing the "
                + "pool of nodes freed by eviction \u{2014} the resident window is a fixed size, so the total "
                + "number of distinct nodes ever created must never exceed it."
        )
    }

    /// The same reuse property, checked as a long walk rather than a single
    /// out-and-back trip: many chunk boundaries are crossed, in both
    /// directions, and the set of node identities ever mounted still must
    /// not exceed the bounded window — "does not duplicate" at minimum, and
    /// in this implementation genuine identity reuse.
    func test_repeatedBackAndForthPan_stillReusesNodeIdentities_ratherThanGrowingWithoutBound() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)
        var everSeenIdentities = Set<ObjectIdentifier>()

        let waypoints: [Double] = [0, 120, -80, 200, -150, 40, 0]
        for x in waypoints {
            streamer.updateCamera(worldPosition: TilePoint(x: x, y: 0))
            // CYBERPUN-17-4-t4: drain every step so the identity-reuse claim
            // is checked against the steady state, not a deliberately partial
            // mid-mount snapshot.
            drainIncrementalMount(streamer)
            everSeenIdentities.formUnion(groundIdentities(in: worldLayer))
        }

        XCTAssertEqual(
            everSeenIdentities.count, boundedNodeCount,
            "Repeatedly crossing the same chunk boundaries back and forth must not keep allocating new "
                + "node identities \u{2014} evicted-chunk nodes must be recycled for newly resident chunks."
        )
    }

    // MARK: - Recycled building nodes carry no stale rooftop sign (CYBERPUN-17-5-t3)

    /// A building node freed by eviction goes back into `buildingPool` with
    /// whatever children it had — including a rooftop-sign child, which is
    /// never pooled separately. `dequeueOrMakeBuildingNode` strips that child
    /// before `TileFieldRenderer.configure` re-textures the node, and this is
    /// the test that reaches that line: the regression it guards is "pan away
    /// from a signed building, pan back, and its recycled node keeps
    /// rendering the old sign over an unsigned lot", which no fresh-mount
    /// assertion in `RooftopSignRenderingTests` can see because a fresh mount
    /// dequeues from an empty pool.
    ///
    /// Asserted as an exact correspondence rather than just "no leftovers":
    /// after the pan, a mounted building node carries a sign child **iff** its
    /// lot is a carrier lot of a currently resident sign, and the sign it
    /// carries crops that record's own atlas cell — so a stale sign, a
    /// *wrong-variant* sign left underneath a newly attached one, and a
    /// dropped sign are all failures here.
    func test_recycledBuildingNodes_carryNoStaleRooftopSign_afterAPanThatEvictsSignedBuildings() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        drainIncrementalMount(streamer)

        let previouslySignedNodes = Set(
            buildingSprites(in: worldLayer)
                .filter { !signChildren(of: $0).isEmpty }
                .map(ObjectIdentifier.init)
        )
        XCTAssertGreaterThan(
            previouslySignedNodes.count, 0,
            "Precondition: the window at the origin must mount at least one signed building, or the recycle "
                + "path this test is about is never fed a node carrying a sign."
        )

        // Pan far enough that every chunk resident at the origin is evicted,
        // handing its building nodes — the signed ones included — to
        // `buildingPool`, so the mount that follows is served by recycled
        // nodes rather than fresh allocations.
        let farOffset = Double((ChunkStreamingManager.residentRadius + 25) * Chunk.size)
        streamer.updateCamera(worldPosition: TilePoint(x: farOffset, y: farOffset))
        drainIncrementalMount(streamer)

        let mountedBuildings = buildingSprites(in: worldLayer)
        let recycledPreviouslySignedNodes = mountedBuildings
            .filter { previouslySignedNodes.contains(ObjectIdentifier($0)) }
        XCTAssertGreaterThan(
            recycledPreviouslySignedNodes.count, 0,
            "Anti-vacuity: no node that previously carried a sign was recycled into this window, so the "
                + "assertions below would pass without ever exercising the strip in "
                + "dequeueOrMakeBuildingNode."
        )

        var signsByCarrierPosition: [CGPoint: RooftopSignRecord] = [:]
        for sign in streamer.streaming.residentChunks.values.flatMap(\.roofSigns) {
            signsByCarrierPosition[mountedPosition(ofLotTile: sign.carrierLotTile)] = sign
        }

        for node in mountedBuildings {
            let signs = signChildren(of: node)
            guard let expectedSign = signsByCarrierPosition[node.position] else {
                XCTAssertTrue(
                    signs.isEmpty,
                    "A building node mounted at \(node.position) carries \(signs.count) rooftop-sign "
                        + "child(ren) but its lot is not a carrier lot of any resident sign — a recycled "
                        + "node kept a previous occupant's sign."
                )
                continue
            }

            XCTAssertEqual(
                signs.count, 1,
                "The carrier building at \(node.position) has \(signs.count) sign children; a recycled node "
                    + "must end up with exactly the one sign this mount attached, never the new sign stacked "
                    + "over a stale one."
            )

            let expectedCell = AtlasCellIndex.signs[expectedSign.signCellIndex]
            let expectedTexture = AtlasSheet.signs.sheet.texture(col: expectedCell.col, row: expectedCell.row)
            guard let mountedTexture = (signs.first as? SKSpriteNode)?.texture else {
                XCTFail("The sign mounted at \(node.position) carries no texture.")
                continue
            }
            XCTAssertEqual(
                mountedTexture.textureRect(), expectedTexture.textureRect(),
                "The sign mounted on the carrier building at \(node.position) crops a different "
                    + "sprite_signs cell than its record's signCellIndex "
                    + "(\(expectedSign.signCellIndex)) — a recycled node is showing the wrong variant."
            )
        }
    }

    // MARK: - No gaps or duplicates at chunk boundaries during a sweep

    /// At every step of a sweep that crosses many chunk boundaries, the set
    /// of tile coordinates covered by mounted ground nodes must exactly
    /// match the set of tiles belonging to the currently resident chunks:
    /// no missing tile (a gap — AC1's continuous-ground/no-seams criterion
    /// would be violated) and no tile covered by more than one node (a
    /// duplicate at a shared chunk edge).
    func test_sweepAcrossManyChunkBoundaries_hasNoGapOrDuplicateGroundNode() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        for step in stride(from: -160, through: 160, by: 5) {
            streamer.updateCamera(worldPosition: TilePoint(x: Double(step), y: Double(-step) * 0.75))
            // CYBERPUN-17-4-t4: drain so every step's "mounted tiles must
            // equal resident tiles" check runs against the fully-mounted
            // window, not the deliberately-partial mid-mount state.
            drainIncrementalMount(streamer)

            let expectedTiles = expectedResidentTiles(for: streamer.streaming)

            let sprites = groundSprites(in: worldLayer)
            let mountedTiles = sprites.map { sprite -> TileCoordinate in
                let owningTile = IsometricProjection.tile(containing: sprite.position)
                return TileCoordinate(tileX: owningTile.tileX, tileY: owningTile.tileY)
            }

            XCTAssertEqual(
                mountedTiles.count, sprites.count,
                "step \(step): could not resolve a tile coordinate for every mounted sprite."
            )

            let mountedTileSet = Set(mountedTiles)
            XCTAssertEqual(
                mountedTileSet.count, mountedTiles.count,
                "step \(step): more than one ground node was mounted for the same tile coordinate \u{2014} "
                    + "a duplicate, most likely at a shared chunk boundary."
            )
            XCTAssertEqual(
                mountedTileSet, expectedTiles,
                "step \(step): mounted ground tiles disagreed with the resident chunk window \u{2014} either a "
                    + "gap (a resident tile with no node) or a stray node for a tile that is not resident."
            )
        }
    }

    /// Every world tile belonging to any chunk `manager` currently
    /// considers resident, derived independently from `ChunkCoordinate`'s
    /// own `worldTileOrigin` rather than from anything `GroundPlaneStreamer`
    /// computes — so this is a check against the streaming manager's
    /// ground truth, not a restatement of the mount code under test.
    private func expectedResidentTiles(for manager: ChunkStreamingManager) -> Set<TileCoordinate> {
        var tiles: Set<TileCoordinate> = []
        for coordinate in manager.residentChunks.keys {
            let origin = coordinate.worldTileOrigin
            for dx in 0..<Chunk.size {
                for dy in 0..<Chunk.size {
                    tiles.insert(TileCoordinate(tileX: origin.tileX + dx, tileY: origin.tileY + dy))
                }
            }
        }
        return tiles
    }

    // MARK: - Scene invariants hold while the ground streams

    /// Streaming across chunk boundaries inside a real `GameScene` must keep
    /// both structural invariants the scene audits intact: no world content
    /// escaping its layer band (the v1 "world paints over UI" failure), and
    /// no node bypassing the scene's own touch dispatch.
    ///
    /// Driven through `GameScene.groundPlane`'s own `updateCamera` rather
    /// than through the `SCAFFOLDING(CYBERPUN-17-7)` debug pan. The property
    /// under test is a *streaming* property, and pinning it to the debug pan
    /// would mean `CYBERPUN-17-7` could not delete that scaffolding without
    /// deleting a green test — which is how temporary code becomes
    /// permanent. Nothing in this suite references `debugPanEnabled`.
    func test_streamingAcrossChunkBoundariesInAScene_keepsEverySceneInvariantIntact() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        guard let plane = scene.groundPlane else {
            return XCTFail("Entering .gameplay must start the ground plane.")
        }

        let startingChunk = chunk(containing: TilePoint(x: 0, y: 0))
        var endingChunk = startingChunk

        for step in stride(from: 0.0, through: Double(Chunk.size * 6), by: 3) {
            let position = TilePoint(x: step, y: step * 0.5)
            plane.updateCamera(worldPosition: position)
            // CYBERPUN-17-4-t4: mounting is deferred past the quickstart
            // ring, so drain through the production per-frame path before
            // asserting the full-window count.
            drainIncrementalMount(plane)
            endingChunk = chunk(containing: position)

            XCTAssertTrue(
                scene.nodesEscapingTheirLayerBand().isEmpty,
                "step \(step): streamed ground nodes escaped the world band: "
                    + "\(scene.layerBandViolationReport())"
            )
            XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
            XCTAssertEqual(
                groundChildren(of: scene).count, boundedNodeCount,
                "step \(step): the scene graph grew past the fixed resident window."
            )
        }

        XCTAssertNotEqual(
            startingChunk, endingChunk,
            "The sweep must actually cross chunk boundaries, or it pins nothing about streaming."
        )
    }

    // MARK: - Teardown and restart reuse the pool rather than reallocating

    /// `unmountAll()` -> `updateCamera` is a supported sequence (it is what a
    /// restarted run does), and it must not re-allocate a whole resident
    /// window's worth of `SKSpriteNode`s.
    ///
    /// `unmountAll()` leaves `streaming.residentChunks` untouched, so the
    /// following `updateCamera` re-mounts the very same window; the nodes it
    /// detached therefore have to go back into the recycle pool, not on the
    /// floor. The three tests above only ever pan, so this is the path they
    /// do not reach.
    func test_unmountAllThenUpdateCamera_recyclesTheTornDownNodes_ratherThanReallocatingTheWindow() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        // CYBERPUN-17-4-t4: drain so `firstMount` is the full window this
        // test's recycling claim is about, not the quickstart-only partial
        // state the call now leaves mid-mount.
        drainIncrementalMount(streamer)
        let firstMount = groundIdentities(in: worldLayer)
        XCTAssertEqual(firstMount.count, boundedNodeCount)

        streamer.unmountAll()
        XCTAssertTrue(worldLayer.children.isEmpty, "unmountAll must detach every node from the scene graph.")
        XCTAssertEqual(streamer.mountedNodeCount, 0)
        XCTAssertEqual(
            streamer.pooledNodeCount, boundedNodeCount,
            "unmountAll dropped its nodes instead of returning them to the recycle pool, so the next "
                + "updateCamera has to allocate a whole resident window again."
        )

        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        // CYBERPUN-17-4-t4: the re-mount is incremental too, so let the
        // per-frame drain finish before comparing node identities.
        drainIncrementalMount(streamer)
        let secondMount = groundIdentities(in: worldLayer)

        XCTAssertEqual(secondMount.count, boundedNodeCount)
        XCTAssertEqual(
            secondMount, firstMount,
            "Re-mounting after unmountAll allocated fresh SKSpriteNode identities instead of recycling "
                + "the ones it had just torn down."
        )
    }

    /// The scene-level half of the same property: RUN AGAIN with an unchanged
    /// seed is the same city, so `startGroundPlane()` keeps the existing
    /// streamer (and with it the pool) instead of building a replacement
    /// whose pool starts empty — which would re-allocate the whole window on
    /// every restart.
    func test_restartingARunWithTheSameSeed_keepsTheStreamer_soNoWindowIsReallocated() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        // CYBERPUN-17-4-t4: drain so `firstNodes` is the steady state RUN
        // AGAIN is being compared against, not a mid-mount snapshot from the
        // deliberately-partial first entry.
        drainIncrementalMount(scene.groundPlane)
        let firstPlane = scene.groundPlane
        let firstNodes = Set(groundChildren(of: scene).map(ObjectIdentifier.init))
        XCTAssertNotNil(firstPlane)

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        XCTAssertTrue(
            scene.groundPlane === firstPlane,
            "An unchanged seed is the same city, so the run restart must reuse the streamer."
        )
        XCTAssertEqual(
            Set(groundChildren(of: scene).map(ObjectIdentifier.init)), firstNodes,
            "Restarting the run rebuilt the ground plane's nodes instead of keeping the mounted ones."
        )
    }

    /// The other side of that decision: a *different* seed is a different
    /// city, so the mounted ground genuinely cannot be reused and the
    /// streamer is replaced.
    func test_restartingARunWithADifferentSeed_replacesTheStreamer_andLeavesNoStaleGround() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let firstPlane = scene.groundPlane
        XCTAssertNotNil(firstPlane)

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        scene.worldSeed = WorldSeed(rawValue: seed.rawValue &+ 1)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        // CYBERPUN-17-4-t4: the replacement streamer's mount is also only the
        // quickstart ring; drain so the assertions below check the steady
        // state ("no stale ground, and the new city is fully there"),
        // matching what this test asserted before the incremental-mount fix.
        drainIncrementalMount(scene.groundPlane)

        XCTAssertFalse(
            scene.groundPlane === firstPlane,
            "A new seed must not keep streaming the previous run's city."
        )
        XCTAssertEqual(
            groundChildren(of: scene).count, scene.groundPlane?.mountedNodeCount,
            "The replaced ground plane left stale nodes behind in worldLayer."
        )
        XCTAssertEqual(groundChildren(of: scene).count, boundedNodeCount)
    }

    // MARK: - Incremental first mount does not gap/duplicate while draining (CYBERPUN-17-4-t4)

    /// Draining the incremental-mount queue tick by tick (the stand-in for
    /// `GameScene.update(_:)` calling `advanceIncrementalMount()` once per
    /// frame) must never mount the same tile twice, checked at *every* tick
    /// of the drain rather than only once it finishes — the "no node ever
    /// double-mounted or dropped" half of this story's fix.
    func test_incrementalMountDrain_neverDoubleMountsATile_atAnyTickOfTheDrain() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        XCTAssertLessThan(streamer.mountedNodeCount, boundedNodeCount, "Precondition: the first call must defer.")

        var ticks = 0
        while streamer.mountedNodeCount < boundedNodeCount, ticks < 50 {
            streamer.advanceIncrementalMount()
            ticks += 1

            let sprites = groundSprites(in: worldLayer)
            let mountedTiles = sprites.map { sprite -> TileCoordinate in
                let owningTile = IsometricProjection.tile(containing: sprite.position)
                return TileCoordinate(tileX: owningTile.tileX, tileY: owningTile.tileY)
            }
            XCTAssertEqual(
                Set(mountedTiles).count, mountedTiles.count,
                "tick \(ticks): a tile was mounted more than once mid-drain."
            )
            XCTAssertEqual(groundSprites(in: worldLayer).count, streamer.mountedNodeCount)
        }

        XCTAssertEqual(
            streamer.mountedNodeCount, boundedNodeCount,
            "The drain must eventually reach the full resident window within a bounded number of ticks."
        )
        XCTAssertEqual(streamer.mountedChunks, Set(streamer.streaming.residentChunks.keys))
    }

    /// The **ground** nodes mounted in `scene.worldLayer`.
    ///
    /// `GameScene` also mounts the player there (`CYBERPUN-17-6-t2`), and the
    /// streamer mounts one building node per `Chunk.buildingPlacements`
    /// record of every resident chunk (`CYBERPUN-17-5-t2`), while every count
    /// in this file is a claim about the streamed resident *ground* window --
    /// comparing raw `children.count` against `boundedNodeCount` (or against
    /// the ground-only `mountedNodeCount`) would silently start measuring
    /// "ground plus whatever else the scene mounts", which is not the
    /// property these tests exist to pin. So this names the ground population
    /// the same way `groundSprites(in:)` does, through
    /// `GroundPlaneStreamer.nodeName`.
    private func groundChildren(of scene: GameScene) -> [SKNode] {
        groundSprites(in: scene.worldLayer)
    }

    /// The chunk owning `position`, resolved through the same seam rule the
    /// streaming manager uses.
    private func chunk(containing position: TilePoint) -> ChunkCoordinate {
        let tile = IsometricProjection.tile(containing: position)
        return ChunkCoordinate.containing(tileX: tile.tileX, tileY: tile.tileY)
    }
}
