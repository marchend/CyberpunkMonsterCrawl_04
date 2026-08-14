# CyberpunkMonsterCrawl

## Overview

A portrait-and-landscape iOS survivor game: the player runs through an
endless, procedurally generated neon city, auto-firing at raccoon swarms
and surviving as long as possible. Visual direction is "Pixel Grit" —
gritty, high-contrast neon cyberpunk pixel art. This is a rebuild of a v1
that shipped unplayable (empty asset catalog, world rendering over the UI)
while all unit tests passed — this codebase is structured to make both
failure classes structurally hard to repeat.

## Tech stack

- Swift, iOS 17+ deployment target
- SpriteKit for the 2D scene graph and rendering (no third-party engine)
- UIKit app delegate hosting a single `SKView` — no SwiftUI in the render
  path, for direct control over drawable scale and pixel-crisp placement
- XCTest for unit tests
- XcodeGen (`project.yml`) generates the `.xcodeproj` — never hand-edit
  `project.pbxproj`

## Run locally

```
./setup.sh
```
Installs XcodeGen if missing, runs `xcodegen generate`, opens the project
in Xcode. Manual fallback: `brew install xcodegen && xcodegen generate`.
Build/run the `CyberpunkMonsterCrawl` scheme on a simulator.

## Run tests

Cmd+U in Xcode on the `CyberpunkMonsterCrawl` scheme, or:
```
xcodebuild test -scheme CyberpunkMonsterCrawl
```

## Directory structure

```
project.yml                          XcodeGen spec (app + test targets)
setup.sh, .gitignore
CyberpunkMonsterCrawl/
  AppDelegate.swift, SceneDelegate.swift   UIKit scene wiring
  GameViewController.swift                 composition root: hosts the SKView, builds GameScene, registers all four screens, presents it
  GameStateMachine.swift                   menu/gameplay/death/highScores GKStateMachine wrapper
  GameScene.swift                          three persistent layers (worldLayer/effectsLayer/uiLayer), state-driven screen registry, UI-first touch dispatch
  Layers/LayerConstants.swift              named zPosition bands enforcing worldLayer < effectsLayer < uiLayer
  Layers/ScreenNode.swift                  ScreenNode protocol + PlaceholderScreenNode test double
  Layers/TouchResponder.swift              touch-consumer protocol + the "scene is the sole dispatcher" contract
  Layers/ButtonNode.swift                  minimal tappable button (plate + label, optional neon accent frame) delivered to via TouchResponder
  Layers/SceneInvariants.swift             runtime audits: cumulative-z band escapes, nodes bypassing scene touch dispatch
  Layers/PixelGritPalette.swift            shared dark-background / neon-accent colors for every screen
  Layers/SKNodeAccessibilityIdentifier.swift  Swift-side accessibilityIdentifier storage for SKNode (SKNode never adopts UIAccessibilityIdentification); AccessibleSKView is what carries the value into a real accessibility element, and only for nodes under uiLayer in an AccessibleSKView-hosted scene - world/effects-layer identifiers stay invisible to XCUITest
  Layers/AccessibleSKView.swift            the hosted SKView subclass: publishes one UIAccessibilityElement per accessible uiLayer node, with a screen-space accessibilityFrame derived from the same coordinate path routeTouch(at:) hit-tests, so identifier/element-driven taps (XCUITest, the runtime probe, VoiceOver) land on the button instead of missing it
  Screens/MenuScreenNode.swift             the menu: title + neon PLAY button + placeholder HIGH SCORES entry, registered for .menu
  Screens/GameplayScreenNode.swift         skeleton .gameplay screen; no full-bleed backdrop so world touches fall through; SCAFFOLDING(CYBERPUN-17-7) placeholder content
  Screens/DeathScreenNode.swift            skeleton .death screen; real RUN AGAIN / back-to-menu buttons, SCAFFOLDING(CYBERPUN-17-16) placeholder run-summary content
  Screens/HighScoresScreenNode.swift       skeleton .highScores screen; real back-to-menu button, SCAFFOLDING(CYBERPUN-17-16) placeholder scores content
  PrivacyInfo.xcprivacy, *.entitlements
  Assets.xcassets/                         the single asset catalog for the target
    Atlas/                                 10 atlas-sheet imagesets (1x only)
    Buildings/                             12 building-sprite imagesets, building_00...building_11 (1x only)
    AppIcon.appiconset/                    stub AppIcon slot (art not yet imported)
  Sources/Assets/TextureLoading.swift      centralized nearest-filtering texture factory
  Sources/Assets/SpriteSheet.swift         measured-geometry contract: pixel/cell size, texture(col:row:)
  Sources/Assets/AtlasSheet.swift          the 10 sheet declarations + tileset_ground's 6 diamond sub-rects
  Sources/Assets/AtlasCellIndex.swift      one owning cell-index list per sheet family
  Sources/Assets/BuildingSprite.swift      manifest of the 12 building ids: measured size, footprint, height class
  Sources/Rendering/GroundTileCatalog.swift  GroundTileKind (the ground plane's own 6-case vocabulary: 2 asphalt orientations, junction stop-line, kerb/sidewalk, lot, building-footprint overhang) mapped onto AtlasGroundDiamond — a semantic relabeling, not a re-measurement; AtlasSheet.swift stays the one source of truth for the pixel rects
  Sources/Rendering/PixelCrispness.swift   PixelCrispness.apply(to:): the shared SKSpriteNode finalizer — .nearest filtering/no mipmaps, whole-integer xScale/yScale, position snapped to the nearest whole point — every future sprite consumer (buildings, actors, bullets, ...) goes through this, not just ground tiles
  Sources/World/IsometricProjection.swift  tileToScreen/screenToTile at 96x48 tile size, TilePoint tile-space type, tile(containing:) diamond-ownership rule floor(coord + 0.5) with both a screen-space and a tile-space overload so no call site re-derives it; Double math with a CGFloat cast only at the boundary
  Sources/World/DepthModel.swift           single source of truth for painter's-algorithm zPosition: band(forTile:) = -(tileX+tileY)*10, groundZPosition = band - 5000, buildingContentRange (<+3) / actorOffsetRange (6.5-9.9) in-band slots, band(forActorAt:) rounds a fractional TilePoint to its owning tile (discontinuous by design) via IsometricProjection.tile(containing:)
  Sources/World/GroundTileRenderer.swift   maps a TileKind + TileCoordinate to a pixel-crisp SKSpriteNode: GroundTileCatalog for the crop rect (re-deriving .asphalt's corridor orientation, north-south vs east-west, from the tile coordinate's lattice-band position — TileKind alone doesn't carry it), IsometricProjection for screen position, DepthModel.groundZPosition + worldLayerRelativeZ for zPosition, PixelCrispness.apply for the finishing pass. Every produced node is meant as a direct child of GameScene.worldLayer
  Sources/World/SeedMixer.swift            explicit splitmix64-style bit mixer over (seed, tileX, tileY), wrapping arithmetic only - never Hasher/.hashValue, which is randomized per process
  Sources/World/WorldSeed.swift            thin UInt64-wrapping per-run seed type: "a run is fully described by its seed"
  Sources/World/TileKind.swift             asphalt/junctionStopLine/kerbSidewalk/lot/buildingFootprint + isWalkable (asphalt, sidewalk, stop-line and empty lot walkable; building footprint solid). An empty .lot never turns solid - buildings are placed on the already-solid .buildingFootprint interiors (Chunk.placementSurface)
  Sources/World/CityLatticeGenerator.swift pure classify(tileX:tileY:seed:) -> TileInfo: 6-tile period, 3x3 block + 3-tile street corridor, intersections structurally always street (seed never reaches street tiles), ~1-in-4 empty-lot decision made once per block via SeedMixer
  Sources/World/Chunk.swift                 8x8 tile data container (ChunkCoordinate origin, tiles[[TileInfo]]) + building-footprint reservation: placementSurface pins .buildingFootprint (never the deliberately empty .lot) as the surface, reservableFootprints(in:)/reserve(footprint:at:) refuse overlapping 1x1/2x2 footprints; LotReservationStore holds the state above the chunk cache so it survives eviction
  Sources/World/ChunkGenerator.swift        generate(chunkCoordinate:seed:reservations:) -> Chunk, calling classify once per tile in the chunk's own 8x8 world-tile footprint, no cross-chunk lookups
  Sources/World/ChunkStreamingManager.swift camera-driven resident-chunk window: updateCamera(worldPosition:) loads/evicts chunks within a fixed Chebyshev radius (3, sized from the worst-case 24-tile margin via coversViewport) of the camera's chunk, using IsometricProjection.tile(containing:) for camera tile ownership; owns the world's LotReservationStore; SpriteKit-free (plain TilePoint input) so it's unit-testable without a scene
CyberpunkMonsterCrawlTests/
  CyberpunkMonsterCrawlTests.swift         proof-of-life (GameViewController)
  IsometricProjectionTests.swift           round-trip sweep (-50...50, both axes, incl. negatives) over tileToScreen/screenToTile + off-centre and on-seam cases pinning tile(containing:), plus the tile-space overload agreeing with the screen-space one across an off-centre sweep (7.6 -> tile 8, not 7)
  CityLatticeGeneratorTests.swift          6-tile period test, intersection-always-street test, ~1-in-4 empty-lot-ratio test, per-block decision consistency, determinism
  ConnectivityTests.swift                  flood-fill over classify's walkable output across >=20 seeds and a 12x12-block region, reaching every intersection tile; private BFS helper over a Set<Coord>
  ConcurrencyDeterminismTests.swift        dispatches classify for the same and for many distinct (tileX, tileY, seed) inputs across DispatchQueue.concurrentPerform and asserts every result matches a single-threaded reference
  ChunkGeneratorTests.swift                chunk-boundary agreement vs standalone classify at chunk edges across multiple chunk pairs (AC2), footprint-reservation no-overlap tests (2x2 overlaps refused, disjoint reservations still allowed), placement-surface polarity in both directions (street and empty .lot refused, building-block interior offered) and reserved footprints solid with no TileKind transition
  ChunkStreamingManagerTests.swift         resident-chunk count stays within the fixed window across a long straight sweep and a diagonal sweep (AC8); an evicted-then-revisited chunk regenerates identically to pure ChunkGenerator/classify output; a reservation survives eviction/revisit and is still refused a second time; worst-case viewport coverage in both orientations (with an anti-vacuity guard); camera tile ownership follows IsometricProjection's pinned rule, not floor
  DepthModelTests.swift                    ground == band - 5000 swept across a wide band range (AC2); band formula + buildingContentRange/actorOffsetRange bounds (AC3); rounded (not continuous) actor band resolution incl. the rounding seam and cross-reference with LayerConstants.worldMaxZ (AC4)
  TextureLoadingTests.swift                nearest-filtering assertion for TextureLoading
  ImagePixelSampling.swift                 shared alpha/RGBA decode helper for the asset gates
  AtlasCatalogTests.swift                  catalog-existence + alpha-channel gate for the 10 atlas sheets
  AtlasDimensionsTests.swift               measured-vs-declared dims + cell-alignment gate
  AtlasCellIndexTests.swift                bounds-checks every owned cell index (incl. ground diamonds)
  AtlasGroundDiamondTests.swift            derives tileset_ground's 6 seams from pixel alpha (5x96+112)
  BuildingCatalogTests.swift               building catalog existence + distinctness gate (12 buildings)
  BuildingSpriteTests.swift                per-building table contract: measured size, footprint, height class
  AtlasContractConventionTests.swift       scans the app target for raw texture-crop rects outside the contract
  AtlasCatalogNoExtraneousAssetsTests.swift whole-catalog scan: no stray @2x/@3x, no tileset_structure/preview art
  DocumentationParityTests.swift           AGENT.md and CLAUDE.md must stay byte-identical
  GameStateMachineTests.swift              exhaustive legal/illegal transition matrix for GameStateMachine
  LayerOrderingTests.swift                 zPosition ordering invariant (named constants) + hostile out-of-band descendants caught by the band audit
  TouchRoutingTests.swift                  UI-first touch routing: an overlapping UI node always wins over a world node
  TouchDispatchTests.swift                 the routed touch is delivered to a TouchResponder; no node bypasses scene dispatch
  GameSceneScreenSwitchingTests.swift      state-machine-driven screen registry swap incl. replace-while-active, using PlaceholderScreenNode doubles
  GameViewControllerCompositionTests.swift composition root builds GameScene, mounts MenuScreenNode + the three skeleton screens, wires PLAY to the state machine, and hosts the scene in an AccessibleSKView (asserted against the view actually installed in the hierarchy)
  AccessibleSKViewTests.swift              the accessibility-frame regression guard: the uiLayer accessible-node walk, and the published frame's centre being the exact scene point routeTouch(at:)/dispatchTouch(atScenePoint:) resolves to the PLAY button
CyberpunkMonsterCrawlUITests/
  CyberpunkMonsterCrawlUITests.swift       menu present + PLAY hittable + tapping it starts a run and lands on the gameplay screen
  AppLaunchAndRotationUITests.swift        launch shows the menu in portrait, rotation re-lays it out in landscape with nothing off-screen, PLAY dismisses the menu
docs/bootstrap.md                          original spec (source of truth)
.mothership/journeys/menu-to-gameplay.json product-verification journey: launch -> tap PLAY by accessibility element -> screenshot the streamed ground plane
```

> `AGENT.md` and `CLAUDE.md` are the same document under two names. Every edit
> must land in both, byte for byte — `DocumentationParityTests` fails the suite
> if they ever diverge, so the two cannot drift into disagreeing instructions.

## Planned architecture (from docs/bootstrap.md)

- UIKit + single `SKView` host (implemented in this PR)
- `GameViewController` presents `GameScene` directly (the bootstrap
  `BootScene` smoke scene has been removed now that a real menu exists)
- Atlas contract type for the 10 sheet families
  (`CyberpunkMonsterCrawl/Sources/Assets/SpriteSheet.swift` +
  `AtlasSheet.swift` + `AtlasCellIndex.swift`) recording each sheet's declared
  pixel size, cell grid and owned cell indices — checked at init time against
  what the imported image actually measures
  (`SpriteSheet.measuredPixelSize(forImageNamed:)`), never inferred from
  filenames, with a hard `precondition` failure on any mismatch. One owning
  cell-index list per family lives in `AtlasCellIndex`, including
  `tileset_ground`'s six non-uniform diamond sub-rects (declared in
  `AtlasSheet.swift` as `AtlasGroundDiamond`). That `5×96 + 112` partition is
  not left as prose: `AtlasGroundDiamondTests` re-runs the alpha scan at test
  time and pins the documented content bounding box, the gap-free tiling of
  the measured sheet width, and each sub-rect holding its own centred diamond
  — so a wrong partition fails rather than merely staying inside the sheet
  bounds. `AtlasContractConventionTests` greps the whole
  `CyberpunkMonsterCrawl/` target (not just `Sources/`, so the root scene
  files are covered; `…Tests` dirs excluded) and fails if any file outside
  those three crops a texture with a rect of its own — `SKTexture(rect:` and
  `textureRect` outright, `CGRect(` only in texture-cropping context so HUD
  and viewport layout cannot erode the gate through exemptions (implemented)
- Asset catalog: the 10 atlas sheets are imported as 1× imagesets under
  `CyberpunkMonsterCrawl/Assets.xcassets/Atlas/`, and every one is referenced
  by `AtlasSheet.allCases`, so renaming or dropping an imageset — or shipping
  one without an alpha channel, which `AtlasCatalogTests` measures off
  `CGImage.alphaInfo` because the pack is specified as PNG-32 — turns the
  suite red today, unmuted (implemented). There is one asset catalog in the
  target; the AppIcon stub lives in it rather than in a second same-named
  catalog. The 12 building sprites (`building_00` … `building_11`) are
  imported as 1× imagesets under `Assets.xcassets/Buildings/`, loaded whole
  (never sliced) via `TextureLoading`; `BuildingSprite` records each one's
  measured pixel size, world-grid footprint and height class from the
  story's table, `BuildingCatalogTests` gates catalog presence and building
  distinctness (no duplicate or horizontally-mirrored art), and
  `BuildingSpriteTests` pins the per-building table contract (implemented).
  `AtlasCatalogNoExtraneousAssetsTests` scans the whole catalog (atlas +
  buildings) and fails if any imageset declares a `2x`/`3x` rendition or if
  `tileset_structure`/the Asset-Scales-preview art was ever imported
  (implemented)
- Central texture loader (`CyberpunkMonsterCrawl/Sources/Assets/TextureLoading.swift`)
  enforcing `.nearest` filtering, no mipmaps (implemented — asset-import PR).
  No production consumer calls it yet; that lands with the sprites/tiles that
  actually render (future PRs)
- `menu → gameplay → death → highScores` state machine: `GameStateMachine`
  wraps `GKStateMachine` with `MenuState`/`GameplayState`/`DeathState`/
  `HighScoresState` `GKState` subclasses encoding the legal transition table
  (menu→gameplay, menu→highScores, gameplay→death, death→gameplay [RUN
  AGAIN], death→menu, highScores→menu) and rejecting every other pair,
  exhaustively covered by `GameStateMachineTests`. The wrapper pushes every
  successful entry to an `onChange: ((GameState) -> Void)` hook (so a scene
  observes instead of polling `currentState`) and routes every rejected pair
  to `onIllegalTransition`, which defaults to an `os.Logger` warning in DEBUG
  so a mis-wired button that silently does nothing is visible in the
  simulator rather than at QA time (implemented; `GameScene` is its first
  production caller, and `GameViewController` presents `GameScene` with all
  four concrete screens registered — `MenuScreenNode` for `.menu`,
  `GameplayScreenNode` for `.gameplay`, `DeathScreenNode` for `.death` and
  `HighScoresScreenNode` for `.highScores` — so PLAY drives menu → gameplay,
  and RUN AGAIN / back-to-menu drive the remaining legal transitions, in a
  real build)
- Scene graph z-layering: `worldLayer < effectsLayer < uiLayer`, `uiLayer`
  pinned to the scene's camera with first refusal on every touch, backed by
  named `LayerConstants` and a state-driven `[GameState: ScreenNode]`
  registry that swaps the active screen in `uiLayer` on every
  `GameStateMachine` transition (implemented — `GameScene.swift`,
  `Layers/LayerConstants.swift`, `Layers/ScreenNode.swift`,
  `Layers/TouchResponder.swift`, `Layers/ButtonNode.swift`,
  `Layers/SceneInvariants.swift`, `Layers/PixelGritPalette.swift`,
  `Screens/MenuScreenNode.swift`, `Screens/GameplayScreenNode.swift`,
  `Screens/DeathScreenNode.swift`, `Screens/HighScoresScreenNode.swift`;
  `LayerOrderingTests`, `TouchRoutingTests`, `TouchDispatchTests`,
  `GameSceneScreenSwitchingTests` and `GameViewControllerCompositionTests`
  cover the ordering invariant, UI-first routing, actual touch delivery, the
  registry swap and the composition root respectively). Two contracts are
  enforced at runtime rather than by convention: cumulative `zPosition` must
  stay inside its layer's band for *every* descendant, and no node may set
  `isUserInteractionEnabled` (UIKit would deliver the touch before the
  scene's `touchesBegan` and bypass UI-first routing) — both audited by
  `GameScene.nodesEscapingTheirLayerBand()` /
  `nodesBypassingSceneTouchDispatch()` and asserted in DEBUG whenever a
  screen mounts, the scene is presented, or a touch is dispatched. A third
  rule is a screen-authoring convention rather than a runtime audit: a screen
  that is meant to sit *over* live world content (today only
  `GameplayScreenNode`) must not mount a node that blankets the viewport,
  because `routeTouch(at:)` returns any non-`uiLayer` hit before it looks at
  `worldLayer` — a full-bleed backdrop there would swallow every touch and
  paint over `worldLayer`. Menu/death/high-scores backdrops are full-bleed on
  purpose (they hide the world); the scene's own `backgroundColor` supplies
  the dark base behind gameplay
- Accessibility-driven touch targeting (implemented - `CYBERPUN-17-4-t5`):
  the app hosts `GameScene` in `AccessibleSKView`
  (`Layers/AccessibleSKView.swift`), which publishes one
  `UIAccessibilityElement` per accessible `uiLayer` node with an explicit
  screen-space `accessibilityFrame`. This exists because a *finger* tap always
  worked while an *element-driven* tap - XCUITest, the scripted runtime probe,
  VoiceOver - did not: such a driver resolves its touch point from
  `accessibilityFrame`, and SpriteKit's implicit `SKNode` accessibility support
  does not resolve a correct screen-space frame for a node under a camera
  transform, which every button is (`uiLayer` hangs off `cameraNode` so the UI
  stays camera-locked). The synthesized tap therefore missed PLAY,
  `touchesBegan(_:with:)` never ran, `transition(to: .gameplay)` never fired,
  and the runtime probe reported "tapped PLAY, screen stayed on the menu"
  while every unit test stayed green - the tests call
  `dispatchTouch(atScenePoint:)` directly and never go near a frame. The frame
  is derived through `GameScene.accessibilityFrameInScene(for:)`, the
  algebraic inverse of the `uiLayer.convert(_:from: self)` + `atPoint(_:)`
  walk `routeTouch(at:)` performs, then scene -> view
  (`SKView.convert(_:from:)`) -> window (`convert(_:to: nil)`), so the frame a
  driver aims at and the point the scene hit-tests cannot disagree.
  `AccessibleSKViewTests` asserts that agreement directly (the published
  frame's centre, routed back through `routeTouch(at:)`, resolves to the PLAY
  button and starts a run) and `GameViewControllerCompositionTests` pins the
  entry-point wiring - reverting `viewDidLoad()` to a plain `SKView` would
  leave this class fully tested and completely dead. `accessibilityElements`
  plus the older `accessibilityElementCount()` / `accessibilityElement(at:)` /
  `index(ofAccessibilityElement:)` triplet are all overridden from one source,
  because UIKit may reach for either container API and `SKView` ships its own.
  Elements are rebuilt on every query rather than cached, so a screen swap, a
  rotation or a camera move can never leave a stale frame behind - a stale
  frame is the same defect wearing a different hat
- Isometric coordinate transform: `IsometricProjection.tileToScreen`/
  `screenToTile` for 96×48 tile diamonds (`screenX = (tileX - tileY) * 48`,
  `screenY = (tileX + tileY) * 24`, and its exact algebraic inverse), Double
  arithmetic throughout with a single `CGFloat` cast at the boundary. Tile
  space has its own `TilePoint` value type so a screen-space `CGPoint` can't
  be fed to the forward transform, and `tile(containing:)` pins the
  diamond-ownership rounding rule (`floor(coord + 0.5)` — a point exactly on
  a seam belongs to the higher-index tile, identically on both sides of the
  origin, which `round()` would not do)
  (implemented — `Sources/World/IsometricProjection.swift`,
  `IsometricProjectionTests`). `GroundTileRenderer` / `GroundPlaneStreamer`
  (`CYBERPUN-17-4-t2`) are the first production consumers that place
  tile-space nodes through it. The seam epsilon lives on the *screen-space*
  overload only — `tileToScreen`/`screenToTile` round trips are what
  introduce the floating-point noise, so the fix sits at the cause and
  `tile(containing: TilePoint)` keeps the exactly half-open
  `[centre - 0.5, centre + 0.5)` region
- Depth module: painter's-algorithm bands `-(tileX+tileY)*10`, ground plane
  5000 below its own band, building content <+3 in-band, actor offsets
  6.5–9.9 sampling a rounded tile (implemented — `Sources/World/DepthModel.swift`,
  `DepthModelTests`; pure Swift, no rendering dependency — `CYBERPUN-17-4-t1`).
  The band formula is an *ordering* rule, not a zPosition on its own, so
  every value the module returns is anchored at `DepthModel.worldBaseZ` (the
  midpoint of `LayerConstants.worldBand`) and is an **absolute cumulative**
  zPosition — the value the layer-band audit sees after SpriteKit
  accumulates `zPosition` down the tree. A node parented directly under
  `worldLayer` therefore takes
  `DepthModel.worldLayerRelativeZ(forAbsoluteZ:)`, not the absolute value.
  Unanchored, `band((0,0))` would be `0` — above `worldMaxZ`, and at tile
  sums past `-100` above `uiMinZ` too, i.e. world content out-painting the
  UI. `DepthModel.maxSupportedTileSumMagnitude` is the derived
  `|tileX+tileY|` bound whose whole band (ground floor through actor
  ceiling) still fits inside `LayerConstants.worldBand`, and
  `DepthModelTests` sweeps that whole range, asserting containment through
  `DepthModel.isWithinWorldBand(_:)` — which delegates to the same inclusive
  `LayerConstants.worldBand` range `GameScene.nodesEscapingTheirLayerBand()`
  audits, so the unit test and the runtime audit cannot disagree. Ground
  clearance (`bandsClearedByGroundOffset`, 500 bands) is likewise asserted
  against the resident window's widest tile-sum spread, derived from
  `ChunkStreamingManager.residentRadius * Chunk.size`, rather than claimed
  in prose.
  Actor band resolution rounds a fractional `TilePoint` to its owning whole
  tile via the same `IsometricProjection.tile(containing:)` seam rule
  buildings use for their base tile, and is deliberately discontinuous (a
  step function of the rounded tile, never interpolated) — see the doc
  comment on `DepthModel.band(forActorAt:)` for why continuous depth would
  desync from building placement. `GroundTileRenderer` (`CYBERPUN-17-4-t2`)
  is the first production consumer of `DepthModel.groundZPosition` /
  `worldLayerRelativeZ`; building/actor consumers still land with
  `CYBERPUN-17-5` onward
- Ground-plane rendering + pixel crispness, the other half of
  `CYBERPUN-17-4` (implemented — `Sources/Rendering/GroundTileCatalog.swift`,
  `Sources/Rendering/PixelCrispness.swift`, `Sources/World/GroundTileRenderer.swift`;
  `GroundTileCatalogTests`, `GroundTileRendererTests` — `CYBERPUN-17-4-t2`):
  `GroundTileRenderer.node(for:at:)` maps a `TileKind` + `TileCoordinate` to a
  finished ground `SKSpriteNode` — `GroundTileCatalog`'s six-case
  `GroundTileKind` (two asphalt orientations, junction stop-line dash,
  kerb/sidewalk, lot, building-footprint overhang) picks the measured
  `AtlasGroundDiamond` sub-rect (re-deriving `.asphalt`'s corridor
  orientation from the tile coordinate's lattice-band position, since
  `TileKind` alone doesn't carry it), `IsometricProjection` places it on
  screen, `DepthModel.groundZPosition` + `worldLayerRelativeZ` set its
  `zPosition` for a direct child of `GameScene.worldLayer`, and
  `PixelCrispness.apply` finishes it (`.nearest` filtering, whole-integer
  scale, position snapped to a whole point, sign preserved so an
  `xScale = -1` mirror survives the clamp; `PixelCrispnessTests` covers that
  shared helper directly rather than only through the ground sweep).
  `GroundPlaneStreamer` (`Sources/World/GroundPlaneStreamer.swift`,
  `GroundPlaneStreamerTests`) is the **production mount**: it walks
  `ChunkStreamingManager`'s resident window and parents one ground node per
  resident tile *directly* into `GameScene.worldLayer` (no intermediate
  container, or its `zPosition` would shift the whole depth scheme), dropping
  a chunk's nodes when that chunk is evicted, and `GameScene` starts it on
  entry to `.gameplay` from `worldSeed` centred on `cameraWorldPosition`. So
  tapping PLAY in a real build shows the generated city rather than an empty
  scene, and the mounted node count stays bounded by the resident window
  however far the camera roams. **Every `updateCamera` call
  (`CYBERPUN-17-4-t4`) mounts only the
  `ChunkStreamingManager.quickstartRadius` ring synchronously** and queues
  everything beyond it in `pendingMountQueue`, drained a few chunks per
  call by `advanceIncrementalMount()` — which `GameScene.update(_:)` calls
  every frame, in Release builds too, not just DEBUG. This exists because the
  old code mounted the *entire* resident window (up to 3,136 `SKSpriteNode`s)
  synchronously inside the PLAY tap's own call stack, a stall long enough for
  a scripted runtime probe to catch the app before the first `.gameplay`
  frame had presented. The split is applied **per call, not just to the
  first**: `CYBERPUN-17-7`'s camera-follow calls `updateCamera` every frame,
  and an earlier revision that folded the whole deferred remainder into the
  second call would have reinstated the same single-frame mount one frame
  later. `quickstartRadius` is sized by the same measured
  `coversViewport(widthPoints:heightPoints:radius:)` arithmetic as
  `residentRadius` — radius 2 covers `phoneViewportPoints` (393×852pt
  portrait, the binding case since iso tiles are 2:1) and radius 1 does not,
  both pinned in `ChunkStreamingManagerTests` — so the ring that is *not*
  deferred is the part that may already be on screen. **What is deferred is
  mounting, not generation:** `ChunkStreamingManager.updateCamera` still
  generates the whole resident window (49 chunks and their
  `LotReservationStore` decisions) synchronously in the same call, so this
  removes the scene-graph half of the PLAY-tap stall only; anyone chasing a
  residual stall on entry to `.gameplay` should look at generation next.
  Which crop *is* the east-west lane is pinned
  by `GroundTileSemanticsTests`, which re-measures the shipped pixels (crop
  fingerprints must all differ; each lane crop's paint must be elongated
  along the tile axis its case name claims) - a swapped lane pair fails
  there, where a literal table compared against a copy of itself cannot see
  it. Buildings and actors are the world content that is still missing; they
  mount into the same `worldLayer`, alongside these ground nodes, with the
  building-placement / integration-checkpoint PRs (`CYBERPUN-17-5` onward).
  Nodes evicted from the resident window go into `GroundPlaneStreamer`'s
  recycle pool rather than being deallocated, and `unmountAll()` returns its
  nodes there too, so a restarted run re-mounts the window out of the pool;
  `GameScene.startGroundPlane()` keeps the existing streamer when `worldSeed`
  is unchanged (same seed = same city) and replaces it only when the seed
  changes, since a discarded streamer takes its pool with it
  (`ChunkStreamingGroundTests` pins both sequences)
- `GameScene` carries one `SCAFFOLDING(CYBERPUN-17-7)` artifact in
  production code: a debug camera pan (`debugPanEnabled`,
  `debugPanTilesPerSecond` and `advanceDebugPanIfNeeded`, all `#if DEBUG`
  and off by default) that exists only so multi-chunk streaming can be
  watched end-to-end during a manual run, since there is no camera-follow
  yet. `CYBERPUN-17-7` deletes the block when real player/camera movement
  lands. Deliberately **not** covered by any test, so removing it cannot
  mean deleting a green test. The `update(_:)` override that calls it is
  **not** part of that scaffolding (`CYBERPUN-17-4-t4`): it also drains
  `groundPlane`'s incremental-mount queue every frame, unconditionally, in
  Release builds too — that half is a correctness fix (see
  `GroundPlaneStreamer` above), so `CYBERPUN-17-7` must keep the override and
  delete only the `#if DEBUG` call inside it
- Pure-function per-tile world generation `(tileX, tileY, seed) → TileInfo`
  (implemented — `Sources/World/CityLatticeGenerator.swift`,
  `Sources/World/SeedMixer.swift`, `Sources/World/WorldSeed.swift`,
  `Sources/World/TileKind.swift`), wrapped into 8×8 chunks with
  camera-driven streaming and no cross-chunk neighbour lookups (implemented
  — `Sources/World/Chunk.swift`, `Sources/World/ChunkGenerator.swift`,
  `Sources/World/ChunkStreamingManager.swift`; `ChunkGeneratorTests`,
  `ChunkStreamingManagerTests`). CYBERPUN-17-3 was deliberately split in
  three: `-t1` shipped the isometric coordinate transform, `-t2` shipped the
  pure seeded city-lattice function, `-t3` wraps it into chunks and
  streaming. AC2 (chunk-boundary agreement) holds because `ChunkGenerator`
  calls `classify` per tile with no neighbour lookups — a chunk-embedded
  tile is identical to the same tile generated standalone by construction,
  which `ChunkGeneratorTests` pins directly. AC8 (bounded resident-chunk
  window) is enforced by `ChunkStreamingManager.residentRadius`, an
  explicit testable constant: a Chebyshev-radius window around the
  camera's current chunk, generated via `ChunkGenerator` as the camera
  approaches and evicted once outside it, so the resident count never
  exceeds `residentWindowSize` regardless of how far the camera roams.
  `residentRadius` is 3, sized from the *worst-case* margin
  (`residentRadius * Chunk.size` = 24 tiles — the camera may sit on its own
  chunk's edge, so its own chunk guarantees nothing), which keeps an
  iPad-sized landscape *and* portrait viewport inside the resident window;
  `ChunkStreamingManager.coversViewport(widthPoints:heightPoints:)` is that
  arithmetic and the tests assert it, so coverage is a checked fact rather
  than prose. Camera-to-tile ownership goes through
  `IsometricProjection.tile(containing:)` (tile-space overload) so the
  `floor(coord + 0.5)` rounding rule has exactly one home in the codebase.
  Building-footprint reservation (`Chunk.reservableFootprints(in:)` /
  `Chunk.reserve(footprint:at:)`) offers only `Chunk.placementSurface` —
  `.buildingFootprint`, the ~3-in-4 block interiors the lattice fills with
  buildings, never the ~1-in-4 `.lot` blocks the brief deliberately leaves
  empty — and refuses any footprint overlapping an existing reservation, so
  1x1/2x2 buildings placed by a later story (`CYBERPUN-17-5`) cannot collide
  with each other. Because the placement surface is already the not-walkable
  kind, a reserved footprint is solid by construction with no `TileKind`
  transition, and an empty `.lot` stays walkable forever. Reservation state
  lives in a manager-owned `LotReservationStore` held *above* the chunk
  cache, so it survives eviction/revisit: chunk tiles are re-derived by
  `classify`, but a reservation is a decision that cannot be re-derived.
  Two limits are accepted deliberately: `Chunk.size` (8) is not a multiple of
  the lattice period (6), so a 2x2 footprint straddling a chunk seam is never
  offered by either side (chunk-local generation is the stronger invariant),
  and nothing renders any of this yet. All three tasks of `CYBERPUN-17-3`
  (`-t1`/`-t2`/`-t3`) have landed, but no production consumer streams or
  draws chunks — treat it as shipped data-layer work awaiting the
  ground-plane/renderer story, not as a finished on-screen feature
- Building & rooftop-sign placement generation, pure logic, no SpriteKit
  (implemented — `Sources/World/BuildingCatalog.swift`,
  `BuildingFootprintReservation.swift`, `BuildingPlacement.swift`,
  `RooftopSignPlacement.swift`; `BuildingPlacementTests`,
  `BuildingFootprintOverlapTests`, `RooftopSignPlacementTests` —
  `CYBERPUN-17-5-t1`). `BuildingCatalog` restates `BuildingSprite`'s asset
  name/footprint/height-class table without importing SpriteKit, so the
  `World` layer stays SpriteKit-free. `BuildingPlacement.generate(forBlock:
  seed:)` walks a block's 3x3 interior in row-major order and, for a
  building block (`!CityLatticeGenerator.isEmptyLotBlock`), fills every lot
  with a seeded-hash-chosen building — a 2x2 pick that wouldn't fit falls
  back to a 1x1 from the same hash, so the interior always ends up fully
  covered; an empty-lot block gets `[]`. `BuildingFootprintReservation` is
  the per-block, per-call no-overlap grid the walk consults before
  committing each placement (independent of the world-lifetime
  `LotReservationStore`). `RooftopSignPlacement.generate(forBlock:
  placements:seed:)` runs on its own salted hash stream (~1-in-3 signed
  blocks) and only ever names a carrier lot that `placements` actually
  contains, returning `nil` unconditionally for an empty block.
  `ChunkGenerator.generate` aggregates both onto `Chunk.buildingPlacements`
  / `Chunk.roofSigns`, but only for blocks whose whole 3x3 interior is
  fully contained in that chunk
  (`BuildingPlacement.blockCoordinates(fullyContainedInChunk:)`) — the same
  no-cross-chunk-lookup limit `reservableFootprints(in:)` already accepts.
  Still nothing renders any of this; a later story mounts the records as
  sprites
- Tile-grid collision — no `SKPhysicsBody`; buildings are flat footprints
  on a tile grid (deferred — future PR; `TileKind.isWalkable` is the data
  this will consume)
- City lattice: 6-tile period per axis, 3×3 building block ringed by a
  3-tile street corridor that doubles as the navmesh, `TileKind` +
  walkability, ~1-in-4 empty lots, every intersection tile street under
  every seed (implemented — `CityLatticeGenerator.classify`). Street tiles
  are decided purely structurally from the tile coordinate's position in
  the 6-tile period (`SeedMixer` is never consulted for them), which is
  what makes "every intersection tile is street under every seed" true by
  construction and makes the lattice's connectivity seed-independent; only
  a block interior's lot-vs-building decision is seed-driven, made once per
  block via `SeedMixer` so every interior tile of one block agrees.
  `CityLatticeGeneratorTests` pins the period/intersection/ratio/
  determinism contracts (including the crossing's sub-kinds by name: centre
  lane asphalt, the four junction mouths stop-line, the four corners
  sidewalk so the ring around each block is unbroken), `ConnectivityTests`
  flood-fills the walkable output across >=20 seeds and a 12x12-block region
  straddling the origin and reaches every intersection tile, and
  `ConcurrencyDeterminismTests` proves thread safety.
  Chunk-boundary agreement (AC2) and the bounded resident-chunk window
  (AC8) are implemented in `CYBERPUN-17-3-t3` (`Sources/World/Chunk.swift`,
  `ChunkGenerator.swift`, `ChunkStreamingManager.swift`). AC2 holds because
  `classify` is a pure function of `(tileX, tileY, seed)` and consults no
  neighbour, chunk or cached state, so two chunks meeting at a boundary
  cannot disagree — AC2 is true by construction the moment chunking wraps
  `classify`, which is why `ChunkGeneratorTests`'s boundary-agreement test
  is a thin wrapper assertion (chunk-embedded tile == standalone `classify`
  tile) rather than a search for subtle bugs. AC8's bounded resident-chunk
  window was the real engineering in `-t3`, enforced by
  `ChunkStreamingManager.residentRadius` and proven by
  `ChunkStreamingManagerTests`'s long straight and diagonal camera sweeps.
  The same suite pins the two things the bound alone does not: worst-case
  viewport coverage (so "no chunk pops in at the viewport edge" is checked,
  not claimed) and reservation survival across eviction/revisit
- Local high-score persistence, no network/Game Center (deferred — future PR)
- `// SCAFFOLDING:` marker convention + grep-based removal gate
  (deferred — future PR)

## Deferred work

- Wiring every real texture consumer (player, raccoons, bullets, pickups,
  pulse, hit puff, signs, ground tiles, buildings) into an actual on-screen
  scene — `TextureLoading.texture(named:)` / `BuildingSprite.texture` exist
  and are tested, but no scene places any sprite yet (later PRs)
- Final gameplay HUD, death-screen run-summary rows and the high-scores list
  are explicitly out of scope for CYBERPUN-17-2 (see the story's "Out of
  scope" section) and remain marked `// SCAFFOLDING:` in
  `GameplayScreenNode` / `DeathScreenNode` / `HighScoresScreenNode` —
  navigation (PLAY, RUN AGAIN, back-to-menu) is real; the visual content is
  not. `GameplayScreenNode`'s placeholder is tagged for CYBERPUN-17-7 (the
  floating-thumbstick story); the death/high-scores placeholders are tagged
  for CYBERPUN-17-16 (integration checkpoint #2)
- Tile-grid collision system
- Local high-score persistence
- SCAFFOLDING marker grep gate
- Audio, app icon art, launch screen polish, App Store metadata/submission
- Game Center/online leaderboards, pause, settings, revives, manual weapon
  switching (weapons auto-progress per spec)

## Git Workflow

> **Default PR target branch: `develop`.** Every feature/refactor/docs PR
> opens against `develop`. PRs are only opened against `qa`, `uat`, or
> `main` for explicit promotion PRs.

**Branch model (`develop` → `qa` → `uat` → `main`):**

| Branch  | Role                                 | Receives PRs from              | Promotes to |
|---------|--------------------------------------|---------------------------------|-------------|
| develop | Default integration branch           | feature branches                | qa          |
| qa      | First quality gate                   | develop (promotion PR)          | uat         |
| uat     | Pre-prod acceptance                  | qa (promotion PR)               | main        |
| main    | Production / release tags            | uat (promotion PR)              | tagged only |

All feature PRs MUST target `develop`. Never open a feature PR against
`qa`, `uat`, or `main`. Promotions happen via dedicated promotion PRs.
