import CoreGraphics

/// Building-footprint avoidance for the raccoon swarm: a thin, AI-specific
/// extension of `CollisionResolver`'s already-general resolve-X-then-Y AABB
/// slide (`CYBERPUN-17-8` PR 2).
///
/// **Why this does not reimplement collision geometry.**
/// `CollisionResolver.resolve` already generalizes over any footprint size
/// -- it resolves against `FootprintBounds` derived from a building's
/// `footprintTiles`, one tile for a 1x1 building, four for a 2x2, with no
/// footprint-size-specific branch anywhere in its own logic (see that
/// type's own doc comment: "Two placements sharing an identical footprint
/// therefore resolve identically no matter which of the 12 catalog sprites
/// either one is"). So "extending [it] to accept both footprint sizes"
/// needs no new geometry at all; this type calls it directly with
/// whichever footprint list a caller hands over.
///
/// **What this type actually adds: a caller that never gets to
/// self-correct.** A human player pushing a thumbstick straight at a wall
/// naturally nudges the stick a few degrees the moment they notice they've
/// stopped moving. `CollisionResolver.resolve` returns the position
/// *unchanged* for exactly one shape of input: a proposed delta that lands
/// the mover back exactly where it started, because the mover is already
/// flush against a flat wall on the blocked axis and the other axis
/// carries no delta of its own to slide along (a dead-on, axis-aligned
/// push -- see `CollisionResolverTests`' own diagonal-approach note: a
/// *diagonal* push into a footprint's corner always keeps sliding, because
/// the untouched axis still has a nonzero component to move along; it is
/// only the single-axis, straight-into-a-flat-wall case that can return
/// completely unchanged). An unattended raccoon recomputing the identical
/// "seek the player" vector every frame would grind against that wall
/// forever whenever the player happens to be directly on the other side of
/// it -- a human never would, because they would drift the stick the
/// moment they noticed they'd stopped.
///
/// `resolve(currentPosition:proposedDelta:obstructions:)` below is the fix:
/// when (and only when) `CollisionResolver.resolve` makes zero progress on
/// a nonzero delta, it probes the two directions perpendicular to the
/// proposed delta -- exactly tangential to whichever wall is blocking it --
/// through the *same* resolver, and takes whichever probe actually moves
/// the raccoon. This never risks entering a footprint: every candidate,
/// direct or probed, is still produced by `CollisionResolver.resolve`
/// itself, so it inherits that type's own "never returns a point strictly
/// inside an obstruction" guarantee for free.
enum BuildingAvoidance {

    /// Resolves `proposedDelta` against `obstructions`, adding the
    /// perpendicular-probe fallback described in this type's doc comment
    /// whenever `CollisionResolver.resolve` alone makes no progress.
    static func resolve(
        currentPosition: TilePoint,
        proposedDelta: CGVector,
        obstructions: [CollisionResolver.FootprintBounds]
    ) -> TilePoint {
        let direct = CollisionResolver.resolve(
            currentPosition: currentPosition,
            proposedDelta: proposedDelta,
            obstructions: obstructions
        )

        // Nothing to correct for: either the move is already unobstructed
        // (`direct != currentPosition`), or the proposed delta was itself
        // zero (in which case `direct == currentPosition` is the only
        // legal answer and a perpendicular probe would just be `.zero`
        // resolved against nothing).
        guard proposedDelta != .zero, direct == currentPosition else { return direct }

        // Blocked outright: probe the two directions tangential to the
        // proposed delta, at the same magnitude, through the same
        // resolver -- exactly along whichever wall stopped the direct
        // move.
        let tangentA = CGVector(dx: -proposedDelta.dy, dy: proposedDelta.dx)
        let tangentB = CGVector(dx: proposedDelta.dy, dy: -proposedDelta.dx)

        for candidate in [tangentA, tangentB] {
            let probed = CollisionResolver.resolve(
                currentPosition: currentPosition,
                proposedDelta: candidate,
                obstructions: obstructions
            )
            if probed != currentPosition {
                return probed
            }
        }

        // Boxed in on every axis tried (would require an obstruction
        // arrangement no real footprint set produces, since buildings
        // never overlap): hold position rather than guessing further.
        return currentPosition
    }

    /// Convenience overload for the production call shape: a list of
    /// `BuildingPlacementRecord`s, exactly like
    /// `CollisionResolver.resolve(currentPosition:proposedDelta:obstructedBy:)`.
    static func resolve(
        currentPosition: TilePoint,
        proposedDelta: CGVector,
        obstructedBy records: [BuildingPlacementRecord]
    ) -> TilePoint {
        resolve(
            currentPosition: currentPosition,
            proposedDelta: proposedDelta,
            obstructions: records.map(CollisionResolver.footprintBounds(for:))
        )
    }
}
