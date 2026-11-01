# CYBERPUN-17-26 — Fix plan

**Bug:** building sidewalks not rendered correctly

## Root cause

**Status: unresolved pending a product decision — see "Open question" below.** This is not a "no defect found" closure. The previous draft of this plan asserted no production defect existed and cited `docs/evidence`'s gate-04 city-read audit as independent corroboration; that citation does not hold up. Gate-04 explicitly disclaims being a visual/pixel comparison ("the literal side-by-side screenshot comparison ... remains a human/runtime-probe task"), and its "no offender found" for the lattice rests on the same `CityLatticeGeneratorTests`/`ConnectivityTests` suite the ticket was filed against — not an independent signal. The ticket is a screenshot report and that artifact has not yet been examined against a named tile coordinate.

What code reading *does* establish, concretely: `CityLatticeGenerator.classify` (via `streetTileKind`/`blockBorderedByEdge`) enforces that every street-band edge or lattice-crossing corner tile looks up the single block interior it borders and only emits `.kerbSidewalk` when that block is non-empty (`.buildingFootprint`); an edge/corner beside an empty `.lot` renders `.asphalt`. However, tracing the arithmetic for a lattice-crossing corner tile of built block `(b, c)` — tile `(6b+3, 6c+3)` — shows it borders that block's nearest interior tile `(6b+2, 6c+2)` **diagonally only**: all four of the corner tile's orthogonal neighbours are themselves street tiles (never `.buildingFootprint`). In the isometric projection those two diamonds meet at a single point, which is a plausible match for the ticket's "floating sidewalk square" / "ONLY supposed to hug the perimeter" wording, if "adjacent" is read as edge-sharing rather than including diagonal touch.

### Open question (needs a human/product call, see ticket discussion)

Is a lattice-crossing corner's diagonal-only touch to its building the intended visual design (sidewalks wrap corners), or is it the reported defect (a sidewalk tile must always edge-share with a building, never only corner-touch it)? This determines what ships:
- If diagonal corner-touch is intended: document it explicitly here and in the ticket, and the 8-connectivity regression test is correct as the acceptance check.
- If it is the defect: `blockBorderedByEdge`/`streetTileKind` needs a production change so a lattice-crossing corner tile renders `.asphalt` (not `.kerbSidewalk`) when its only bordering building contact is diagonal, and the regression test must assert 4-connectivity (edge-sharing), not 8.

The remaining coverage gap identified by the original draft still stands independent of the above: existing pre-PR tests re-derive the same internal block-arithmetic the generator uses rather than independently verifying, tile-by-tile via classify() on actual neighboring tiles, that no .kerbSidewalk tile is emitted without a true .buildingFootprint neighbor — the literal, black-box statement of the ticket's acceptance criteria.

## Plan

(See "Root cause" above for the unresolved open question this plan depends on. The regression test below locks in 8-connectivity as the acceptance definition; if the open question resolves the other way, this test must change to 4-connectivity and a production fix is needed in `blockBorderedByEdge`/`streetTileKind`.)

**Changes (test-only, 1 file):**
- `CyberpunkMonsterCrawlTests/CityLatticeGeneratorTests.swift`: add one new test that:
  - Sweeps `CityLatticeGenerator.classify` over a wide tile range (e.g. -24...24 on both axes) across several seeds.
  - For every tile that classifies `.kerbSidewalk`, independently calls `classify` on all 8 surrounding neighbor coordinates and asserts at least one neighbor is `.buildingFootprint` — proving the AC ("no `.kerbSidewalk` tile unless adjacent to a `.buildingFootprint` tile") directly from real neighbor lookups, not from re-deriving `blockBorderedByEdge`'s formula.
  - The empty-lot-block / never-kerb half of the AC is already covered by the existing `test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState`, which asserts the strictly stronger `XCTAssertEqual(kind, .asphalt)` over the same ring coordinates across a wider seed sweep — a separate, weaker duplicate test was removed rather than added, to avoid two places to update.

**Tests:**
- New regression test added to `CityLatticeGeneratorTests.swift` per above — this is the "test that should have caught this bug" per the guiding principle, now verifying the AC in an implementation-independent (black-box) way. Its compile-breaking closure-destructuring bug (`contains { dx, dy in ... }`, invalid in Swift 4+) has been fixed to `contains { offset in ... offset.0 ... offset.1 ... }`.
- Confirm all existing `CityLatticeGeneratorTests` and `GroundTileRendererTests` invariants continue to pass unchanged (no production code touched pending the open question above).
- No new production files; `code_run_tests` is a no-op signal in this environment (native iOS toolchain unavailable), so correctness rests on the independent, from-first-principles manual proof plus the new black-box test's logic being self-consistent (it calls only public `classify`, no internal re-implementation). A real build/compile check is still needed before merge, since neither test has been built in this environment.
