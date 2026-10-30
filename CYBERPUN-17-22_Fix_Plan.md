# Fix Plan — CYBERPUN-17-22: Street Rendering looks bad

## Bug summary
Kerb sidewalk tiles currently ring every block interior unconditionally — both
empty `.lot` interiors and `.buildingFootprint` interiors — making street
corridors that border an empty lot look wrong: sidewalk tiles should only
visually hug an actual building edge.

## Root cause
`CityLatticeGenerator.streetTileKind` decides `.kerbSidewalk` vs `.asphalt`
for street-band edge tiles (band position 0/2 on a straight corridor, and the
four "corner" tiles at a lattice crossing) purely from `xMod`/`yMod` —
structural inputs only. It never consults which block interior that edge
actually borders, so a kerb-sidewalk ring is drawn around every block
interior unconditionally, including empty `.lot` interiors that have no
building edge to hug.

## Accepted tradeoff
This makes street-tile classification depend on the seed-driven lot/building
decision for the adjacent block interior. The previously-documented "street
tiles are 100% structural / never consult seed" invariant must be updated:
lattice **connectivity** (driving lanes, intersection-is-always-street) stays
structural/seed-independent — because both `.asphalt` and `.kerbSidewalk` are
walkable street kinds — but the kerb-vs-asphalt *cosmetic* choice at a band
edge now depends on the adjacent block's seed-driven state.

## Non-goals
- No change to the 6x6 period, block/street sizing.
- No change to junction corner/stop-line logic for the lane-mouth tiles
  (where one axis is the centre driving lane) — only the
  kerbSidewalk-vs-asphalt decision on straight corridor edges and crossing
  corners (both axes on a band edge) changes.

## Changes

### `CyberpunkMonsterCrawl/Sources/World/CityLatticeGenerator.swift`
1. Extend `streetTileKind`'s signature to accept `tileX: Int, tileY: Int,
   seed: WorldSeed` in addition to its current `xMod/yMod/isStreetX/isStreetY`
   params; update its one call site inside `classify`.
2. Add a small private helper:
   ```swift
   private static func adjacentBlockCoordinate(_ coordinate: Int, bandPosition: Int) -> Int {
       let block = floorDiv(coordinate, period)
       return bandPosition == 0 ? block : block + 1
   }
   ```
   Band position 0 is the edge nearest the lower-index block (same period's
   interior); band position 2 is the edge nearest the higher-index block
   (next period's interior), so position 2 adds 1 to the block index.
3. Straight-corridor branch (`bandPosition != 1`, i.e. not the driving lane):
   compute the bordering block's `(blockX, blockY)` — using
   `adjacentBlockCoordinate` on the street-band axis, and plain `floorDiv` on
   the non-banded (interior) axis — then return `.asphalt` if
   `isEmptyLotBlock(blockX:blockY:seed:)` is true, else `.kerbSidewalk`.
4. Crossing-corner branch (both axes on a band edge, i.e. not lane, not
   mouth): same lookup pattern using `adjacentBlockCoordinate` on *both*
   axes to find the one diagonal neighbor block, same `.asphalt` /
   `.kerbSidewalk` choice. The lane-mouth (`.junctionStopLine`) and
   driving-lane-centre (`.asphalt`) cases are untouched.
5. Update the doc comments on `streetTileKind` and the enum-level doc
   comment that currently assert street tiles never consult the seed, to
   describe the corrected invariant (see "Accepted tradeoff" above).

### No changes needed
`GroundTileCatalog.swift` / `GroundTileRenderer.swift` require no changes:
`.asphalt` already exists as a `TileKind`, and `GroundTileRenderer`'s
orientation lookup (`asphaltOrientation`) is based only on which axis is
banded (`isStreetX`/`isStreetY`), not on band position — so newly-asphalt
edge/corner tiles render with the correct orientation already, including the
existing "ambiguous crossing-centre tile defaults to `.asphaltEastWest`"
fallback, which also covers the new corner case.

## Tests

### `CyberpunkMonsterCrawlTests/CityLatticeGeneratorTests.swift`
1. `test_classify_sidewalkRingAroundABlockInterior_isUnbrokenIncludingCorners`:
   split into two assertions —
   - (a) ring tiles bordering a block for which `isEmptyLotBlock` is `false`
     (a building) still render `.kerbSidewalk` (AC1, unchanged behavior).
   - (b) ring tiles bordering a block for which `isEmptyLotBlock` is `true`
     (an empty lot) render `.asphalt` instead (AC2, new behavior).
   Use/construct seeds so both a building-block and a lot-block are
   deterministically exercised (e.g. pick two seeds, or sweep blocks under
   one seed and partition expectations by `isEmptyLotBlock`).
2. `test_classify_crossing_pinsCentreLaneMouthAndCornerSubKinds`: update the
   local `expectedKind` helper so the corner case consults the diagonal
   neighbor block's `isEmptyLotBlock` state instead of unconditionally
   expecting `.kerbSidewalk`; lane and mouth expectations stay unchanged.
3. Update the file's top-level doc comment and any inline comments that
   state street tiles are classified "independent of any specific seed" to
   describe the corrected invariant: kerb-vs-asphalt at a band edge/corner
   depends on the adjacent block's seed-driven lot/building decision, while
   lattice connectivity and "every intersection tile is street" remain
   seed-independent.
4. No changes expected in `ConnectivityTests.swift`: both `.asphalt` and
   `.kerbSidewalk` are walkable (`TileKind.isWalkable`), so reclassifying
   some edge tiles between the two kinds does not affect the flood-fill
   connectivity guarantee.

## Risk / verification notes
- `TileKind.isWalkable` already returns `true` for both `.asphalt` and
  `.kerbSidewalk`, so this change cannot break pathfinding/connectivity —
  it is purely a cosmetic reclassification between two already-walkable
  street kinds.
- `isEmptyLotBlock` is an existing, already-tested pure function
  (`SeedMixer.bounded`), reused as-is — no new seed-mixing logic is
  introduced.
- Verify the block-coordinate math symmetrically: for a street band at
  `tileX = k*period + blockSize` (band position 0), `floorDiv` must resolve
  to block `k` (the block whose interior immediately precedes the band);
  for `tileX = k*period + period - 1` (band position 2), the neighbor must
  resolve to block `k + 1` (the block whose interior immediately follows).
  This should be spot-checked for at least one negative-coordinate case
  (crossing `x = 0` / `y = 0`), matching this file's existing
  negative-safe-arithmetic test coverage pattern.
