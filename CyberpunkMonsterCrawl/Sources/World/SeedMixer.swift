import Foundation

/// Deterministic, seed-driven bit mixer used everywhere the city-lattice
/// generator needs a pseudo-random-but-reproducible decision for a given
/// tile or block coordinate.
///
/// Deliberately **not** `Hasher`/`.hashValue`: Swift's `Hasher` is
/// documented as randomly seeded per process launch (it draws from the
/// system RNG at process start specifically to resist hash-flooding
/// attacks), so two runs fed the same `WorldSeed` would produce two
/// different cities. `SeedMixer` is a hand-rolled splitmix64-style mixer
/// instead: the same `(seed, tileX, tileY)` triple always produces the
/// same 64-bit output, in any process, on any thread, forever \u2014 which is
/// the whole contract the design brief calls "a run is fully described by
/// its seed."
enum SeedMixer {
    /// The splitmix64 "golden gamma" increment constant
    /// (`0x9E3779B97F4A7C15`, the 64-bit golden-ratio constant splitmix64
    /// uses to decorrelate successive states).
    private static let goldenGamma: UInt64 = 0x9E3779B97F4A7C15

    /// The splitmix64 output-mixing function: two xorshift/multiply rounds
    /// plus a final xorshift, using the standard splitmix64 constants.
    /// Pure, no shared state \u2014 the same input always yields the same
    /// output.
    private static func mix(_ input: UInt64) -> UInt64 {
        var z = input
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return z
    }

    /// Combines a world seed with a tile (or block) coordinate pair into a
    /// single deterministic 64-bit value.
    ///
    /// All arithmetic is wrapping (`&+`/`&*`) so overflow is defined
    /// behaviour rather than a crash, and the output is bit-for-bit
    /// identical for the same inputs regardless of call order or calling
    /// thread \u2014 there is no mutable state anywhere in this type.
    static func hash(seed: UInt64, tileX: Int, tileY: Int) -> UInt64 {
        var state = seed
        state = mix(state &+ (UInt64(bitPattern: Int64(tileX)) &* goldenGamma))
        state = mix(state &+ (UInt64(bitPattern: Int64(tileY)) &* goldenGamma))
        return state
    }

    /// `hash(seed:tileX:tileY:)` reduced to `0..<modulus`. Used for bounded
    /// seed-driven decisions such as the city lattice's ~1-in-4 empty-lot
    /// choice (`modulus: 4`).
    static func bounded(seed: UInt64, tileX: Int, tileY: Int, modulus: UInt64) -> UInt64 {
        hash(seed: seed, tileX: tileX, tileY: tileY) % modulus
    }
}
