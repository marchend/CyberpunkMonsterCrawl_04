/// The per-tile classification the city-lattice generator assigns to every
/// tile. Rendering (ground plane, buildings) and collision both key off
/// this rather than re-deriving lattice geometry themselves.
enum TileKind: Equatable {
    /// The street corridor's driving lane \u2014 the centre of a 3-tile-wide
    /// street band. Fully walkable; part of the navmesh.
    case asphalt
    /// The painted stop line inside a lattice crossing (a 3x3 intersection
    /// area): the four tiles at the *mouths* of the junction, where one
    /// axis sits on the driving lane and the other on a band edge. The
    /// crossing's centre is `.asphalt` and its four corners stay
    /// `.kerbSidewalk` (the sidewalk band continues through the junction),
    /// so this case marks only where a stop line is actually painted
    /// across a lane. Still street, still walkable, still part of the
    /// navmesh \u2014 this is a paint/marking distinction for rendering, not a
    /// collision distinction.
    case junctionStopLine
    /// The sidewalk bordering a street band on the side nearest a block,
    /// including the four corner tiles of a lattice crossing where two
    /// sidewalk bands meet, so the ring around every 3x3 block is
    /// unbroken.
    /// Walkable \u2014 the player and the raccoon swarm cross it exactly like
    /// asphalt; it exists as a separate case purely so the ground-plane
    /// renderer can draw a kerb/sidewalk texture instead of asphalt there.
    case kerbSidewalk
    /// A block interior left empty by the seed's ~1-in-4 decision: bare,
    /// permanently walkable ground.
    ///
    /// A `.lot` tile never turns solid and never hosts a building. The brief
    /// leaves these blocks empty on purpose, so building placement
    /// (`CYBERPUN-17-5`) reserves footprints on `.buildingFootprint` tiles
    /// instead — see `Chunk.placementSurface`, which pins that polarity.
    /// (An earlier version of this doc said a reserved lot's tiles "become
    /// `.buildingFootprint`"; nothing performs that transition, and it is
    /// not needed now that the placement surface is the already-solid kind.)
    case lot
    /// A block interior tile consumed by a building: the ~3-in-4 blocks the
    /// lattice fills, and the surface building placement reserves against
    /// (`Chunk.placementSurface`). Solid collision — not walkable —
    /// regardless of the building's drawn height, per the brief: "a building
    /// blocks movement by its footprint regardless of drawn height."
    ///
    /// Because this kind is already impassable straight out of `classify`, a
    /// reserved-and-built footprint is solid by construction: collision
    /// consumers read `isWalkable` and never need to consult
    /// `Chunk.reservedTiles`.
    case buildingFootprint

    /// Whether the player / raccoon swarm can occupy this tile.
    ///
    /// Per the design brief: "asphalt **and** sidewalk both read as
    /// walkable; building footprints do not." Decision recorded here,
    /// confirmed against the brief during implementation:
    /// - `.asphalt`, `.kerbSidewalk` \u2014 walkable (explicitly named in the
    ///   brief).
    /// - `.junctionStopLine` \u2014 walkable. It is a rendering/paint variant
    ///   of street inside a lattice crossing, not a distinct surface; the
    ///   brief never singles it out as impassable, and treating it as
    ///   impassable would put a hole in the middle of every intersection,
    ///   which contradicts "every intersection tile is street" being the
    ///   swarm's guaranteed path.
    /// - `.lot` — walkable, permanently. The brief: "Buildings fill the 3x3
    ///   block interior; ~1-in-4 blocks are left as empty lots" — an empty
    ///   lot is bare ground, not a hole, and stays walkable because no
    ///   building is ever placed on one (buildings occupy the
    ///   `.buildingFootprint` blocks; see `Chunk.placementSurface`).
    /// - `.buildingFootprint` \u2014 not walkable (explicitly named in the
    ///   brief).
    var isWalkable: Bool {
        switch self {
        case .asphalt, .junctionStopLine, .kerbSidewalk, .lot:
            return true
        case .buildingFootprint:
            return false
        }
    }
}
