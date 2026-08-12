import CoreGraphics

/// One owning list of valid cell indices per atlas-sheet family.
///
/// `docs/bootstrap.md` §2: "one owning index list per family — no magic
/// numbers scattered across consumers." Every family currently uses its
/// entire measured grid (there are no held-back cells for any of the 10
/// sheets), so each list below is the exhaustive `(col, row)` product of that
/// family's declared grid rather than a hand-picked subset — but it still
/// lives in exactly one place, so a future consumer writes
/// `AtlasCellIndex.playerWalk` instead of `for row in 0..<8 { for col in
/// 0..<4 { ... } }` at its own call site. `AtlasContractConventionTests`
/// enforces that no other file constructs cell rects by hand.
enum AtlasCellIndex {
    /// A single `(column, row)` cell reference into a `SpriteSheet`'s grid,
    /// using the same top-row-is-index-0 convention as the design table
    /// (`SpriteSheet.texture(col:row:)` handles the SpriteKit-origin flip).
    struct CellIndex: Equatable {
        let col: Int
        let row: Int
    }

    private static func grid(columns: Int, rows: Int) -> [CellIndex] {
        (0..<rows).flatMap { row in
            (0..<columns).map { col in CellIndex(col: col, row: row) }
        }
    }

    /// `sprite_player_walk`: 4 frames (cols) × 8 directions (rows) = 32 cells.
    static let playerWalk: [CellIndex] = grid(columns: 4, rows: 8)

    /// `sprite_player_weapons`: 8 directions (cols) × 3 weapon tiers (rows) = 24 cells.
    static let playerWeapons: [CellIndex] = grid(columns: 8, rows: 3)

    /// `sprite_raccoon_walk`: 4 frames (cols) × 8 directions (rows) = 32 cells.
    static let raccoonWalk: [CellIndex] = grid(columns: 4, rows: 8)

    /// `sprite_raccoon_attack`: 4 frames (cols) × 8 directions (rows) = 32 cells.
    static let raccoonAttack: [CellIndex] = grid(columns: 4, rows: 8)

    /// `sprite_bullets`: 3 variants in a single row (slug, SMG tracer, rifle round).
    static let bullets: [CellIndex] = grid(columns: 3, rows: 1)

    /// `sprite_pickups`: 2 variants in a single row (med kit, garbage can).
    static let pickups: [CellIndex] = grid(columns: 2, rows: 1)

    /// `sprite_pulse`: 8 shockwave frames in a single row.
    static let pulse: [CellIndex] = grid(columns: 8, rows: 1)

    /// `sprite_hit_puff`: 4 frames in a single row (frame 0 doubles as the muzzle flash).
    static let hitPuff: [CellIndex] = grid(columns: 4, rows: 1)

    /// `sprite_signs`: 12 rooftop neon sign variants, 4 cols × 3 rows.
    static let signs: [CellIndex] = grid(columns: 4, rows: 3)

    /// The six `tileset_ground` diamond sub-rects. These are not a uniform
    /// grid (see the measurement comment on `AtlasGroundDiamond` in
    /// `AtlasSheet.swift`), so they are indexed by `AtlasGroundDiamond`
    /// rather than `CellIndex`. Re-exported here so every family's owning
    /// list is discoverable from `AtlasCellIndex` in one place, even though
    /// the underlying rects live alongside `AtlasSheet`.
    static let groundDiamonds: [AtlasGroundDiamond] = AtlasGroundDiamond.allCases
}
