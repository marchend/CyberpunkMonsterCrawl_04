# Fix Plan — CYBERPUN-17-19: Player starts hidden

> Complexity gate: `assess_complexity` returned **complex** (≈120 estimated LOC
> crossed the auto-threshold, despite only 2 files being touched and no
> schema/API change). Per process, this ticket is written up here rather than
> implemented directly in this phase.

## Root cause
`RunSpawnSelector.selectSpawnTile(seed:)`
(`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`) deterministically
picks a street-intersection's driving-lane centre tile from the seed alone. It
never checks whether that tile is actually clear of building obstruction — a
tall building on a neighbouring block can still visually occlude the player at
that tile. This is the same class of issue gate 5 (pickup visibility) already
solved for pickups.

## Precedent to follow
`PickupManager.isLegalPlacement`
(`CyberpunkMonsterCrawl/Sources/Pickups/PickupManager.swift`) already defines
"visible" for this codebase: a tile only counts as visible if the tile itself
*and all 8 neighbours* are free of any building footprint, checked via
`BuildingObstruction.isObstructed(_:byAnyOf:)` against
`CityLatticeGenerator`/`BuildingPlacementRecord` obstructions.

## Acceptance criteria
- `RunSpawnSelector.selectSpawnTile(seed:)` must never return a junction tile
  where the tile or any of its 8 neighbours is obstructed by a building
  footprint (same rule as `PickupManager.isLegalPlacement`'s
  building-adjacency check).
- If the seed-derived junction is obstructed, the selector must
  deterministically fall back to another candidate junction (still satisfying
  `RunSpawnSelector.isIntersectionTile`) rather than spawning on the
  obstructed one. Fallback must remain a pure function of `seed` (no
  randomness beyond the existing seed-driven selection) so runs stay
  reproducible.
- Must continue to satisfy existing invariants: always an intersection tile
  (`isIntersectionTile`), always within `DepthModel`'s supported tile-sum
  range (see `selectionRadiusBlocks`/`roamMarginTiles` headroom).
- Add/extend `RunSpawnSelectorTests` to cover: a seed whose default junction
  is obstructed falls back to a clear one; the result is always
  building-free per the 8-neighbour rule.

## Non-goals
- Not changing pickup, raccoon, or general actor visibility/occlusion rules —
  those are untouched.
- Not changing `DepthBanding`/painter's-algorithm z-ordering itself — the fix
  is in tile *selection*, not rendering order.

## Implementation tasks

1. **`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`** — In
   `selectSpawnTile(seed:)`, after computing the seed-derived junction tile,
   check it (and its 8 neighbours) for building obstruction via
   `BuildingObstruction.isObstructed(_:byAnyOf:)`, using the same
   obstruction-provider data `PickupManager.isLegalPlacement` uses.
2. **`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`** — Add a
   private helper mirroring `PickupManager.isLegalPlacement`'s "tile + 8
   neighbours clear" rule, scoped to spawn-tile validation (e.g.
   `isClearOfBuildingObstruction(tile:)`).
3. **`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`** —
   Implement a deterministic fallback: when the seed-derived junction fails
   the obstruction check, iterate remaining candidate junctions (those
   satisfying `isIntersectionTile`) in a fixed, seed-derived order until a
   clear one is found — no added randomness.
4. **`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`** — Ensure
   fallback candidates still respect existing invariants: `isIntersectionTile`
   true, and within `DepthModel`'s supported tile-sum range
   (`selectionRadiusBlocks`/`roamMarginTiles` headroom).
5. **`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`** — Thread
   through whatever obstruction-data context
   (`CityLatticeGenerator`/`BuildingPlacementRecord` obstructions) is needed
   as a parameter/dependency to `selectSpawnTile`, matching how
   `PickupManager` receives its `obstructionsProvider`-equivalent (read-only,
   no changes to those types).
6. **`CyberpunkMonsterCrawlTests/RunSpawnSelectorTests.swift`** — Add a test
   asserting that when the seed's default junction is obstructed,
   `selectSpawnTile` falls back to a different, clear junction
   (deterministically, same result on repeat runs with that seed).
7. **`CyberpunkMonsterCrawlTests/RunSpawnSelectorTests.swift`** — Add a test
   asserting the returned tile always passes the 8-neighbour building-free
   rule across a sample of seeds (including at least one known-obstructed and
   one known-clear seed).
8. **`CyberpunkMonsterCrawlTests/RunSpawnSelectorTests.swift`** — Add/extend a
   regression test confirming existing invariants still hold post-fix: result
   is always an intersection tile and within `DepthModel`'s supported
   tile-sum range.

## Affected components
- `CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`
- `CyberpunkMonsterCrawlTests/RunSpawnSelectorTests.swift`
- Reads (no changes expected): `BuildingObstruction`, `CityLatticeGenerator`,
  `BuildingPlacementRecord` (whatever supplies the
  `obstructionsProvider`-equivalent data for `RunSpawnSelector`'s context).
