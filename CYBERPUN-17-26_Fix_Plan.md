# CYBERPUN-17-26 — Fix plan

**Bug:** building sidewalks not rendered correctly

## Root cause

Exhaustive review of CityLatticeGenerator.classify/streetTileKind/blockBorderedByEdge (plus GroundTileRenderer/GroundTileCatalog and BuildingPlacement/BuildingFootprintReservation) shows the adjacency invariant the ticket describes is already enforced: every street-band edge or crossing-corner tile looks up the single block interior it actually borders via blockBorderedByEdge and only emits .kerbSidewalk when that block is non-empty (.buildingFootprint); an edge/corner beside an empty .lot already renders .asphalt. This was the CYBERPUN-17-22 fix, and it is independently corroborated by existing tests (test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState, the two GroundTileRendererTests cross-section tests) and by docs/evidence's gate-04 city-read audit ("no offender found"). Manual proof of every straight-edge/crossing-corner/negative-coordinate case confirms no current defect. The remaining gap is test coverage, not logic: existing tests re-derive the same internal block-arithmetic the generator uses rather than independently verifying, tile-by-tile via classify() on actual neighboring tiles, that no .kerbSidewalk tile is emitted without a true .buildingFootprint neighbor — the literal, black-box statement of the ticket's acceptance criteria.

## Plan

## Fix Plan — CYBERPUN-17-26

**Root cause:** No production defect found. `CityLatticeGenerator.classify` (via `streetTileKind`/`blockBorderedByEdge`) already enforces the exact invariant the ticket describes: a street-band edge or lattice-crossing corner tile looks up the single block interior it borders and only emits `.kerbSidewalk` when that block is non-empty (`.buildingFootprint`); an edge/corner beside an empty `.lot` already renders `.asphalt`. This was fixed under CYBERPUN-17-22, is already covered by `CityLatticeGeneratorTests`/`GroundTileRendererTests`, and is independently corroborated by the `docs/evidence` gate-04 city-read audit ("no offender found"). Manual proof across straight corridors, all four crossing corners, and negative-coordinate `floorDiv`/`mod` cases confirms the logic holds. The gap is coverage, not behavior: existing tests re-derive the generator's own internal block-index arithmetic rather than independently checking, via `classify()` on real neighboring tiles, that every `.kerbSidewalk` tile is genuinely adjacent to a `.buildingFootprint` tile — the literal, black-box statement of the AC.

**Changes (test-only, 1 file):**
- `CyberpunkMonsterCrawlTests/CityLatticeGeneratorTests.swift`: add one new test that:
  - Sweeps `CityLatticeGenerator.classify` over a wide tile range (e.g. -24...24 on both axes) across several seeds.
  - For every tile that classifies `.kerbSidewalk`, independently calls `classify` on all 8 surrounding neighbor coordinates and asserts at least one neighbor is `.buildingFootprint` — proving the AC ("no `.kerbSidewalk` tile unless adjacent to a `.buildingFootprint` tile") directly from real neighbor lookups, not from re-deriving `blockBorderedByEdge`'s formula.
  - Also asserts, for a swept set of street edges/corners known to border an empty-lot block (reusing `isEmptyLotBlock` only to pick fixture coordinates, not to compute the expected kind), that the resulting kind is `.asphalt`, never `.kerbSidewalk`.

**Tests:**
- New regression test added to `CityLatticeGeneratorTests.swift` per above — this is the "test that should have caught this bug" per the guiding principle, now verifying the AC in a implementation-independent (black-box) way.
- Confirm all existing `CityLatticeGeneratorTests` and `GroundTileRendererTests` invariants continue to pass unchanged (no production code touched).
- No new production files; `code_run_tests` is a no-op signal in this environment (native iOS toolchain unavailable), so correctness rests on the independent, from-first-principles manual proof plus the new black-box test's logic being self-consistent (it calls only public `classify`, no internal re-implementation).
