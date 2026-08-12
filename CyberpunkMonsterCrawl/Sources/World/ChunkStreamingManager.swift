import Foundation

/// Tracks the set of resident chunks around a moving camera, streaming
/// chunks in as the camera approaches them and evicting chunks once they
/// fall outside a fixed window.
///
/// Deliberately free of SpriteKit \u2014 the camera is fed in as a plain
/// `TilePoint` (the same tile-space value type `IsometricProjection`
/// already uses for a camera-shaped position), so this type is unit
/// testable with a synthetic sweep and no scene, no `SKCameraNode`, no
/// view hierarchy at all (AC8's test drives exactly that).
final class ChunkStreamingManager {
    /// Chebyshev-distance radius, in chunks, around the camera's current
    /// chunk that must stay resident.
    ///
    /// **Sized from the worst case, not the best.** The window is
    /// `(2 * radius + 1)` chunks on a side, but the camera sits *somewhere
    /// inside* its own chunk rather than at its centre, so the margin
    /// guaranteed in every tile-axis direction is only
    /// `residentRadius * Chunk.size` tiles — the camera's own chunk
    /// contributes nothing, because the camera may be standing on its very
    /// edge. The "40x40 tiles" this comment used to quote at radius 2 was the
    /// best case; the guaranteed margin was 16 tiles, which projects to a
    /// ±1536 x ±768pt diamond, and an iPad-sized landscape viewport
    /// (1366x1024pt) does *not* fit inside it: `683/1536 + 512/768 = 1.11`.
    /// Since `docs/bootstrap.md` commits to portrait *and* landscape iOS,
    /// the player really could have seen a chunk pop in at the edge.
    ///
    /// Radius `3` gives a guaranteed 24-tile margin (a ±2304 x ±1152pt
    /// diamond), which covers `referenceViewportPoints` in both orientations
    /// with room to spare (`683/2304 + 512/1152 = 0.74`). The cost is a
    /// larger fixed window (49 resident chunks instead of 25), which AC8 is
    /// indifferent to: it requires the resident count not grow with how far
    /// the camera roams, not that it be small. `coversViewport(widthPoints:
    /// heightPoints:)` below is exactly this arithmetic, and
    /// `ChunkStreamingManagerTests` asserts it for the reference viewport, so
    /// the coverage claim is now checked rather than asserted in prose.
    ///
    /// An explicit, testable constant per the implementation plan: AC8's
    /// test asserts the resident count never exceeds `residentWindowSize`
    /// at any step of a long sweep.
    static let residentRadius = 3

    /// The largest viewport, in points, the resident window is sized to
    /// cover: an iPad-sized landscape screen. Both orientations of it are
    /// checked in the tests, because `docs/bootstrap.md` commits to portrait
    /// and landscape iOS.
    static let referenceViewportPoints = (width: 1_366.0, height: 1_024.0)

    /// The margin, in tiles, guaranteed between the camera and the edge of
    /// the resident window along each tile axis, for *any* camera position
    /// within its own chunk. Only the `residentRadius` rings beyond the
    /// camera's own chunk count, for the reason spelled out on
    /// `residentRadius`.
    static var guaranteedMarginTiles: Int { residentRadius * Chunk.size }

    /// Whether a `widthPoints` x `heightPoints` viewport centred on the
    /// camera is fully covered by resident chunks in the worst case.
    ///
    /// `guaranteedMarginTiles` (`M`) on both tile axes maps, through
    /// `IsometricProjection.tileToScreen`, to a screen-space diamond whose
    /// corners are at `(±2M * tileHalfWidth, 0)` and
    /// `(0, ±2M * tileHalfHeight)` — both tile axes contribute to each screen
    /// axis (`screenX = (dx - dy) * 48`, `screenY = (dx + dy) * 24`). A
    /// rectangle centred in that diamond fits precisely while
    /// `halfWidth / diamondHalfWidth + halfHeight / diamondHalfHeight <= 1`.
    static func coversViewport(widthPoints: Double, heightPoints: Double) -> Bool {
        let margin = Double(guaranteedMarginTiles)
        let diamondHalfWidth = 2 * margin * IsometricProjection.tileHalfWidth
        let diamondHalfHeight = 2 * margin * IsometricProjection.tileHalfHeight
        guard diamondHalfWidth > 0, diamondHalfHeight > 0 else { return false }
        return (widthPoints / 2) / diamondHalfWidth + (heightPoints / 2) / diamondHalfHeight <= 1
    }

    /// The number of chunks resident at any time once the camera is far
    /// enough from the world's origin that the window isn't clipped by
    /// world edges (there are none here \u2014 the world is unbounded) \u2014 i.e.
    /// the fixed upper bound AC8 requires.
    static var residentWindowSize: Int {
        let side = residentRadius * 2 + 1
        return side * side
    }

    /// Chebyshev-distance radius, in chunks, around the camera's chunk that
    /// must be mounted **synchronously** on the very first `.gameplay`
    /// entry \u2014 `CYBERPUN-17-4-t4`'s fix for the main-thread stall a runtime
    /// probe caught: the old code built/mounted the entire `residentRadius`
    /// window (49 chunks, up to 3,136 `SKSpriteNode`s) inside the same call
    /// stack as the PLAY tap. `GroundPlaneStreamer` mounts only this smaller
    /// ring immediately and streams the rest in over the next few
    /// `GameScene.update(_:)` ticks, so the first rendered frame already
    /// shows a street without blocking the tap handler on the full window.
    ///
    /// Deliberately smaller than `residentRadius` (which is sized for the
    /// worst-case iPad-landscape *reference* viewport, `referenceViewportPoints`):
    /// a radius-1 ring (9 chunks, a guaranteed 8-tile margin) comfortably
    /// covers a typical phone viewport for the one synchronous frame this
    /// exists to unblock, trading a slightly tighter first-frame margin for
    /// never doing the full 49-chunk mount inside a touch handler.
    static let quickstartRadius = 1

    /// The chunk coordinate that owns `worldPosition` (tile space) \u2014 the
    /// camera-chunk computation `updateCamera` needs, exposed so
    /// `GroundPlaneStreamer` can derive the same "which chunk is the camera
    /// on" answer for its own quickstart-ring mounting without re-deriving
    /// (or disagreeing with) the rounding rule.
    static func chunkCoordinate(containing worldPosition: TilePoint) -> ChunkCoordinate {
        let tile = IsometricProjection.tile(containing: worldPosition)
        return ChunkCoordinate.containing(tileX: tile.tileX, tileY: tile.tileY)
    }

    /// Every chunk coordinate within `radius` (Chebyshev distance) of
    /// `center`, inclusive \u2014 a `(2*radius + 1)`-side square of chunks
    /// centred on `center`. Exposed (rather than kept private to
    /// `residentRadius`'s own use) so `GroundPlaneStreamer` can compute the
    /// smaller `quickstartRadius` ring with the identical shape rule.
    static func chunkCoordinates(withinRadius radius: Int, of center: ChunkCoordinate) -> Set<ChunkCoordinate> {
        var result: Set<ChunkCoordinate> = []
        for dx in -radius...radius {
            for dy in -radius...radius {
                result.insert(ChunkCoordinate(x: center.x + dx, y: center.y + dy))
            }
        }
        return result
    }

    private let seed: WorldSeed

    /// Building-footprint reservation state for the whole world.
    ///
    /// Owned here, *above* `residentChunks`, precisely because this cache is
    /// lossy by design: eviction drops a `Chunk` instance and revisiting
    /// regenerates it. Tile content is safe across that cycle (it is a pure
    /// function of `(tileX, tileY, seed)`), but reservations are decisions
    /// that cannot be re-derived, so storing them on the evicted instance
    /// silently discarded them every time the camera moved two chunks away.
    /// Holding one store for the world and handing it to every generated
    /// chunk makes reservation survival independent of the eviction policy
    /// (pinned by `ChunkStreamingManagerTests`'s reservation-survival test).
    let reservations = LotReservationStore()

    /// Chunks currently loaded, keyed by chunk coordinate. `private(set)`
    /// so callers (and tests) can inspect residency without being able to
    /// mutate it out from under `updateCamera`.
    private(set) var residentChunks: [ChunkCoordinate: Chunk] = [:]

    init(seed: WorldSeed) {
        self.seed = seed
    }

    /// Recomputes chunk residency for a camera now centred at
    /// `worldPosition` (tile space): generates any chunk newly within
    /// `residentRadius` of the camera's chunk and evicts any chunk now
    /// outside it.
    ///
    /// Returns the chunk coordinates that became resident this call (empty
    /// if the camera didn't leave its previous chunk), purely as a
    /// convenience for callers that want to react to newly-streamed-in
    /// chunks; the manager's own state is the source of truth.
    @discardableResult
    func updateCamera(worldPosition: TilePoint) -> Set<ChunkCoordinate> {
        // "Which tile is the camera on?" is `IsometricProjection`'s decision,
        // not this type's: `tile(containing:)` pins `floor(coord + 0.5)` (whole
        // tile-space values are tile *centres*), and it exists so the rounding
        // rule is not re-invented per call site. A local `rounded(.down)` here
        // answered differently for any camera in the upper half of a tile
        // (tile-space x = 7.6 -> tile 7 -> chunk 0, where the pinned rule says
        // tile 8 -> chunk 1), which slid the whole resident window half a tile
        // off from the camera.
        let cameraChunk = Self.chunkCoordinate(containing: worldPosition)

        let desired = Self.chunkCoordinates(withinRadius: Self.residentRadius, of: cameraChunk)

        var newlyLoaded: Set<ChunkCoordinate> = []
        for coordinate in desired where residentChunks[coordinate] == nil {
            residentChunks[coordinate] = ChunkGenerator.generate(
                chunkCoordinate: coordinate,
                seed: seed,
                reservations: reservations
            )
            newlyLoaded.insert(coordinate)
        }

        let coordinatesToEvict = residentChunks.keys.filter { !desired.contains($0) }
        for coordinate in coordinatesToEvict {
            residentChunks.removeValue(forKey: coordinate)
        }

        return newlyLoaded
    }
}
