# CYBERPUN-17-28 — Fix plan

**Bug:** road and sidewalk rendering still wrong

## Root cause

In CityLatticeGenerator.streetTileKind, (1) the "lane mouth" tiles of a lattice crossing (one axis on the driving lane, the other on a band edge) are explicitly classified as .junctionStopLine, which renders the atlas's striped "intersection" texture untinted (the CYBERPUN-17-27 fix only tinted .asphalt tiles black, not .junctionStopLine) — producing the reported yellow/striped tiles. (2) The crossing-corner case (both axes on band edges, i.e. neither is the lane) decides .kerbSidewalk vs .asphalt via blockBorderedByEdge, which combines both axes' offsets to pick the single block the corner touches only *diagonally*; all four of a corner tile's true orthogonal (edge-sharing) neighbors are themselves street tiles, never .buildingFootprint, so a corner can never be truly edge-adjacent to a building. Using this diagonal-only check instead of real 4-connectivity causes sidewalk tiles to render around corners that only touch a building's block diagonally (or none at all), producing the reported floating/cornering grey sidewalk squares.

## Plan

## Fix Plan — CYBERPUN-17-28

**Root cause:** `CityLatticeGenerator.streetTileKind`'s lattice-crossing branch has two defects:
1. Lane-mouth tiles (one axis on the driving lane, the other on a band edge) are classified `.junctionStopLine`, which renders the atlas's untinted striped "intersection" texture — the CYBERPUN-17-27 fix only black-tints `.asphalt`, not `.junctionStopLine` — producing the reported yellow-line tiles.
2. Corner tiles (both axes on a band edge) decide `.kerbSidewalk` via `blockBorderedByEdge`, which picks the bordering block using a *diagonal-only* offset. Every orthogonal (true edge-sharing) neighbor of a corner tile is itself a street tile, never `.buildingFootprint`, so a corner can never be genuinely edge-adjacent to a building — yet the current code still kerbs it, producing the reported floating/cornering grey sidewalk squares around an empty center.

**Changes:**
- `CyberpunkMonsterCrawl/Sources/World/CityLatticeGenerator.swift`: collapse the `isStreetX && isStreetY` crossing branch so lane-mouth and corner cases both return `.asphalt` (drop the `.junctionStopLine` return and the corner's `blockBorderedByEdge`-driven `.kerbSidewalk` check; remove the now-dead `xIsLane`/`yIsLane` locals). `blockBorderedByEdge` remains used by the straight-corridor-edge case below, which is already correct (its single-axis offset lands on a genuinely edge-adjacent block-interior tile).
- `CyberpunkMonsterCrawl/Sources/World/TileKind.swift`: trim the `.kerbSidewalk` doc's claim that it includes "corner tiles of a lattice crossing," and note `.junctionStopLine` is no longer emitted by the generator (case kept for the enum's `CaseIterable`/catalog contract, just unused going forward) — doc-only, no behavior change.
- `CyberpunkMonsterCrawlTests/CityLatticeGeneratorTests.swift`: update `test_classify_crossing_pinsCentreLaneMouthAndCornerSubKinds`'s `expectedKind` to assert `.asphalt` for every crossing position (mouth and corner alike), dropping its now-unneeded block-lookup helper; tighten `test_everyKerbSidewalkTile_hasAnActualBuildingFootprintNeighbor_acrossManySeeds`'s `neighborOffsets` from 8-connectivity to true 4-connectivity (orthogonal only), resolving the open question left by CYBERPUN-17-26 in favor of "edge-share required"; add a small new regression asserting `classify()` never returns `.junctionStopLine` across a wide tile/seed sweep.

**Tests:** The updated/added `CityLatticeGeneratorTests` cases are exactly "the test that should have caught this bug" — they independently sweep real tile coordinates/neighbors via the public `classify()` API (no re-derivation of internal block arithmetic) and will fail against the old code, pass against the fix. No renderer/catalog changes needed: `GroundTileRenderer` already maps `.asphalt` to the black-tinted texture, so removing `.junctionStopLine`/diagonal-kerb emission alone eliminates both reported visual defects.
