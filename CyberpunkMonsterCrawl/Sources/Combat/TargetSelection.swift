import CoreGraphics
import Foundation

/// Tile-space nearest-living-raccoon target selection for the auto-fire
/// weapon system (`CYBERPUN-17-9` PR 1) \u2014 the "at whom to fire" half of
/// the decision layer `WeaponFiringController` (this same PR) drives.
///
/// **Deliberately decoupled from `RaccoonSpawnDirector.ActiveRaccoon`**,
/// which is `private` to that type and, per its own scope note, still
/// belongs to the raccoon-swarm story. This file's job is the pure
/// selection rule alone, so it takes any list of raccoon-with-position
/// pairs (`Candidate`) rather than reaching into that director's
/// internals. The story's later end-to-end wiring PR is expected to build
/// a `[TargetSelection.Candidate]` from the spawn director's live swarm
/// each frame (see `WeaponFiringController`'s type doc for why that caller
/// is deferred rather than landed here).
enum TargetSelection {

    /// One live (or recently-live) raccoon paired with its current
    /// tile-space position \u2014 the minimal shape this file's selection rule
    /// needs, independent of how a caller tracks its own swarm.
    ///
    /// `RaccoonNode` carries no tile-space position of its own (a raccoon's
    /// position is tracked externally by whichever system steers it, the
    /// same shape `RaccoonSeekBehavior`'s functions already take), so a
    /// candidate must pair the two explicitly.
    struct Candidate {
        let raccoon: RaccoonNode
        let position: TilePoint

        init(raccoon: RaccoonNode, position: TilePoint) {
            self.raccoon = raccoon
            self.position = position
        }
    }

    /// The nearest **living** raccoon among `raccoons` within `maxRange`
    /// tiles of `origin`, or `nil` if none qualifies.
    ///
    /// Returns the winning `Candidate` \u2014 node *and* tile-space position \u2014
    /// rather than the bare `RaccoonNode`, because `RaccoonNode` carries no
    /// tile-space position of its own (see `Candidate`). A consumer that
    /// needs the shot vector or the muzzle placement (bullets are authored
    /// pointing screen-right and must be drawn rotated to the shot vector)
    /// would otherwise have to re-scan `raccoons` by `===` to recover the
    /// position this function had just computed \u2014 an O(n) re-lookup that
    /// also picks the wrong entry if the same node ever appears twice.
    ///
    /// A dead raccoon (`RaccoonNode.isDead`) is filtered out **before**
    /// any distance comparison \u2014 the story's re-target-on-death
    /// requirement \u2014 so a caller can never select an already-dead target,
    /// even as its single remaining candidate.
    ///
    /// Ties (two raccoons at exactly the same distance) resolve to
    /// whichever appears first in `raccoons`: a plain `<` comparison never
    /// replaces the current best on an equal distance, matching `Array`'s
    /// stable iteration order. There is no story requirement for any
    /// other tie-break, and a stable rule is what makes this
    /// deterministically testable.
    static func nearestLivingTarget(
        from origin: TilePoint,
        raccoons: [Candidate],
        maxRange: Double
    ) -> Candidate? {
        var best: (candidate: Candidate, distance: Double)?

        for candidate in raccoons {
            guard !candidate.raccoon.isDead else { continue }

            let distance = tileDistance(origin, candidate.position)
            guard distance <= maxRange else { continue }

            if best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }

        return best?.candidate
    }

    /// Plain tile-space Euclidean distance, kept in `Double` throughout
    /// and only ever compared against another `Double` (`maxRange`) \u2014
    /// never cast to `CGFloat` here, since nothing in this file constructs
    /// a point/vector. The same tile-space (not screen-space) shape
    /// `RaccoonSeekBehavior`'s own private `tileDistance` helper uses for
    /// its garbage-can diversion/arrival ranges, matching the story's own
    /// wording: "tile-space nearest-living-raccoon targeting".
    private static func tileDistance(_ a: TilePoint, _ b: TilePoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
