import Foundation

/// A single spawned ground pickup: pure data, no SpriteKit/rendering
/// dependency. `PickupNode` (this same PR) is the visual counterpart a
/// later scene-wiring PR mounts one of per active `Pickup` `PickupManager`
/// reports -- the same "logic first, rendering is a later PR" split
/// `ChunkStreamingManager`/`GroundPlaneStreamer` and
/// `RaccoonSpawnDirector`/`RaccoonNode` already follow in this codebase.
struct Pickup: Identifiable, Equatable {
    let id: UUID

    /// Which kind this is -- fixed for this pickup's whole lifetime.
    let kind: PickupKind

    /// This pickup's fixed world position, in tile space. A pickup never
    /// moves once spawned.
    let position: TilePoint

    /// Seconds elapsed since this pickup spawned, advanced **only** by the
    /// real `deltaTime` `PickupManager.update(deltaTime:visibleRect:)`
    /// receives -- never by anything derived from a camera/viewport change
    /// between calls. Expires (removed by `PickupManager`) once this reaches
    /// `kind.tuning.lifetime`.
    var age: TimeInterval

    /// Set the instant a collection query
    /// (`PickupManager.attemptCollectMedKit`/`attemptCollectGarbageCan`)
    /// consumes this pickup. A consumed pickup is pruned on the very next
    /// `PickupManager.update` call, so no consumer outside `PickupManager`
    /// should observe one with `isConsumed == true` still present in
    /// `activePickups`.
    var isConsumed: Bool

    init(
        id: UUID = UUID(),
        kind: PickupKind,
        position: TilePoint,
        age: TimeInterval = 0,
        isConsumed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.age = age
        self.isConsumed = isConsumed
    }
}
