/// The per-tile classification the city-lattice generator assigns to every
/// tile. Rendering (ground plane, buildings) and collision both key off
/// this rather than re-deriving lattice geometry themselves.
enum TileKind: Equatable {
    /// The street corridor's driving lane \u2014 the centre of a 3-tile-wide
    /// street band. Fully walkable; part of the navmesh.
    case asphalt
    /// The painted stop line inside a lattice crossing (a 3x3 intersection
    /// area), on every tile of the crossing except its own centre. Still
    /// street, still walkable, still part of the navmesh \u2014 this is a
    /// paint/marking distinction for rendering, not a collision
    /// distinction.
    case junctionStopLine
    /// The sidewalk bordering a street band on the side nearest a block.
    /// Walkable \u2014 the player and the raccoon swarm cross it exactly like
    /// asphalt; it exists as a separate case purely so the ground-plane
    /// renderer can draw a kerb/sidewalk texture instead of asphalt there.
    case kerbSidewalk
    /// A block interior left empty by the seed's ~1-in-4 decision. Walkable
    /// ground until the building-placement story (`CYBERPUN-17-5`)
    /// reserves it for a placed building \u2014 at that point the *placed
    /// building's* footprint tiles become `.buildingFootprint`; an empty
    /// `.lot` does not turn solid on its own.
    case lot
    /// A block interior tile consumed by a building. Solid collision \u2014
    /// not walkable \u2014 regardless of the building's drawn height, per the
    /// brief: "a building blocks movement by its footprint regardless of
    /// drawn height."
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
    /// - `.lot` \u2014 walkable. The brief: "Buildings fill the 3x3 block
    ///   interior; ~1-in-4 blocks are left as empty lots" \u2014 an empty lot is
    ///   bare ground, not a hole, until a building is actually placed on
    ///   it.
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
