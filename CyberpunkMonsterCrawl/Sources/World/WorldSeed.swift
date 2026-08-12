import Foundation

/// A per-run world seed: the single value a run is generated from.
///
/// The design brief's contract is "a run is fully described by its seed" \u2014
/// the same `WorldSeed` fed to `CityLatticeGenerator.classify` (directly
/// today; indirectly through chunk streaming once `CYBERPUN-17-3-t3` wraps
/// it) must reproduce the identical city, tile for tile, forever.
/// `WorldSeed` is a thin wrapper around a `UInt64` rather than a bare
/// `UInt64` parameter so call sites can't accidentally pass an unrelated
/// integer (a tile coordinate, a block id, a raw hash) where a seed is
/// expected \u2014 the same discipline `TilePoint` applies to tile space in
/// `IsometricProjection.swift`.
struct WorldSeed: Hashable {
    /// The raw 64-bit seed value. Two `WorldSeed`s with the same
    /// `rawValue` always produce identical output from every generator
    /// function in this module.
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}
