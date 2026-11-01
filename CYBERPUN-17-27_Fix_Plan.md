# CYBERPUN-17-27 — Fix plan

**Bug:** Road tiles look wrong because of yellow dash

## Root cause

GroundTileRenderer.configure(_:for:at:) unconditionally crops and assigns an atlas texture (via GroundTileCatalog.pixelRect/diamond) for every GroundTileKind, including .asphaltEastWest and .asphaltNorthSouth, which are backed by the atlas's laneEastWest/laneNorthSouth diamonds that contain the yellow divider-dash artwork; there is no branch that renders these two kinds as a plain color fill instead of the textured lane crop.

## Plan

## Fix Plan — CYBERPUN-17-27

**Root cause:** `GroundTileRenderer.configure(_:for:at:)` unconditionally crops and assigns an atlas texture (via `GroundTileCatalog.pixelRect(for:)`) for every `GroundTileKind`, including `.asphaltEastWest`/`.asphaltNorthSouth`. Those two kinds are backed by the atlas's `laneEastWest`/`laneNorthSouth` diamonds, which contain the yellow lane-divider dash art that reads wrong on-device. There is no branch rendering these two kinds as a flat fill.

**Changes:**
1. `CyberpunkMonsterCrawl/Sources/World/GroundTileRenderer.swift` — in `configure(_:for:at:)`, branch on `groundKind`:
   - For `.asphaltEastWest` / `.asphaltNorthSouth`: set `node.texture = nil`, `node.color = .black`, `node.colorBlendFactor = 1`, `node.size = pixelRect.size` (reuses the existing measured 96×60 footprint, so depth/position math is untouched).
   - For all other kinds: keep the current atlas-crop path (`AtlasSheet.groundTiles.sheet.texture(forPixelRect:)`, `node.texture`, `node.size = texture.size()`) unchanged.
   - `node.position`, the `DepthModel` zPosition assignment, and the trailing `PixelCrispness.apply(to: node)` call stay identical and outside the branch — they already apply correctly to a textureless color sprite since `PixelCrispness.apply` guards its texture-filtering checks with `if let texture = node.texture`.
   - `GroundTileCatalog`'s kind→diamond mapping is left untouched (still consumed for sizing), so `.junctionStopLine`, `.kerbSidewalk`, `.lot`, `.buildingFootprint` are visually unaffected — satisfying the "non-goal" acceptance criterion.

2. `CyberpunkMonsterCrawlTests/GroundTileRendererTests.swift`:
   - Update `test_everyProducedNode_isPixelCrisp` to only assert `filteringMode`/`usesMipmaps` `if let texture = node.texture` (asphalt nodes now legitimately have `nil` texture); whole-number scale/position checks still run unconditionally.
   - Add a new regression test, e.g. `test_asphaltKinds_renderAsSolidBlackFill_withNoTexture`, that builds nodes for `.asphalt` at the two coordinates already proven (by existing tests) to map to `.asphaltNorthSouth` (tileX:4, tileY:0) and `.asphaltEastWest` (tileX:0, tileY:4), and asserts `node.texture == nil`, `node.color == .black`, `node.colorBlendFactor == 1`, and `node.size == GroundTileCatalog.pixelRect(for: kind).size`.

**No changes needed** to `GroundTileCatalog.swift`, `GroundTileCatalogTests.swift`, or `GroundTileSemanticsTests.swift` — the catalog's kind→diamond→pixelRect mapping is unchanged (still used for node sizing), so those tests continue to pass and accurately describe the (now render-unused-for-asphalt) atlas art data.

**Verification:** Since `code_run_tests` skips on this iOS repo, correctness rests on compiling the branch logic mentally against `SKSpriteNode` semantics (color-only sprites are a standard SpriteKit idiom) and the updated/added XCTest assertions, which the CI merge-gate will run for real.
