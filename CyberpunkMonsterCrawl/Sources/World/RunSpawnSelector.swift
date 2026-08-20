import Foundation

/// Selects the run's starting tile: a street-intersection tile the player
/// spawns on, chosen deterministically from the run's `WorldSeed`.
///
/// **Why an intersection.** `CityLatticeGenerator`'s own contract is that
/// every intersection tile is street under every seed (docs/bootstrap.md
/// section 1: "every intersection tile is street under every seed") --
/// the crossing where two street corridors meet is never seed-decided,
/// unlike a block interior's lot-vs-building choice. Spawning there means a
/// run always starts on guaranteed-walkable ground with a path in every
/// direction along the lattice, independent of how the seed happened to
/// decide the neighbouring blocks.
///
/// **Which tile, precisely.** Not merely *a* tile inside the 3x3 crossing
/// area, but its exact centre -- the driving-lane tile where both axes sit
/// on their street band's centre lane (`CityLatticeGenerator.streetTileKind`
/// names this the crossing's centre: always `.asphalt`, never
/// `.junctionStopLine`/`.kerbSidewalk`). That is the one point of the
/// crossing every direction of travel leaves equally freely.
///
/// **Determinism and variety.** `selectSpawnTile(seed:)` is a pure function
/// of `seed` alone, via `SeedMixer` -- the same deterministic bit mixer
/// every other seed-driven decision in `World` uses -- so the same seed
/// always spawns a run at the same junction, and two different seeds
/// overwhelmingly choose two different junctions
/// (`RunSpawnSelectorTests` checks this holds across many seeds).
///
/// **That variety reaches the player via `GameScene.worldSeed`.**
/// `GameScene.startNewRun()` (`CYBERPUN-17-13` PR 3) draws a fresh random
/// `worldSeed` before every RUN AGAIN, so consecutive runs are handed
/// different seeds and land at different junctions; the very first
/// `.menu -> .gameplay` entry still spawns at the fixed default's
/// junction -- see `GameScene.worldSeed`'s own doc comment.
enum RunSpawnSelector {
    /// How many blocks, on each axis, either side of the world origin a
    /// candidate junction may be drawn from. Large enough that a sweep of
    /// distinct seeds lands on visibly different junctions rather than a
    /// small, easily-exhausted set; arbitrary otherwise -- the lattice is
    /// unbounded, so no particular value here is more "correct" than
    /// another.
    static let selectionRadiusBlocks = 512

    /// Salts distinguishing this decision's hash stream from every other
    /// per-seed decision hashed against small integer coordinates (the city
    /// lattice's empty-lot choice, `BuildingPlacement`'s building pick), so
    /// a shared `WorldSeed` cannot make them agree by accident -- the same
    /// technique `BuildingPlacement.buildingSelectionSalt` uses for the
    /// identical reason.
    private static let blockXSalt: UInt64 = 0x5BAB_5EED_0001
    private static let blockYSalt: UInt64 = 0x5BAB_5EED_0002

    /// The tile-space offset, from a block's own `(blockX, blockY)`, of the
    /// crossing centre this type spawns on: `blockSize + streetWidth / 2` --
    /// the driving lane's own centre column/row of the 3-tile street band
    /// immediately after the block's interior (see
    /// `CityLatticeGenerator`'s "Design (period 6, per the brief)" note).
    /// Exposed so a caller (and this type's own tests) can derive which
    /// block a selected spawn tile belongs to, without duplicating this
    /// arithmetic.
    static let junctionCentreOffset = CityLatticeGenerator.blockSize + CityLatticeGenerator.streetWidth / 2

    /// Selects the run's starting tile for `seed`.
    static func selectSpawnTile(seed: WorldSeed) -> TileCoordinate {
        let span = UInt64(selectionRadiusBlocks * 2 + 1)
        let blockX = Int(SeedMixer.bounded(seed: seed.rawValue ^ blockXSalt, tileX: 0, tileY: 0, modulus: span))
            - selectionRadiusBlocks
        let blockY = Int(SeedMixer.bounded(seed: seed.rawValue ^ blockYSalt, tileX: 0, tileY: 0, modulus: span))
            - selectionRadiusBlocks

        let tileX = blockX * CityLatticeGenerator.period + junctionCentreOffset
        let tileY = blockY * CityLatticeGenerator.period + junctionCentreOffset
        return TileCoordinate(tileX: tileX, tileY: tileY)
    }

    /// Whether `(tileX, tileY)` falls inside a lattice crossing -- both
    /// axes' coordinates land in their own street band (remainder `>=
    /// blockSize` within the tile's period-6 remainder), the same
    /// "isStreetX && isStreetY" condition `CityLatticeGenerator.classify`
    /// uses internally to pick a crossing's sub-kind.
    ///
    /// Exposed so a caller -- and this type's own tests -- can check the
    /// general intersection property without re-deriving
    /// `CityLatticeGenerator`'s private band math. The specific tile
    /// `selectSpawnTile` returns always satisfies this (and more: it is
    /// always the crossing's exact driving-lane centre), but a future
    /// caller checking an arbitrary tile can use this on its own.
    static func isIntersectionTile(tileX: Int, tileY: Int) -> Bool {
        isStreetBand(tileX) && isStreetBand(tileY)
    }

    private static func isStreetBand(_ coordinate: Int) -> Bool {
        let remainder = ((coordinate % CityLatticeGenerator.period) + CityLatticeGenerator.period)
            % CityLatticeGenerator.period
        return remainder >= CityLatticeGenerator.blockSize
    }
}
