import CoreGraphics
import SpriteKit

/// Mounts the ground plane into `GameScene.worldLayer`: the production
/// consumer of `GroundTileRenderer`, driven by `ChunkStreamingManager`'s
/// resident chunk window.
///
/// `GroundTileRenderer.node(for:at:)` is a factory, and a factory with no
/// caller renders nothing in a real build — the story's headline AC ("render
/// every generated ground cell", product gate 4: *the city has to read as a
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
/// bounded however far the camera roams — the scene-graph counterpart of AC8,
/// and pinned by `GroundPlaneStreamerTests`.
///
/// Nodes are parented **directly** under `worldLayer` (no intermediate
/// container) because `GroundTileRenderer` sets a `worldLayer`-*relative*
/// `zPosition`: SpriteKit accumulates `zPosition` down the tree, so an
/// intermediate node with any non-zero `zPosition` would silently shift every
/// ground tile out of the depth scheme `DepthModel` computed.
final class GroundPlaneStreamer {

    /// Streams the chunk window this mount follows. Owned here (rather than
    /// injected from the scene) so the ground plane has exactly one source of
    /// truth for "which tiles exist right now".
    let streaming: ChunkStreamingManager

    /// The layer ground nodes are parented into. Weak: the scene owns the
    /// layer, and this mount must never keep a dead scene's graph alive.
    private weak var worldLayer: SKNode?

    /// Mounted nodes, grouped by the chunk whose residency they follow, so an
    /// eviction is an O(tiles-per-chunk) removal rather than a full rescan.
    private var nodesByChunk: [ChunkCoordinate: [SKSpriteNode]] = [:]

    /// Nodes given up by a chunk that just streamed out of the resident
    /// window, held here for reuse rather than deallocated.
    ///
    /// `CYBERPUN-17-4-t3`: without this, every chunk that streams in would
    /// allocate a fresh `SKSpriteNode` per tile, so panning far enough would
    /// have allocated and discarded many multiples of the resident window's
    /// worth of nodes even though only `mountedNodeCount` are ever on screen
    /// at once. Because eviction always runs (in `synchroniseWithResidentChunks`)
    /// *before* the mount pass in the same `updateCamera` call, and the
    /// resident window is a fixed size, the number of nodes freed by
    /// eviction on any call is exactly the number the mount pass needs that
    /// same call \u2014 so after the very first `updateCamera` fills the window
    /// from empty, no further `SKSpriteNode` is ever allocated; the pool
    /// always has enough to recycle. Capped defensively at `maxPoolSize`
    /// anyway, so a call pattern this reasoning doesn't cover still can't
    /// grow memory without bound.
    private var pool: [SKSpriteNode] = []

    /// Defensive cap on `pool`'s size \u2014 see `pool`'s doc comment for why it
    /// should never need to hold more than one resident window's worth.
    private static var maxPoolSize: Int { ChunkStreamingManager.residentWindowSize * Chunk.size * Chunk.size }

    init(seed: WorldSeed, worldLayer: SKNode) {
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
    /// Idempotent for a camera that hasn't left its chunk — the streaming
    /// manager's resident set is unchanged, so no node is rebuilt.
    func updateCamera(worldPosition: TilePoint) {
        streaming.updateCamera(worldPosition: worldPosition)
        synchroniseWithResidentChunks()
    }

    /// Removes every mounted ground node from the scene graph. Called when a
    /// run ends (or a new one starts), so a fresh world never inherits the
    /// previous one's tiles.
    func unmountAll() {
        for nodes in nodesByChunk.values {
            for node in nodes {
                node.removeFromParent()
            }
        }
        nodesByChunk.removeAll()
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
    private func synchroniseWithResidentChunks() {
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

        for (coordinate, chunk) in streaming.residentChunks where nodesByChunk[coordinate] == nil {
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
