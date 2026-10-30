# CYBERPUN-17-19 — Fix Plan: "Player starts hidden"

## Bug summary
When starting a new game, the player can spawn on a street-intersection
tile that is visually occluded by a nearby building. The player should
always start on a tile that is guaranteed visible.

## Root cause
`RunSpawnSelector.selectSpawnTile(seed:)`
(`CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`)
deterministically picks the seed-derived street-junction's driving-lane
centre tile but never checks it for building obstruction. This is the same
class of issue `PickupManager.isLegalPlacement`
(`CyberpunkMonsterCrawl/Sources/Pickups/PickupManager.swift`) already
solved for pickups: a tile only counts as "visible" in this codebase if the
tile itself **and all 8 neighbours** are free of any building footprint,
checked via `BuildingObstruction.isObstructed(_:byAnyOf:)`.

### Caveat (recorded for reviewers, does not change the plan)
Tracing `CityLatticeGenerator`'s constants (`period = 6`, `blockSize = 3`,
`streetWidth = 3`) shows the junction centre always sits at local offset 4
(the middle of the 3-tile street band) and its 8 neighbours sit at offsets
3/5 — both structurally always inside the street band. `BuildingPlacement
.generate` can only place footprints at offsets 0–2 (the block interior),
so this specific check can never actually trigger against the *real*
generator today. It is still implemented exactly as specified in the
ticket's acceptance criteria (mirroring `PickupManager`'s established
precedent for "visible"), and is exercised in tests via an injected
fixture — the same way `PickupManagerTests` already tests `PickupManager`'s
equivalent check. This is a safety net / consistency fix, not a
currently-reachable runtime branch; if the real-world occlusion turns out
to be a rendering/z-order issue instead, that is explicitly out of scope
(see Non-goals) and would need a separate ticket.

## Acceptance criteria (from ticket)
- `RunSpawnSelector.selectSpawnTile(seed:)` must never return a junction
  tile where the tile or any of its 8 neighbours is obstructed by a
  building footprint (same rule as `PickupManager.isLegalPlacement`).
- If the seed-derived junction is obstructed, the selector must
  deterministically fall back to another candidate junction (still
  satisfying `RunSpawnSelector.isIntersectionTile`) rather than spawning on
  the obstructed one. Fallback must remain a pure function of `seed` (no
  randomness beyond the existing seed-driven selection).
- Must continue to satisfy existing invariants: always an intersection
  tile, always within `DepthModel`'s supported tile-sum range.
- Add/extend `RunSpawnSelectorTests` to cover: a seed whose default
  junction is obstructed falls back to a clear one; the result is always
  building-free per the 8-neighbour rule.

## Non-goals
- Not changing pickup, raccoon, or general actor visibility/occlusion
  rules.
- Not changing `DepthBanding`/painter's-algorithm z-ordering — the fix is
  in tile *selection*, not rendering order.

## Implementation plan

### `CyberpunkMonsterCrawl/Sources/World/RunSpawnSelector.swift`

1. **New injectable parameter, defaulted for backward compatibility.**
   Add `obstructionsProvider: (BlockCoordinate, WorldSeed) ->
   [BuildingPlacementRecord] = BuildingPlacement.generate(forBlock:seed:)`
   to `selectSpawnTile(seed:)`. Because it has a default value matching the
   real production generator, every existing call site (`GameScene
   .spawnTilePosition()`, `PlayerMountTests`, `PickupManagerTests`,
   `RunVarietyTests`, `GameStateMachineTests`) keeps compiling and
   behaving identically with zero changes.

2. **Factor out the existing block/tile derivation, parameterized by an
   `attempt` index.**
   - `candidateBlock(seed:attempt:) -> (blockX: Int, blockY: Int)`: same
     `SeedMixer.bounded(seed: seed.rawValue ^ blockXSalt/blockYSalt, ...)`
     calls as today, but fold `attempt` into the coordinate argument
     already passed to `SeedMixer.bounded` (e.g. `tileX: attempt` for the
     X salt, `tileY: attempt` for the Y salt) instead of the current fixed
     `0`. At `attempt == 0` this reproduces today's exact output
     bit-for-bit — no behavior change for the default (expected-always)
     path.
   - `junctionTile(blockX:blockY:) -> TileCoordinate`: the existing
     `blockX * period + junctionCentreOffset` arithmetic, unchanged.

3. **New private obstruction check.**
   `isObstructed(_:nearBlockX:blockY:seed:obstructionsProvider:) -> Bool`:
   gathers `BuildingPlacementRecord`s from the surrounding 3x3 blocks
   (`blockX-1...blockX+1`, `blockY-1...blockY+1`) via `obstructionsProvider`,
   then checks the junction tile and all 8 neighbours against the combined
   records using `BuildingObstruction.isObstructed(_:byAnyOf:)` — the same
   `dx in -1...1, dy in -1...1` loop `PickupManager.isLegalPlacement` uses.

4. **Attempt loop in `selectSpawnTile`.**
   Loop `attempt` from `0` up to a bounded `maxSelectionAttempts` (e.g.
   `64`, mirroring `PickupManager.maxPlacementAttemptsPerSpawn`'s
   precedent for "try N candidates, bounded"). Return the first
   `junctionTile` that passes the obstruction check. If every attempt is
   exhausted (documented as structurally unreachable per the caveat
   above — never a silent behavior change players can hit), fall back to
   attempt `0`'s tile so the function stays total.

5. **Doc comments.** Extend the existing (very thorough) doc comments on
   `selectSpawnTile` to explain the obstruction check, the fallback, and
   the structural-unreachability caveat, matching this file's existing
   documentation style.

### `CyberpunkMonsterCrawlTests/RunSpawnSelectorTests.swift`

1. **`test_obstructedDefaultJunction_fallsBackToAClearJunction`**
   - Compute a seed's baseline tile using the default (real) provider.
   - Build a hand-built obstructing provider that returns a
     `BuildingPlacementRecord` whose `footprintTiles` contains exactly the
     baseline tile (regardless of which block is queried).
   - Call `selectSpawnTile(seed:obstructionsProvider:)` with the
     obstructing provider and assert: the result is **different** from the
     baseline tile, still satisfies `isIntersectionTile`, and is **not**
     obstructed under the same obstructing provider (re-run the same
     8-neighbour check used in production against the result).

2. **`test_fallback_isDeterministic_forTheSameSeedAndObstructingProvider`**
   - Call `selectSpawnTile(seed:obstructionsProvider:)` twice with the same
     seed and the same obstructing provider fixture; assert equal results.

3. **`test_selectedSpawnTile_isAlwaysObstructionFree_againstTheRealGenerator_acrossManySeeds`**
   - Sweep seeds with the real default provider
     (`BuildingPlacement.generate(forBlock:seed:)`), and assert
     `BuildingObstruction.isObstructed` is false for the tile and all 8
     neighbours. This pins the structural invariant against the actual
     generator, so a future change to `CityLatticeGenerator`'s constants
     that breaks the guarantee described in the caveat is caught by a
     test rather than discovered as a reopened bug report.

4. Existing tests (`isIntersectionTile`, street-walkable, depth-range,
   worst-case corner, determinism) are expected to keep passing unchanged,
   since `attempt == 0`'s derivation is bit-for-bit identical to today's.

## Risk / scope check
- No schema or public API break: the new parameter is defaulted.
- No change to `DepthBanding`, rendering, or any other actor's visibility
  rules.
- Touches exactly 2 files.
- All new logic is pure and deterministic (seed + injected provider only),
  consistent with `RunSpawnSelector`'s existing "pure function of seed"
  contract.
