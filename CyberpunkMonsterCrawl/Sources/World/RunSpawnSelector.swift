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
    /// How many tiles, on each axis, a run is allowed to roam away from its
    /// spawn junction before it can reach the edge of `DepthModel`'s
    /// supported band.
    ///
    /// The lattice is unbounded but the depth scheme is not: past
    /// `DepthModel.maxSupportedTileSumMagnitude` a node's zPosition escapes
    /// `LayerConstants.worldBand` (`DepthBanding` trips a DEBUG
    /// precondition rather than draw it). Spawn selection therefore cannot
    /// spend the *whole* budget on the spawn point itself -- it has to leave
    /// the run somewhere to walk. This is that reserve: `500` tiles on each
    /// axis is roughly twenty resident streaming windows
    /// (`ChunkStreamingManager.guaranteedMarginTiles` is `24`), far more
    /// ground than a run covers, and it costs only spawn variety, of which
    /// there is a surplus (see `selectionRadiusBlocks`).
    ///
    /// It is a reserve, not a guarantee: a run that walks past it still hits
    /// the same bound. Ending the endlessness of the world at the depth
    /// model's edge is a separate, pre-existing limitation -- what this
    /// constant fixes is spawning a run *already* outside the band.
    static let roamMarginTiles = 500

    /// How many blocks, on each axis, either side of the world origin a
    /// candidate junction may be drawn from.
    ///
    /// **Derived from the depth model, not chosen.** The selected junction's
    /// tile sum is worst-cased at
    /// `2 * selectionRadiusBlocks * CityLatticeGenerator.period
    /// + 2 * junctionCentreOffset` (both axes at the far corner of the
    /// selection square, both offset to the crossing centre), and a run then
    /// roams up to `roamMarginTiles` further on each axis. Inverting
    ///
    ///     2 * radius * period + 2 * junctionCentreOffset + 2 * roamMarginTiles
    ///         <= DepthModel.maxSupportedTileSumMagnitude
    ///
    /// for `radius` gives the largest selection square whose every junction
    /// -- and the run that starts there -- stays inside the band.
    ///
    /// This used to be a flat `512`, described in this comment as
    /// "arbitrary... no particular value here is more 'correct' than
    /// another". That was wrong: at `512` the far corner sums to `6_152`
    /// against a supported `4_450`, so about one seed in seven spawned a run
    /// outside the depth model's supported range and `DepthBanding`'s
    /// precondition killed it. Before `GameScene.startNewRun()` began
    /// drawing random seeds the fixed default always landed in range, which
    /// is why the bound violation went unnoticed rather than unbroken.
    ///
    /// The derived value costs nothing that matters: `286` blocks at today's
    /// constants is a `573 x 573`-block square, ~328k candidate junctions,
    /// still far more than a seed sweep can visibly exhaust.
    static var selectionRadiusBlocks: Int {
        // Both axes contribute to `|tileX + tileY|`, so each of the three
        // terms below is a *per-axis* half of the sum budget.
        let perAxisBudget = DepthModel.maxSupportedTileSumMagnitude / 2
            - junctionCentreOffset
            - roamMarginTiles
        return max(0, perAxisBudget / CityLatticeGenerator.period)
    }

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
    ///
    /// The result always satisfies
    /// `DepthModel.isWithinSupportedDepthRange(forTile:)`, with
    /// `roamMarginTiles` of headroom on each axis -- see
    /// `selectionRadiusBlocks` for the derivation, and
    /// `RunSpawnSelectorTests` for the sweep that checks it.
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
