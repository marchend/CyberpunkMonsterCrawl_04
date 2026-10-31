import CoreGraphics
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
/// **Visual clearance, not just footprint adjacency.** A junction centre
/// always sits at `junctionCentreOffset` (local offset 4 of the 6-tile
/// period), while a building footprint only ever occupies local offsets
/// 0-2 of its own block -- so the nearest building tile is always *two or
/// more* tiles away from any junction centre on each axis. A naive
/// "candidate tile + its 8 neighbours clear of building footprint" rule
/// (`PickupManager.isLegalPlacement`'s rule, built for pickups scattered
/// across a whole visible rect) can therefore never fire here: its ±1 tile
/// reach never touches a building tile, no matter how the city generates.
/// That is a *different* question from the one this type has to answer --
/// not "is a building directly adjacent", but "does a nearby tall
/// building's sprite, drawn upward from its own base tile under this
/// game's isometric projection and painter's-algorithm depth ordering,
/// visually reach far enough on screen to cover the junction". See
/// `isTileVisuallyOccluded(_:byAnyOf:)` for that check, and
/// `candidateJunction(forAttempt:seed:)` for the deterministic fallback
/// `selectSpawnTile` walks through when a candidate fails it.
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

    /// Safety ceiling on fallback attempts `selectSpawnTile` will try before
    /// giving up and returning the last candidate anyway, rather than
    /// looping forever. A real city can occlude at most a small, bounded
    /// fraction of junctions (a junction is only ever occluded by a tall
    /// building on one of its 4 bordering blocks, and most blocks are
    /// empty lots or hold a short building), so this is many, many times
    /// more attempts than any real seed should ever need -- it exists only
    /// so a pathological `buildingsProvider` (e.g. a test double that
    /// always reports an occluding building) cannot hang the game.
    static let maxFallbackAttempts = 10_000

    /// Selects the run's starting tile for `seed`.
    ///
    /// The result always satisfies
    /// `DepthModel.isWithinSupportedDepthRange(forTile:)`, with
    /// `roamMarginTiles` of headroom on each axis -- see
    /// `selectionRadiusBlocks` for the derivation, and
    /// `RunSpawnSelectorTests` for the sweep that checks it. It is also
    /// always clear of visual building occlusion
    /// (`isTileVisuallyOccluded(_:byAnyOf:)`): `candidateJunction(
    /// forAttempt:seed:)` draws a deterministic sequence of candidate
    /// junctions purely from `seed` and the attempt index (no added
    /// randomness, so a given seed always walks the exact same sequence),
    /// and this method returns the first one that passes the occlusion
    /// check.
    ///
    /// `buildingsProvider` defaults to `BuildingPlacement.generate`, the
    /// production building generator; a test can inject a different
    /// closure to exercise the fallback against a synthetic occluding
    /// building without needing to brute-force a seed that happens to
    /// generate one.
    static func selectSpawnTile(
        seed: WorldSeed,
        buildingsProvider: (BlockCoordinate, WorldSeed) -> [BuildingPlacementRecord] = BuildingPlacement.generate
    ) -> TileCoordinate {
        var attempt = 0
        var lastCandidate: TileCoordinate?
        while attempt < maxFallbackAttempts {
            let (candidate, blockX, blockY) = candidateJunction(forAttempt: attempt, seed: seed)
            let obstructions = neighboringBlocks(blockX: blockX, blockY: blockY)
                .flatMap { buildingsProvider($0, seed) }
            if !isTileVisuallyOccluded(candidate, byAnyOf: obstructions) {
                return candidate
            }
            lastCandidate = candidate
            attempt += 1
        }
        // Practically unreachable (see `maxFallbackAttempts`); returning the
        // last candidate rather than trapping keeps this a total function.
        return lastCandidate ?? candidateJunction(forAttempt: 0, seed: seed).candidate
    }

    /// The `attempt`-th deterministic candidate junction for `seed`, plus
    /// the block coordinate it was derived from (so callers can look up
    /// that block's bordering buildings without re-deriving it).
    ///
    /// `attempt` is folded into the existing `SeedMixer` hash as its own
    /// coordinate input (the same mechanism every other per-tile/per-block
    /// seed decision in `World` already uses to vary its hash stream) --
    /// not added entropy, since the result is still a pure function of
    /// `(seed, attempt)` alone and every attempt for a given seed is fixed
    /// in advance.
    private static func candidateJunction(
        forAttempt attempt: Int, seed: WorldSeed
    ) -> (candidate: TileCoordinate, blockX: Int, blockY: Int) {
        let span = UInt64(selectionRadiusBlocks * 2 + 1)
        let blockX = Int(SeedMixer.bounded(seed: seed.rawValue ^ blockXSalt, tileX: attempt, tileY: 0, modulus: span))
            - selectionRadiusBlocks
        let blockY = Int(SeedMixer.bounded(seed: seed.rawValue ^ blockYSalt, tileX: attempt, tileY: 0, modulus: span))
            - selectionRadiusBlocks

        let tileX = blockX * CityLatticeGenerator.period + junctionCentreOffset
        let tileY = blockY * CityLatticeGenerator.period + junctionCentreOffset
        return (TileCoordinate(tileX: tileX, tileY: tileY), blockX, blockY)
    }

    /// The (up to) 4 blocks whose interior can border the lattice crossing
    /// at block coordinate `(blockX, blockY)` -- see `junctionCentreOffset`:
    /// a junction's tile is `blockX * period + junctionCentreOffset` on
    /// each axis, which sits between block `blockX`/`blockY`'s own interior
    /// and the next block up on each axis. The diagonal block `(blockX + 1,
    /// blockY + 1)` can never actually be nearer the camera than the
    /// junction itself (every one of its tiles has a strictly greater tile
    /// sum), but it costs nothing to include it here rather than special-
    /// case it out -- `isTileVisuallyOccluded` already filters on tile sum.
    private static func neighboringBlocks(blockX: Int, blockY: Int) -> [BlockCoordinate] {
        [
            BlockCoordinate(x: blockX, y: blockY),
            BlockCoordinate(x: blockX + 1, y: blockY),
            BlockCoordinate(x: blockX, y: blockY + 1),
            BlockCoordinate(x: blockX + 1, y: blockY + 1)
        ]
    }

    /// A conservative (never-undercounts) approximate pixel height for a
    /// building's `BuildingCatalog.HeightClass`, used only to test whether
    /// a building's sprite could visually reach tall enough on screen to
    /// occlude a tile behind it (`isTileVisuallyOccluded`).
    ///
    /// Mirrors the measured pixel heights `Sources/Assets/
    /// BuildingSprite.declaredPixelSize` already documents per entry
    /// (`CityReadComparisonTests` cross-checks those against the shipped
    /// art) -- duplicated here as plain numbers, not imported, for the same
    /// "`World` stays SpriteKit-free" reason `BuildingCatalog` itself
    /// already duplicates `BuildingSprite`'s footprint/height-class table
    /// rather than importing it. Each class takes its *tallest* member's
    /// measured height (e.g. `.mid` takes `building_04`'s 176px over
    /// `building_06`/`07`'s 144px and `building_08`/`09`'s 136px), so this
    /// can only ever *overestimate* a shorter member's reach -- an
    /// overestimate costs only an extra fallback attempt; an underestimate
    /// would silently let an occluding building through, the exact defect
    /// this type exists to fix.
    static func approximatePixelHeight(forHeightClass heightClass: BuildingCatalog.HeightClass) -> Double {
        switch heightClass {
        case .lowest: return 80 // building_10
        case .low: return 112 // building_00...03
        case .mid: return 176 // tallest of building_04/06/07/08/09
        case .tall: return 240 // building_05
        case .large: return 192 // building_11
        }
    }

    /// Whether `tile` could be visually occluded -- under this game's
    /// isometric projection and `DepthModel`'s painter's-algorithm depth
    /// ordering -- by any building in `records`.
    ///
    /// Unlike `PickupManager.isLegalPlacement`'s "tile + 8 neighbours
    /// clear" building-adjacency rule -- which only ever asks about
    /// footprint tiles directly touching the candidate, and so can never
    /// fire for a junction centre tile (see this file's own doc comment) --
    /// this asks the question that actually determines visibility: does a
    /// nearby building's *sprite*, drawn upward from its base tile in
    /// screen space, reach tall enough on screen to cover `tile`'s own
    /// screen position?
    ///
    /// A building can only ever occlude `tile` if both hold:
    /// - **It draws in front of `tile`.** `DepthModel`'s band ordering is
    ///   strictly per-diagonal (`tileX + tileY`): any tile with a *strictly
    ///   smaller* tile sum sits in a band with a higher zPosition than
    ///   `tile` -- `DepthModel.bandSpacing` (10) is wider than both
    ///   `DepthModel.buildingContentRange` and `DepthModel.actorOffsetRange`
    ///   combined, so this holds regardless of either tile's in-band offset
    ///   -- and so draws on top of it; any tile with an equal or greater
    ///   sum draws behind or beside it and can never visually cover it.
    /// - **It lines up with `tile` on screen, and reaches tall enough.**
    ///   `IsometricProjection.tileToScreen` gives each tile's on-screen
    ///   point; a building's sprite is anchored at its base tile and
    ///   extends upward (screen `+y`) by its own approximate pixel height
    ///   (`approximatePixelHeight(forHeightClass:)`). If the horizontal gap
    ///   between the two tiles' screen points is within one tile's
    ///   half-width and the building's height clears the vertical gap, its
    ///   sprite's on-screen footprint covers `tile`'s point.
    static func isTileVisuallyOccluded(_ tile: TileCoordinate, byAnyOf records: [BuildingPlacementRecord]) -> Bool {
        let tileSum = tile.tileX + tile.tileY
        let tileScreen = IsometricProjection.tileToScreen(tileX: Double(tile.tileX), tileY: Double(tile.tileY))

        for record in records {
            let buildingHeight = approximatePixelHeight(forHeightClass: record.building.heightClass)
            for footprintTile in record.footprintTiles {
                guard footprintTile.tileX + footprintTile.tileY < tileSum else { continue }

                let buildingScreen = IsometricProjection.tileToScreen(
                    tileX: Double(footprintTile.tileX), tileY: Double(footprintTile.tileY)
                )
                let horizontalGap = abs(Double(buildingScreen.x - tileScreen.x))
                guard horizontalGap < IsometricProjection.tileHalfWidth else { continue }

                let verticalGap = Double(tileScreen.y - buildingScreen.y)
                if verticalGap >= 0 && verticalGap < buildingHeight {
                    return true
                }
            }
        }
        return false
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
