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
    /// chunk that must stay resident. Radius `2` keeps a 5x5 chunk window
    /// (40x40 tiles) loaded \u2014 comfortably larger than a single screen at
    /// the 96x48 tile diamond size, so the player never sees a chunk pop in
    /// at the edge of the viewport, while still bounding memory/generation
    /// work as the camera roams an unbounded world.
    ///
    /// An explicit, testable constant per the implementation plan: AC8's
    /// test asserts the resident count never exceeds `residentWindowSize`
    /// at any step of a long sweep.
    static let residentRadius = 2

    /// The number of chunks resident at any time once the camera is far
    /// enough from the world's origin that the window isn't clipped by
    /// world edges (there are none here \u2014 the world is unbounded) \u2014 i.e.
    /// the fixed upper bound AC8 requires.
    static var residentWindowSize: Int {
        let side = residentRadius * 2 + 1
        return side * side
    }

    private let seed: WorldSeed

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
        let cameraTileX = Int(worldPosition.x.rounded(.down))
        let cameraTileY = Int(worldPosition.y.rounded(.down))
        let cameraChunk = ChunkCoordinate.containing(tileX: cameraTileX, tileY: cameraTileY)

        let desired = Self.chunkCoordinatesWithinRadius(of: cameraChunk)

        var newlyLoaded: Set<ChunkCoordinate> = []
        for coordinate in desired where residentChunks[coordinate] == nil {
            residentChunks[coordinate] = ChunkGenerator.generate(chunkCoordinate: coordinate, seed: seed)
            newlyLoaded.insert(coordinate)
        }

        let coordinatesToEvict = residentChunks.keys.filter { !desired.contains($0) }
        for coordinate in coordinatesToEvict {
            residentChunks.removeValue(forKey: coordinate)
        }

        return newlyLoaded
    }

    /// Every chunk coordinate within `residentRadius` (Chebyshev distance)
    /// of `center`, inclusive \u2014 a `(2*radius + 1)`-side square of chunks
    /// centred on the camera's own chunk.
    private static func chunkCoordinatesWithinRadius(of center: ChunkCoordinate) -> Set<ChunkCoordinate> {
        var result: Set<ChunkCoordinate> = []
        for dx in -residentRadius...residentRadius {
            for dy in -residentRadius...residentRadius {
                result.insert(ChunkCoordinate(x: center.x + dx, y: center.y + dy))
            }
        }
        return result
    }
}
