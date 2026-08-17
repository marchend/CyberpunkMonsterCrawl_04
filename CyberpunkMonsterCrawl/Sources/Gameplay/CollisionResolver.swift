import CoreGraphics
import Foundation

/// Resolves a proposed tile-space movement delta against building footprint
/// diamonds, sliding the blocked velocity component along the wall edge
/// rather than zeroing the whole move or letting the player stick to the
/// last legal frame.
///
/// **Scope of this PR (`CYBERPUN-17-7` PR 2).** This is the world-reaction
/// half of the story: given a proposed movement delta (the shape
/// `PlayerMovementController.frameDisplacement` already produces \u2014 a
/// tile-space `CGVector` with `deltaTime` already folded in) and a focus
/// point, decide where the mover actually ends up. It does not compute the
/// proposed delta itself (that is `PlayerMovementController`'s job, PR 1 of
/// this story) and it is not wired into `GameScene`/`PlayerNode.position`
/// yet \u2014 that wiring, together with deleting `PlayerScaffoldingDriver` and
/// the debug camera pan, lands in a later PR of this same story.
///
/// **Flat-base collision only, per `docs/bootstrap.md` \u00a71: "Buildings are
/// flat base-diamond footprints on a tile grid; collision is a tile query,
/// not `SKPhysicsBody`. Visual height must never affect collision."** This
/// type never reads `BuildingCatalog.Entry.heightClass`,
/// `BuildingSprite.declaredPixelSize`, or any rendered node's
/// `calculateAccumulatedFrame()` \u2014 only `BuildingPlacementRecord
/// .footprintTiles`, exactly like `BuildingObstruction` (the discrete,
/// tile-membership sibling this type generalizes to continuous tile
/// space). Two placements sharing an identical footprint therefore resolve
/// identically no matter which of the 12 catalog sprites either one is
/// (`CollisionResolverTests` pins that parity directly, the same way
/// `BuildingCollisionTests` pins it for the discrete query).
///
/// **Why continuous, not discrete.** `BuildingObstruction.isObstructed`
/// answers "is this whole tile blocked", which is the right question for a
/// generation-time reservation but the wrong one for a moving point: a
/// player approaching a building diagonally must be able to glide along its
/// edge instead of being stopped a whole tile away or teleported to the
/// tile boundary. So a footprint's `footprintTiles` \u2014 one or four
/// contiguous unit tiles \u2014 is restated here as a continuous rectangle in
/// tile space: tile `T` owns `[T - 0.5, T + 0.5]` on each axis (the same
/// half-tile-per-side convention `IsometricProjection.tile(containing:)`
/// pins for tile *ownership*; unlike that half-open rounding rule, both of
/// a footprint's edges bound the rectangle symmetrically, and the edge
/// itself reads as *legal* ground -- `FootprintBounds.contains` uses
/// strict inequalities on purpose, because the clamp below lands a blocked
/// axis exactly on that edge and a boundary point must read as legal or
/// the very next call would re-block the position this one just
/// produced), so a 2x2 footprint's own rectangle spans two
/// tiles' worth on each axis. `footprintBounds(for:)` derives that rectangle
/// from `footprintTiles` alone, never from `lotTile`/`farCornerTile` in
/// isolation, so an irregular future footprint shape would still be bounded
/// correctly.
///
/// **The slide, not a stop.** `resolve` moves the X axis first (holding Y at
/// its current value), then the Y axis (holding the just-resolved X): the
/// textbook per-axis AABB resolution that produces sliding for free. A
/// diagonal approach into a footprint's corner is blocked on whichever axis
/// would carry the point inside the rectangle while the other axis keeps
/// moving freely \u2014 so the point can glide along an edge, and a sustained
/// diagonal push converges arbitrarily close to (but never onto) the
/// footprint's near vertex, exactly the property
/// `CollisionResolverTests` sweeps for from all 8 approach directions.
///
/// **The swept segment, not just the endpoint (no tunnelling).** A single
/// per-axis test only inspects the move's *endpoint*, so on its own it
/// would let a large enough delta step straight over a narrow footprint:
/// for a 1x1 footprint at (20, 20) -- bounds `[19.5, 20.5]` -- a mover at
/// `x = 18` with `dx = 3.5` lands at `21.5`, which is outside the
/// rectangle, and nothing blocks. `PlayerMovementController.maxFrameDelta`
/// caps the production per-frame delta well below that (~0.17 tile-units
/// per axis at `maxPointsPerSecond`, and PR 1 wrote the cap down
/// specifically so "the guarantee exists *before* the resolver is written
/// against it"), but this type is `static` API any future caller
/// (knockback, a pulse ability, the raccoon swarm) can hand a bigger delta
/// to, and an unenforced precondition is one refactor away from a
/// tunnelling report. So the dependency is *enforced here* rather than
/// merely documented: `resolve` splits `proposedDelta` into substeps no
/// longer than half the narrowest obstruction's own extent and resolves
/// each in turn, which makes the endpoint test cover the whole swept
/// segment. A delta already inside that budget (every production frame)
/// takes exactly one substep, so this costs nothing on the normal path;
/// `CollisionResolverTests` pins both the oversized-delta case and the
/// one-substep production budget.
///
/// **An illegal starting position ejects forwards, never backwards.**
/// `resolve` does not assume `currentPosition` is outside every
/// obstruction, because two paths can violate that: a chunk streaming a
/// building in under a mover, and a run-start tile chosen before
/// placements are known. Clamping from inside would fire against the near
/// edge *in the direction of travel* and teleport the mover backwards (a
/// full tile, out of a 2x2 footprint). Instead, an obstruction that
/// already contains the starting point is skipped for that step, so a
/// mover that somehow starts inside one is free to walk out in whichever
/// direction it is pushed. Deciding *where* such a mover should be
/// respawned is spawn-safety policy and belongs with the wiring PR that
/// owns run-start placement; this type's contract is only that it never
/// moves anyone backwards against their own input.
enum CollisionResolver {

    /// A building footprint's tile-space extent, restated as a continuous
    /// rectangle: `[minX, maxX] x [minY, maxY]`, both bounds already
    /// widened by half a tile from the raw `TileCoordinate` range so the
    /// rectangle matches the union of the footprint's own tile diamonds
    /// (see this type's doc comment).
    struct FootprintBounds: Equatable {
        let minX: Double
        let maxX: Double
        let minY: Double
        let maxY: Double

        /// Whether `(x, y)` falls **strictly inside** this rectangle. The
        /// boundary itself (a footprint's own edge) is deliberately not
        /// "inside" \u2014 the resolver's clamp lands a blocked axis exactly on
        /// that boundary, and a boundary point must read as legal or the
        /// very next call would re-block a position the previous call just
        /// produced.
        func contains(x: Double, y: Double) -> Bool {
            x > minX && x < maxX && y > minY && y < maxY
        }

        /// The shorter of this rectangle's two side lengths, in tile units
        /// -- `1` for a 1x1 footprint, `2` for a 2x2. This is the distance
        /// a single per-axis step must not exceed if the endpoint test is
        /// to catch a crossing of this rectangle, which is what
        /// `substepCount(for:obstructions:)` sizes its substeps against
        /// (see this type's "The swept segment" note).
        var narrowestExtent: Double {
            min(maxX - minX, maxY - minY)
        }
    }

    /// Derives `record`'s footprint rectangle from `footprintTiles` alone
    /// \u2014 one unit tile for a 1x1 building, four for a 2x2 \u2014 never from the
    /// building's sprite/height class, per this type's flat-base-only
    /// contract.
    static func footprintBounds(for record: BuildingPlacementRecord) -> FootprintBounds {
        let tiles = record.footprintTiles
        let tileXs = tiles.map(\.tileX)
        let tileYs = tiles.map(\.tileY)

        // `BuildingPlacementRecord` always covers at least its own
        // `lotTile` (`BuildingPlacement.generate` never emits an empty
        // `footprintTiles`), so these `min()`/`max()` calls only need a
        // fallback to keep the compiler happy about the optional, not to
        // handle a real empty-footprint case.
        let minTileX = tileXs.min() ?? record.lotTile.tileX
        let maxTileX = tileXs.max() ?? record.lotTile.tileX
        let minTileY = tileYs.min() ?? record.lotTile.tileY
        let maxTileY = tileYs.max() ?? record.lotTile.tileY

        return FootprintBounds(
            minX: Double(minTileX) - 0.5,
            maxX: Double(maxTileX) + 0.5,
            minY: Double(minTileY) - 0.5,
            maxY: Double(maxTileY) + 0.5
        )
    }

    /// Resolves `proposedDelta` (tile-space, `deltaTime` already folded in \u2014
    /// the shape `PlayerMovementController.frameDisplacement` produces)
    /// against `obstructions`, returning the tile-space position the mover
    /// actually ends up at this frame.
    ///
    /// Per-axis resolution: X moves first (Y held at `currentPosition.y`),
    /// then Y moves using the just-resolved X. This is what turns a stop
    /// into a slide \u2014 a diagonal move blocked only because the *combined*
    /// destination lands inside a footprint can still complete whichever
    /// single axis doesn't, on its own, cross the footprint boundary.
    ///
    /// A delta larger than the narrowest obstruction is split into
    /// substeps first (see this type's "The swept segment" note), so the
    /// per-axis endpoint test covers the whole swept segment rather than
    /// just its far end. An in-budget delta -- every frame the production
    /// path can produce, given `PlayerMovementController.maxFrameDelta` --
    /// takes exactly one substep and is therefore bit-for-bit what the
    /// un-substepped version returned.
    static func resolve(
        currentPosition: TilePoint,
        proposedDelta: CGVector,
        obstructions: [FootprintBounds]
    ) -> TilePoint {
        let substeps = substepCount(for: proposedDelta, obstructions: obstructions)
        guard substeps > 1 else {
            return resolvedStep(
                currentPosition: currentPosition,
                proposedDelta: proposedDelta,
                obstructions: obstructions
            )
        }

        let substep = CGVector(
            dx: proposedDelta.dx / CGFloat(substeps),
            dy: proposedDelta.dy / CGFloat(substeps)
        )

        var position = currentPosition
        for _ in 0..<substeps {
            position = resolvedStep(
                currentPosition: position,
                proposedDelta: substep,
                obstructions: obstructions
            )
        }
        return position
    }

    /// Upper bound on the substeps a single `resolve` call will take, so a
    /// pathological delta (or a degenerate zero-extent obstruction) can
    /// never turn one frame into an unbounded loop.
    ///
    /// At the smallest real footprint extent (`1` tile, so a half-extent
    /// budget of `0.5`) this covers a single-call delta of 256 tile-units
    /// per axis -- more than three orders of magnitude beyond the ~0.17
    /// `PlayerMovementController.maxFrameDelta` actually permits. Past the
    /// cap the substeps grow longer than the budget and tunnelling becomes
    /// possible again; that is a deliberate "bounded work per frame beats
    /// an unbounded loop" trade for an input no caller in this codebase
    /// can produce.
    static let maxSubstepsPerResolve = 512

    /// How many substeps `resolve` needs to split `proposedDelta` into so
    /// that no single step's per-axis travel exceeds half the narrowest
    /// obstruction's extent -- `1` whenever the delta is already inside
    /// that budget, which is every production frame.
    ///
    /// Exposed (rather than private) so `CollisionResolverTests` can pin
    /// the production per-frame delta at exactly one substep instead of
    /// asserting it in prose.
    static func substepCount(for proposedDelta: CGVector, obstructions: [FootprintBounds]) -> Int {
        let longestAxisTravel = max(abs(Double(proposedDelta.dx)), abs(Double(proposedDelta.dy)))
        guard longestAxisTravel > 0, !obstructions.isEmpty else { return 1 }

        // Half the narrowest extent, not the whole extent: a step at most
        // that long cannot begin outside a rectangle and end outside it on
        // the far side, and the extra factor of two also keeps a diagonal
        // corner approach sliding instead of cutting the corner.
        let safeStep = (obstructions.map(\.narrowestExtent).min() ?? 0) / 2
        guard safeStep > 0, longestAxisTravel > safeStep else { return 1 }

        let needed = Int((longestAxisTravel / safeStep).rounded(.up))
        return min(max(1, needed), maxSubstepsPerResolve)
    }

    /// One per-axis resolution pass: X moves first (Y held at
    /// `currentPosition.y`), then Y moves using the just-resolved X. This
    /// is the primitive `resolve` applies once per substep.
    private static func resolvedStep(
        currentPosition: TilePoint,
        proposedDelta: CGVector,
        obstructions: [FootprintBounds]
    ) -> TilePoint {
        var x = currentPosition.x
        var y = currentPosition.y

        let candidateX = x + Double(proposedDelta.dx)
        x = resolvedCoordinate(from: x, candidate: candidateX, other: y, obstructions: obstructions, axis: .x)

        let candidateY = y + Double(proposedDelta.dy)
        y = resolvedCoordinate(from: y, candidate: candidateY, other: x, obstructions: obstructions, axis: .y)

        return TilePoint(x: x, y: y)
    }

    /// Convenience overload for the production call shape: a list of
    /// `BuildingPlacementRecord`s (exactly what `Chunk.buildingPlacements`
    /// / `ChunkStreamingManager.residentChunks` hand back) rather than
    /// pre-derived `FootprintBounds`.
    static func resolve(
        currentPosition: TilePoint,
        proposedDelta: CGVector,
        obstructedBy records: [BuildingPlacementRecord]
    ) -> TilePoint {
        resolve(
            currentPosition: currentPosition,
            proposedDelta: proposedDelta,
            obstructions: records.map(footprintBounds(for:))
        )
    }

    private enum Axis {
        case x
        case y
    }

    /// Resolves a single axis's coordinate: `candidate` unchanged if it
    /// does not land inside any obstruction (tested against `other`, the
    /// *other* axis's coordinate \u2014 already-resolved for the Y pass, still
    /// the starting value for the X pass); otherwise clamped to the nearest
    /// blocking rectangle's boundary in the direction of travel.
    ///
    /// While `current` is legal (outside every
    /// obstruction \u2014 true by construction as long as every call in a
    /// sequence starts from the previous call's resolved position), a
    /// `candidate` found inside some obstruction can only be approached
    /// from the one side that rectangle's near edge faces, so clamping to
    /// that edge (rather than choosing a direction) is unambiguous.
    ///
    /// When that does not hold -- a building streamed in on top of the
    /// mover, or a run-start tile chosen before placements were known --
    /// clamping to the near edge in the direction of travel would teleport
    /// the mover *backwards*, a full tile out of a 2x2 footprint, against
    /// its own input. So an obstruction that already contains `current` is
    /// skipped instead of clamped against: the mover keeps whatever motion
    /// it was given and can walk out (see this type's "An illegal starting
    /// position" note).
    private static func resolvedCoordinate(
        from current: Double,
        candidate: Double,
        other: Double,
        obstructions: [FootprintBounds],
        axis: Axis
    ) -> Double {
        guard candidate != current else { return current }
        let movingPositive = candidate > current
        var resolved = candidate

        for obstruction in obstructions {
            let blocked: Bool
            let startedInside: Bool
            switch axis {
            case .x:
                blocked = obstruction.contains(x: candidate, y: other)
                startedInside = obstruction.contains(x: current, y: other)
            case .y:
                blocked = obstruction.contains(x: other, y: candidate)
                startedInside = obstruction.contains(x: other, y: current)
            }
            // Skipping an obstruction the mover is already inside is what
            // keeps an illegal starting position from resolving backwards.
            guard blocked, !startedInside else { continue }

            switch axis {
            case .x:
                resolved = movingPositive ? min(resolved, obstruction.minX) : max(resolved, obstruction.maxX)
            case .y:
                resolved = movingPositive ? min(resolved, obstruction.minY) : max(resolved, obstruction.maxY)
            }
        }

        return resolved
    }
}
