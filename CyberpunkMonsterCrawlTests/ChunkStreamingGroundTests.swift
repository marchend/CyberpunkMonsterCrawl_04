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
/// on `unmountAll`). This suite covers the three things this PR's plan calls
/// out specifically and that suite does not: (1) resident node count staying
/// bounded across a genuinely long multi-chunk pan, not just a handful of
/// steps; (2) a chunk that streams out and later streams back in reusing
/// node identities from `GroundPlaneStreamer`'s recycle pool rather than
/// allocating without bound; and (3) no gap or duplicate ground node at any
/// tile of the resident window, checked at every step of a sweep that
/// repeatedly crosses chunk boundaries (AC1, the continuous-ground/no-seams
/// criterion, holding across a pan rather than only at a single camera
/// position).
final class ChunkStreamingGroundTests: XCTestCase {

    private let seed = WorldSeed(rawValue: 90_210)

    private var tilesPerChunk: Int { Chunk.size * Chunk.size }
    private var boundedNodeCount: Int { ChunkStreamingManager.residentWindowSize * tilesPerChunk }

    // MARK: - Bounded resident node count across a long pan

    /// Pans the camera far beyond any single chunk (hundreds of tiles, both
    /// along a single axis and diagonally) and asserts the mounted ground
    /// node count never grows past the fixed resident window \u2014 in
    /// particular, it must not creep upward the further the camera has
    /// travelled, which is exactly the failure mode a leaking mount/evict
    /// pairing would produce.
    func test_longMultiChunkPan_keepsMountedGroundNodeCountBounded() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        for step in stride(from: 0, through: 600, by: 9) {
            streamer.updateCamera(worldPosition: TilePoint(x: Double(step), y: Double(step) * 0.5))

            XCTAssertEqual(
                streamer.mountedNodeCount, boundedNodeCount,
                "step \(step): mounted ground node count drifted from the fixed resident window \u{2014} "
                    + "it must stay bounded no matter how far the camera has panned."
            )
            XCTAssertEqual(
                worldLayer.children.count, boundedNodeCount,
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
        var everSeenIdentities = Set(worldLayer.children.map(ObjectIdentifier.init))
        XCTAssertEqual(everSeenIdentities.count, boundedNodeCount, "The initial full mount must fill the window.")

        // Move far enough away that every chunk resident at the origin,
        // including the origin chunk itself, is evicted.
        let farOffset = Double((ChunkStreamingManager.residentRadius + 25) * Chunk.size)
        streamer.updateCamera(worldPosition: TilePoint(x: farOffset, y: farOffset))
        everSeenIdentities.formUnion(worldLayer.children.map(ObjectIdentifier.init))

        // Wander a little further while away, so more than one eviction
        // cycle has happened before returning.
        streamer.updateCamera(worldPosition: TilePoint(x: farOffset + 40, y: farOffset - 15))
        everSeenIdentities.formUnion(worldLayer.children.map(ObjectIdentifier.init))

        // Return to the origin, re-streaming the original chunks back in.
        streamer.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        everSeenIdentities.formUnion(worldLayer.children.map(ObjectIdentifier.init))

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
    /// not exceed the bounded window \u2014 "does not duplicate" at minimum, and
    /// in this implementation genuine identity reuse.
    func test_repeatedBackAndForthPan_stillReusesNodeIdentities_ratherThanGrowingWithoutBound() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)
        var everSeenIdentities = Set<ObjectIdentifier>()

        let waypoints: [Double] = [0, 120, -80, 200, -150, 40, 0]
        for x in waypoints {
            streamer.updateCamera(worldPosition: TilePoint(x: x, y: 0))
            everSeenIdentities.formUnion(worldLayer.children.map(ObjectIdentifier.init))
        }

        XCTAssertEqual(
            everSeenIdentities.count, boundedNodeCount,
            "Repeatedly crossing the same chunk boundaries back and forth must not keep allocating new "
                + "node identities \u{2014} evicted-chunk nodes must be recycled for newly resident chunks."
        )
    }

    // MARK: - No gaps or duplicates at chunk boundaries during a sweep

    /// At every step of a sweep that crosses many chunk boundaries, the set
    /// of tile coordinates covered by mounted ground nodes must exactly
    /// match the set of tiles belonging to the currently resident chunks:
    /// no missing tile (a gap \u2014 AC1's continuous-ground/no-seams criterion
    /// would be violated) and no tile covered by more than one node (a
    /// duplicate at a shared chunk edge).
    func test_sweepAcrossManyChunkBoundaries_hasNoGapOrDuplicateGroundNode() {
        let worldLayer = SKNode()
        let streamer = GroundPlaneStreamer(seed: seed, worldLayer: worldLayer)

        for step in stride(from: -160, through: 160, by: 5) {
            streamer.updateCamera(worldPosition: TilePoint(x: Double(step), y: Double(-step) * 0.75))

            let expectedTiles = expectedResidentTiles(for: streamer.streaming)

            let sprites = worldLayer.children.compactMap { $0 as? SKSpriteNode }
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
    /// computes \u2014 so this is a check against the streaming manager's
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

    // MARK: - Scaffolding debug pan (GameScene)

    /// The scaffolding debug pan (`GameScene.debugPanEnabled`) is what
    /// exercises multi-chunk streaming end-to-end in a running session per
    /// this PR's AC \u2014 this pins that it actually moves the camera across a
    /// chunk boundary over time, and that doing so keeps every scene
    /// invariant intact (no world content escaping its layer band, no node
    /// bypassing the scene's own touch dispatch).
    func test_debugPan_movesCameraAcrossAChunkBoundary_keepingSceneInvariantsIntact() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        scene.debugPanEnabled = true

        let startingChunk = ChunkCoordinate.containing(
            tileX: IsometricProjection.tile(containing: scene.cameraWorldPosition).tileX,
            tileY: IsometricProjection.tile(containing: scene.cameraWorldPosition).tileY
        )

        // Enough elapsed time, at `debugPanTilesPerSecond`, to cross at
        // least one `Chunk.size`-tile boundary.
        let secondsToCrossAChunk = Double(Chunk.size) / GameScene.debugPanTilesPerSecond
        scene.update(0)
        scene.update(secondsToCrossAChunk * 1.5)

        let endingChunk = ChunkCoordinate.containing(
            tileX: IsometricProjection.tile(containing: scene.cameraWorldPosition).tileX,
            tileY: IsometricProjection.tile(containing: scene.cameraWorldPosition).tileY
        )

        XCTAssertNotEqual(
            startingChunk, endingChunk,
            "The scaffolding debug pan must move the camera across a chunk boundary given enough time."
        )
        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "Debug-pan-streamed ground nodes escaped the world band: \(scene.layerBandViolationReport())"
        )
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
    }

    /// Off by default: a scene that never opts in must not have its camera
    /// move on its own when `update(_:)` runs, since that is exactly the
    /// real camera-follow behaviour this scaffolding explicitly must not
    /// stand in for.
    func test_debugPan_disabledByDefault_doesNotMoveTheCameraOnItsOwn() {
        let scene = GameScene(size: CGSize(width: 400, height: 800))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        XCTAssertFalse(scene.debugPanEnabled)

        let before = scene.cameraWorldPosition
        scene.update(0)
        scene.update(10)
        let after = scene.cameraWorldPosition

        XCTAssertEqual(before, after, "The camera must not move on its own unless the debug pan is explicitly enabled.")
    }
}
