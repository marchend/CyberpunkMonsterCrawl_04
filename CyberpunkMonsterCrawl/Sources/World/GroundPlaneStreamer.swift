import CoreGraphics
import SpriteKit

/// Mounts the ground plane into `GameScene.worldLayer`: the production
/// consumer of `GroundTileRenderer`, driven by `ChunkStreamingManager`'s
/// resident chunk window.
///
/// `GroundTileRenderer.node(for:at:)` is a factory, and a factory with no
/// caller renders nothing in a real build \u2014 the story's headline AC (\"render
/// every generated ground cell\", product gate 4: *the city has to read as a
/// city*) is only observable once something parents those nodes into the
/// scene. This is that something, and it is deliberately the *smallest* thing
/// that makes the ground observable on device rather than a full world
/// renderer: it mounts ground nodes and nothing else. Buildings, actors and
/// camera following land with `CYBERPUN-17-5` onward and will mount into the
/// same `worldLayer` alongside these nodes.
///
/// **Node ownership mirrors chunk residency.** One node per tile of every
/// resident chunk; when `ChunkStreamingManager` evicts a chunk, this drops
/// that chunk's nodes in the same pass. The resident window is a fixed size
/// (`ChunkStreamingManager.residentWindowSize`), so the mounted node count is
/// bounded however far the camera roams \u2014 the scene-graph counterpart of AC8,
/// and pinned by `GroundPlaneStreamerTests`.
///
/// Nodes are parented **directly** under `worldLayer` (no intermediate
/// container) because `GroundTileRenderer` sets a `worldLayer`-*relative*
/// `zPosition`: SpriteKit accumulates `zPosition` down the tree, so an
/// intermediate node with any non-zero `zPosition` would silently shift every
/// ground tile out of the depth scheme `DepthModel` computed.
///
/// **`CYBERPUN-17-4-t4`: the very first mount is incremental, not one giant
/// synchronous pass.** A runtime probe reported "PLAY tapped, screen never
/// visibly left the menu"; the cause was that the *first* `updateCamera` call
/// on a brand-new streamer used to build/mount every tile of the entire
/// resident window (up to `ChunkStreamingManager.residentWindowSize *
/// Chunk.size * Chunk.size` = 3,136 `SKSpriteNode`s) inside the same call
/// stack as the PLAY tap \u2014 real, uninterrupted main-thread work with no
/// yield point. Now that very first call mounts only the
/// `ChunkStreamingManager.quickstartRadius` ring around the camera
/// synchronously (enough to fill a typical viewport, so the next rendered
/// frame already shows a street) and queues the remainder of the window in
/// `pendingMountQueue`, drained a few chunks at a time by
/// `advanceIncrementalMount()` \u2014 which `GameScene.update(_:)` calls every
/// frame. Every call *after* the first behaves exactly as before: any newly
/// resident chunk (from ordinary panning) is mounted immediately, and it also
/// folds in anything still sitting in `pendingMountQueue` from an earlier
/// deferred first mount (the RUN AGAIN path: the same streamer instance is
/// kept across a restart, so its second-ever `updateCamera` call drains
/// whatever the first one queued). `flushPendingMounts()` mounts the queue's
/// remainder synchronously on demand for a caller (or a test) that needs the
/// full window to exist right now rather than waiting for further ticks.
final class GroundPlaneStreamer {

    /// Streams the chunk window this mount follows. Owned here (rather than
    /// injected from the scene) so the ground plane has exactly one source of
    /// truth for \"which tiles exist right now\".
    let streaming: ChunkStreamingManager

    /// The world seed `streaming` generates from. Exposed so a caller
    /// restarting a run (`GameScene.startGroundPlane()`) can tell whether the
    /// mounted city is still the right one and keep this streamer \u2014 along
    /// with its `pool` and its already-generated chunks \u2014 instead of building
    /// a replacement whose pool starts empty.
    let seed: WorldSeed

    /// The layer ground nodes are parented into. Weak: the scene owns the
    /// layer, and this mount must never keep a dead scene's graph alive.
    private weak var worldLayer: SKNode?

    /// Mounted nodes, grouped by the chunk whose residency they follow, so an
    /// eviction is an O(tiles-per-chunk) removal rather than a full rescan.
    private var nodesByChunk: [ChunkCoordinate: [SKSpriteNode]] = [:]

    /// Chunks that are currently resident (`streaming.residentChunks`) but
    /// not yet mounted, in the order they should be mounted \u2014 populated by
    /// the very first `updateCamera` call's quickstart split, and drained by
    /// `advanceIncrementalMount()` / `flushPendingMounts()`. Empty once the
    /// deferred remainder has fully landed, and for the entire lifetime of a
    /// streamer whose first call never needed to defer anything (there is
    /// nothing to defer once a full mount has already happened once).
    private var pendingMountQueue: [ChunkCoordinate] = []

    /// Whether `updateCamera` has ever been called on this instance. The
    /// quickstart/incremental split only applies to that very first call \u2014
    /// every later call (ordinary panning, or a RUN AGAIN that reuses this
    /// same streamer) mounts immediately, exactly as before `CYBERPUN-17-4-t4`.
    private var hasPerformedInitialMount = false

    /// How many queued chunks `advanceIncrementalMount()` mounts per call.
    /// `GameScene.update(_:)` calls it once per frame, so this is also \"how
    /// many chunks stream in per frame\" while the deferred remainder drains.
    /// Small enough that a single tick's mounting work cannot itself become a
    /// visible stall (each chunk is `Chunk.size * Chunk.size` = 64 sprite
    /// configurations \u2014 a small fraction of the ~3,136-node pass this exists
    /// to avoid), large enough that the full window still lands within a
    /// handful of frames.
    static let defaultChunksPerIncrementalMountTick = 6

    /// Nodes this mount has given up \u2014 because their chunk streamed out of
    /// the resident window, or because `unmountAll()` tore the whole window
    /// down \u2014 held here for reuse rather than deallocated.
    ///
    /// `CYBERPUN-17-4-t3`: without this, every chunk that streams in would
    /// allocate a fresh `SKSpriteNode` per tile, so panning far enough would
    /// have allocated and discarded many multiples of the resident window's
    /// worth of nodes even though only `mountedNodeCount` are ever on screen
    /// at once.
    ///
    /// **The invariant, scoped to what actually holds.** For a given
    /// `GroundPlaneStreamer` instance, after the first `updateCamera` fills
    /// the window from empty (whether that happens in one call or is spread
    /// across the incremental mount this file adds in `CYBERPUN-17-4-t4`), no
    /// further `SKSpriteNode` is allocated by either supported call sequence:
    /// - *Panning.* Eviction runs (in `synchroniseWithResidentChunks`)
    ///   *before* the mount pass of the same `updateCamera` call, and the
    ///   resident window is a fixed size, so the nodes freed by eviction on
    ///   any call are exactly what the mount pass needs that same call.
    /// - *`unmountAll()` then `updateCamera`* (what a restarted run does).
    ///   `unmountAll()` returns every node it detaches to this pool rather
    ///   than dropping it, and it leaves `streaming.residentChunks` alone, so
    ///   the re-mount asks for exactly the window's worth the pool is now
    ///   holding. Both paths are pinned by `ChunkStreamingGroundTests`.
    ///
    /// The invariant is per instance and cannot be otherwise: a brand-new
    /// `GroundPlaneStreamer` starts with an empty pool by construction, so a
    /// caller that discards this object discards the pool with it. That is
    /// why `GameScene.startGroundPlane()` keeps the existing streamer when
    /// the run's seed is unchanged instead of building a fresh one per run.
    ///
    /// Capped defensively at `maxPoolSize` regardless, so a call pattern the
    /// reasoning above doesn't cover still can't grow memory without bound.
    private var pool: [SKSpriteNode] = []

    /// Nodes currently parked in the recycle pool. Exposed for the tests that
    /// pin the invariant on `pool`'s doc comment (notably the
    /// `unmountAll()` -> `updateCamera` sequence, where the pool is what
    /// stands between a restarted run and a whole window of fresh
    /// allocations).
    var pooledNodeCount: Int { pool.count }

    /// Defensive cap on `pool`'s size \u2014 see `pool`'s doc comment for why it
    /// should never need to hold more than one resident window's worth.
    private static var maxPoolSize: Int { ChunkStreamingManager.residentWindowSize * Chunk.size * Chunk.size }

    init(seed: WorldSeed, worldLayer: SKNode) {
        self.seed = seed
        self.streaming = ChunkStreamingManager(seed: seed)
        self.worldLayer = worldLayer
    }

    /// Chunks currently mounted in the scene graph.
    var mountedChunks: Set<ChunkCoordinate> { Set(nodesByChunk.keys) }

    /// Total ground nodes currently in the scene graph. Bounded by
    /// `ChunkStreamingManager.residentWindowSize * Chunk.size * Chunk.size`.
    var mountedNodeCount: Int { nodesByChunk.values.reduce(0) { $0 + $1.count } }

    /// Moves the camera to `worldPosition` (tile space) and brings the scene
    /// graph back in step with chunk residency: mounts a node per tile of
    /// every newly resident chunk, and removes the nodes of every chunk that
    /// was just evicted.
    ///
    /// Idempotent for a camera that hasn't left its chunk \u2014 the streaming
    /// manager's resident set is unchanged, so no node is rebuilt.
    ///
    /// The very first call on a given instance mounts only the
    /// `ChunkStreamingManager.quickstartRadius` ring synchronously and queues
    /// the rest for `advanceIncrementalMount()` \u2014 see the type doc comment
    /// for why. Every later call mounts immediately, exactly as before
    /// `CYBERPUN-17-4-t4`.
    func updateCamera(worldPosition: TilePoint) {
        let isFirstEverCall = !hasPerformedInitialMount
        hasPerformedInitialMount = true

        streaming.updateCamera(worldPosition: worldPosition)
        synchroniseWithResidentChunks(cameraWorldPosition: worldPosition, isFirstEverCall: isFirstEverCall)
    }

    /// Mounts up to `maxChunksPerTick` chunks still waiting in
    /// `pendingMountQueue`, synchronously. `GameScene.update(_:)` calls this
    /// every frame (in Release builds too, not just DEBUG \u2014 this is a
    /// correctness fix, not scaffolding) so the chunks the first
    /// `updateCamera` call deferred land over the next few frames rather than
    /// never. A no-op once the queue is empty, so it is always safe to call
    /// unconditionally.
    ///
    /// Returns the number of chunks actually mounted this call, mainly for
    /// tests that want to bound how many ticks a full drain takes.
    @discardableResult
    func advanceIncrementalMount(
        maxChunksPerTick: Int = GroundPlaneStreamer.defaultChunksPerIncrementalMountTick
    ) -> Int {
        guard let worldLayer, !pendingMountQueue.isEmpty else { return 0 }

        var mountedThisTick = 0
        while mountedThisTick < maxChunksPerTick, !pendingMountQueue.isEmpty {
            let coordinate = pendingMountQueue.removeFirst()
            // The chunk may have streamed back out of residency (the camera
            // kept moving) before its turn came up, or may already have been
            // mounted by an intervening non-incremental `updateCamera` call
            // (see `synchroniseWithResidentChunks`'s \"else\" branch, which
            // folds the queue in). Either way, skip it rather than double-
            // mount or resurrect an evicted chunk's nodes.
            guard streaming.residentChunks[coordinate] != nil, nodesByChunk[coordinate] == nil else { continue }
            mountChunk(coordinate, into: worldLayer)
            mountedThisTick += 1
        }
        return mountedThisTick
    }

    /// Mounts every chunk still waiting in `pendingMountQueue` right now,
    /// synchronously, draining the queue completely in one call. Exists for a
    /// caller (or a test) that needs the full resident window to exist
    /// immediately rather than waiting for further `advanceIncrementalMount()`
    /// ticks \u2014 the same full-window guarantee the mount used to make on every
    /// call, before `CYBERPUN-17-4-t4` made the *first* call incremental.
    func flushPendingMounts() {
        guard let worldLayer else { return }
        for coordinate in pendingMountQueue {
            guard streaming.residentChunks[coordinate] != nil, nodesByChunk[coordinate] == nil else { continue }
            mountChunk(coordinate, into: worldLayer)
        }
        pendingMountQueue.removeAll()
    }

    /// Removes every mounted ground node from the scene graph. Called when a
    /// run ends (or a new one starts with a different seed), so a fresh world
    /// never inherits the previous one's tiles.
    ///
    /// Detached nodes go back into `pool` rather than being dropped: this
    /// call does not touch `streaming`, so `residentChunks` is unchanged and
    /// the next `updateCamera` re-mounts the very same window. Dropping them
    /// would make that re-mount allocate a full resident window's worth of
    /// `SKSpriteNode`s \u2014 precisely the churn the pool exists to remove \u2014 and
    /// would leave `pool`'s stated invariant false for a supported sequence.
    ///
    /// Also clears `pendingMountQueue`: after every mounted node is torn
    /// down, \"pending\" is meaningless \u2014 the following `updateCamera` call is
    /// never the *first* one on this instance (that already happened), so it
    /// mounts everything immediately anyway, per `synchroniseWithResidentChunks`.
    func unmountAll() {
        for nodes in nodesByChunk.values {
            for node in nodes {
                node.removeFromParent()
                if pool.count < Self.maxPoolSize {
                    pool.append(node)
                }
            }
        }
        nodesByChunk.removeAll()
        pendingMountQueue.removeAll()
    }

    /// Adds nodes for resident-but-unmounted chunks and removes nodes for
    /// mounted-but-evicted ones.
    ///
    /// Eviction runs **before** the mount pass so a chunk that streamed out
    /// this call gives its nodes to `pool` in time for the mount pass below
    /// to recycle them for a chunk streaming in this same call \u2014 that
    /// ordering is what makes `pool` stay effectively empty in steady state
    /// (see `pool`'s doc comment) instead of merely bounded by
    /// `maxPoolSize`.
    private func synchroniseWithResidentChunks(cameraWorldPosition: TilePoint, isFirstEverCall: Bool) {
        guard let worldLayer else { return }

        // Snapshot the keys: the loop body mutates `nodesByChunk`.
        for coordinate in Array(nodesByChunk.keys) where streaming.residentChunks[coordinate] == nil {
            for node in nodesByChunk[coordinate] ?? [] {
                node.removeFromParent()
                if pool.count < Self.maxPoolSize {
                    pool.append(node)
                }
            }
            nodesByChunk.removeValue(forKey: coordinate)
        }

        // A chunk queued for the incremental mount that streamed back out of
        // residency before its turn came up must not linger in the queue.
        pendingMountQueue.removeAll { streaming.residentChunks[$0] == nil }

        let newlyUnmounted = streaming.residentChunks.keys.filter {
            nodesByChunk[$0] == nil && !pendingMountQueue.contains($0)
        }
        guard !newlyUnmounted.isEmpty || !pendingMountQueue.isEmpty else { return }

        if isFirstEverCall {
            // Mount only the viewport-covering ring now, so the very next
            // rendered frame already shows a street; queue the remainder for
            // `advanceIncrementalMount()` to bring in over the next few
            // frames rather than blocking this call \u2014 the whole point of
            // `CYBERPUN-17-4-t4`.
            let cameraChunk = ChunkStreamingManager.chunkCoordinate(containing: cameraWorldPosition)
            let quickstartRing = ChunkStreamingManager.chunkCoordinates(
                withinRadius: ChunkStreamingManager.quickstartRadius,
                of: cameraChunk
            )
            let quickstart = newlyUnmounted.filter { quickstartRing.contains($0) }
            let remainder = newlyUnmounted.filter { !quickstartRing.contains($0) }

            for coordinate in quickstart {
                mountChunk(coordinate, into: worldLayer)
            }
            pendingMountQueue.append(contentsOf: remainder)
        } else {
            // Steady state (ordinary panning, or a RUN AGAIN reusing this
            // streamer): mount anything newly resident immediately, and fold
            // in anything still waiting from an earlier deferred first mount
            // \u2014 exactly the full-window-per-call behaviour this type had
            // before `CYBERPUN-17-4-t4`, for every call after the first.
            for coordinate in newlyUnmounted {
                mountChunk(coordinate, into: worldLayer)
            }
            for coordinate in pendingMountQueue where streaming.residentChunks[coordinate] != nil {
                mountChunk(coordinate, into: worldLayer)
            }
            pendingMountQueue.removeAll()
        }
    }

    /// Mounts every tile of `coordinate`'s chunk into `worldLayer`, recording
    /// the mounted nodes under `coordinate` in `nodesByChunk`. Assumes
    /// `coordinate` is currently resident and not already mounted \u2014 every
    /// call site above checks both before calling this.
    private func mountChunk(_ coordinate: ChunkCoordinate, into worldLayer: SKNode) {
        guard let chunk = streaming.residentChunks[coordinate] else { return }
        var mounted: [SKSpriteNode] = []
        mounted.reserveCapacity(Chunk.size * Chunk.size)
        for localX in 0..<Chunk.size {
            for localY in 0..<Chunk.size {
                let tile = chunk.tile(localX: localX, localY: localY)
                let coordinateOfTile = TileCoordinate(tileX: tile.tileX, tileY: tile.tileY)
                let node = dequeueOrMakeNode(for: tile.kind, at: coordinateOfTile)
                worldLayer.addChild(node)
                mounted.append(node)
            }
        }
        nodesByChunk[coordinate] = mounted
    }

    /// Reuses a pooled node (freed by a chunk that just streamed out) if one
    /// is available, reconfiguring it via `GroundTileRenderer.configure` for
    /// `tileKind`/`coordinateOfTile`; otherwise allocates a fresh node via
    /// `GroundTileRenderer.node(for:at:)`. `pool` only ever holds nodes for
    /// chunks that are no longer resident, so a dequeued node can never
    /// collide with one still mounted for a different chunk.
    private func dequeueOrMakeNode(for tileKind: TileKind, at coordinateOfTile: TileCoordinate) -> SKSpriteNode {
        if let recycled = pool.popLast() {
            GroundTileRenderer.configure(recycled, for: tileKind, at: coordinateOfTile)
            return recycled
        }
        let node = GroundTileRenderer.node(for: tileKind, at: coordinateOfTile)
        node.name = Self.nodeName
        return node
    }

    /// Name stamped on every mounted ground node, so the scene's audits and
    /// the tests can identify ground tiles among `worldLayer`'s children
    /// without holding a reference to this mount.
    static let nodeName = "groundTile"
}
