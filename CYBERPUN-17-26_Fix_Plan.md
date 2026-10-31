# CYBERPUN-17-26 Fix Plan — building sidewalks not rendered correctly

## Root cause

No production defect was found. `CityLatticeGenerator.classify` (via
`streetTileKind` / `blockBorderedByEdge`) already enforces the exact
invariant the ticket describes: a street-band edge tile, or a
lattice-crossing corner tile, looks up the single block interior it
actually borders (`blockBorderedByEdge`) and only emits `.kerbSidewalk`
when that block is non-empty (`.buildingFootprint`); an edge/corner
beside an empty `.lot` already renders `.asphalt`.

This was fixed under `CYBERPUN-17-22`, is already covered by
`CityLatticeGeneratorTests` / `GroundTileRendererTests`
(`test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState`,
`test_threeTileStreetCrossSection_besideBuiltBlocks_readsAsphaltFlankedBySidewalks`,
`test_threeTileStreetCrossSection_besideEmptyLots_readsAsUnbrokenAsphalt`),
and is independently corroborated by `docs/evidence`'s gate-04 city-read
audit ("no offender found").

Manual proof across straight north-south and east-west corridors, all
four lattice-crossing corners (via `blockBorderedByEdge`'s
`xBandPosition`/`yBandPosition` offset arithmetic), and negative-coordinate
`floorDiv`/`mod` cases confirms the logic holds for every case the AC
names. `GroundTileRenderer` / `GroundTileCatalog` / `BuildingPlacement` /
`BuildingFootprintReservation` were also reviewed and introduce no
mismatch (every lot of a non-empty block is guaranteed a building by
`BuildingPlacement.generate`'s row-major walk with 2x2-overlap fallback,
so `TileKind.buildingFootprint` never disagrees with what is actually
drawn).

**The remaining gap is test coverage, not behavior.** The existing tests
re-derive the generator's own internal block-index arithmetic
(`localFloorDiv`, `xBand == 2 ? 1 : 0`, etc.) rather than independently
checking — via `classify()` called on the tile's *actual* neighboring
coordinates — that every emitted `.kerbSidewalk` tile is genuinely
adjacent to a `.buildingFootprint` tile. That is the literal, black-box
statement of the ticket's acceptance criteria, and it is not yet pinned
that way anywhere in the suite.

## Changes

**File:** `CyberpunkMonsterCrawlTests/CityLatticeGeneratorTests.swift`
(test-only; no production code changes)

Add one new regression test, `test_everyKerbSidewalkTile_hasAnActualBuildingFootprintNeighbor_acrossManySeeds`,
that:

1. Sweeps `CityLatticeGenerator.classify(tileX:tileY:seed:)` over a wide
   tile range (e.g. `-24...24` on both axes) across several seeds (reuse
   the file's existing `someSeeds(_:)` helper).
2. For every tile that classifies as `.kerbSidewalk`, independently calls
   `classify` on all 8 real surrounding neighbor coordinates
   `(tileX + dx, tileY + dy)` for `dx, dy in -1...1` (excluding `(0,0)`)
   and asserts **at least one** neighbor's kind is `.buildingFootprint`.
   This proves the AC directly from real neighbor lookups rather than
   from re-deriving `blockBorderedByEdge`'s internal formula — if a
   future change ever regresses the adjacency guarantee, this test fails
   even if it also breaks in a way that coincidentally keeps the
   formula-mirroring tests green.
3. Additionally sweeps a representative set of street edges/corners that
   border blocks `CityLatticeGenerator.isEmptyLotBlock` reports as empty
   (using `isEmptyLotBlock` only to *pick* fixture coordinates to probe,
   never to compute the expected kind) and asserts the resulting
   `classify(...).kind` is `.asphalt`, never `.kerbSidewalk` — the
   ticket's second bullet, stated independently of the first.

## Tests

- New black-box regression test added as above — the "test that should
  have caught this bug" per the guiding principle, now pinning the AC in
  an implementation-independent way.
- All existing `CityLatticeGeneratorTests` and `GroundTileRendererTests`
  invariants are expected to continue passing unchanged, since no
  production code is touched.
- `code_run_tests` is a no-op signal in this sandboxed environment (no
  native iOS toolchain), so correctness here rests on: (a) the new test
  calling only the public, already-pure `classify` API with no
  reimplementation of its internals, and (b) the manual, from-first-
  principles proof recorded in the Jira findings that the invariant holds
  for every structural case (straight corridors on both axes, all four
  crossing corners, negative-coordinate wraparound).

## Non-goals (per ticket)

- No change to lattice period/street-width structure.
- No change to which blocks are chosen as empty lots.
- No production code changes — investigation found the invariant already
  correctly implemented; this plan only closes the test-coverage gap the
  ticket explicitly asked for ("add a regression test covering the
  reported mismatch").
