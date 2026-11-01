# CYBERPUN-17-30 — Fix plan

**Bug:** Sidewalk tiles around buildings should include corner tiles

## Root cause

CityLatticeGenerator.streetTileKind's lattice-crossing corner branch (CYBERPUN-17-28) unconditionally returns .asphalt for every corner position in a 3x3 crossing, and GroundTileRenderer fully black-tints every .asphalt tile (CYBERPUN-17-27). So a corner diagonally adjacent to a building footprint renders as a solid black square instead of any sidewalk-reading surface — the reported "black corner" defect. 17-28 deliberately enforced this because .kerbSidewalk's invariant (verified by a dedicated test sweep) requires TRUE 4-connected (edge-sharing) adjacency to a .buildingFootprint tile, which a lattice-crossing corner can never have (it only touches its nearest block diagonally). Fixing the visual gap without reverting that invariant requires a new, semantically distinct tile kind for the diagonal corner-wrap case (not .kerbSidewalk), threaded through TileKind (new case + isWalkable), CityLatticeGenerator (new corner sub-branch keyed off the same diagonal blockBorderedByEdge lookup, but naming a different kind), GroundTileKind/GroundTileCatalog (new ground-kind, and since the shipped ground atlas (tileset_ground, 592x60px) contains exactly 6 measured diamonds with no spare art for a 7th "corner" graphic, the only asset-honest option is to deliberately reuse the existing kerbTransition diamond's pixel rect for the new kind, which several exhaustive 1:1 "no-duplicate-rect" catalog tests will need to be consciously updated to allow), and GroundTileRenderer (map the new kind to the un-tinted kerb render path, not the asphalt black-tint path).

## Plan

## Fix Plan — CYBERPUN-17-30

**Root cause:** `CityLatticeGenerator.streetTileKind`'s lattice-crossing corner branch (CYBERPUN-17-28) unconditionally returns `.asphalt`, which `GroundTileRenderer` fully black-tints — so a corner diagonally adjacent to a building renders as a solid black square instead of sidewalk. That branch can't simply emit `.kerbSidewalk` again: a dedicated test sweep (`test_everyKerbSidewalkTile_hasAnActualBuildingFootprintNeighbor_acrossManySeeds`) pins `.kerbSidewalk` to require *true* edge-sharing (4-connected) adjacency to a `.buildingFootprint`, which a crossing corner — which only ever touches its nearest block diagonally — can never have. The shipped ground atlas (`tileset_ground`, 592×60px) also has exactly 6 measured diamonds, fully consumed, so there is no spare art for a genuinely new corner graphic.

**Changes:**
1. `TileKind.swift`: add `.cornerSidewalk` case (walkable), documented as the diagonal lattice-crossing-corner-wrap case, distinct from `.kerbSidewalk`'s edge-adjacency contract.
2. `CityLatticeGenerator.swift`: in `streetTileKind`'s `isStreetX && isStreetY` branch, split out the true-corner sub-case (both band positions ≠ 1, i.e. neither is the lane) from the mouth/centre sub-case (which stays `.asphalt`). For a true corner, reuse the existing `blockBorderedByEdge` diagonal lookup and return `.cornerSidewalk` when it resolves to `.buildingFootprint`, else `.asphalt`.
3. `GroundTileCatalog.swift`: add `GroundTileKind.cornerSidewalk`, deliberately mapped to the same `AtlasGroundDiamond.kerbTransition` rect as `.kerbSidewalk` (documented reuse — no new art exists).
4. `GroundTileRenderer.swift`: map `TileKind.cornerSidewalk` → `GroundTileKind.cornerSidewalk`; it already falls into `configure`'s un-tinted `default` render path (no asphalt black-tint).

**Tests:**
- `CityLatticeGeneratorTests.swift`: update `test_classify_crossing_pinsCentreLaneMouthAndCornerSubKinds` so `expectedKind` depends on the bordered diagonal block's state at true-corner positions (`.cornerSidewalk` vs `.asphalt`), not a blanket `.asphalt`; update `test_classify_sidewalkRingAroundABlockInterior_matchesItsOwnBuildingFootprintState`'s corner expectation similarly; add a new regression sweep (`test_everyCornerSidewalkTile_hasADiagonalBuildingFootprintNeighbor_acrossManySeeds`) — the test that should have caught this bug — independently verifying via `classify()` that every `.cornerSidewalk` tile has a true diagonal `.buildingFootprint` neighbor and every lattice corner beside an empty-lot diagonal still reads `.asphalt`.
- `TileWalkabilityTests.swift`: add `.cornerSidewalk` to the per-case walkability assertions.
- `GroundTileCatalogTests.swift` / `GroundTileRendererTests.swift` / `GroundTileSemanticsTests.swift`: consciously update the "exactly 6 kinds / all rects distinct / all fingerprints distinct" assertions to allow the one intentional `.kerbSidewalk`/`.cornerSidewalk` → `kerbTransition` reuse, and add mapping coverage for the new kind.
