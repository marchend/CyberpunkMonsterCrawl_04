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
  GameScene.swift                          three persistent layers (worldLayer/effectsLayer/uiLayer), state-driven screen registry, UI-first touch dispatch; mounts the streamed ground plane + PlayerNode on entry to .gameplay, snapping the player's screen position via PixelCrispness.snappedPosition on every mount/reposition; mounts the floating thumbstick in uiLayer and routes touchesBegan/Moved/Ended/Cancelled to it (activeStickTouch); runs the per-frame run pipeline in advanceMovementAndCamera(currentTime:): thumbstick -> PlayerMovementController -> CollisionResolver -> PlayerNode position/depth/visual state -> CameraController (CYBERPUN-17-7). The SCAFFOLDING(CYBERPUN-17-7) PlayerScaffoldingDriver demo vector, its debugPlayerDemoEnabled flag and the debug camera pan are deleted
  Layers/LayerConstants.swift              named zPosition bands enforcing worldLayer < effectsLayer < uiLayer
  Layers/ScreenNode.swift                  ScreenNode protocol + ScreenStackLayout (the shared vertical stack both content screens lay out with: flexible title/rows even-spaced above a height-aware, bottom-pinned button block, so a 72pt RUN AGAIN and a 48pt BACK TO MENU cannot overlap in landscape) + PlaceholderScreenNode test double
  Layers/TouchResponder.swift              touch-consumer protocol + the "scene is the sole dispatcher" contract
  Layers/ButtonNode.swift                  minimal tappable button (plate + label, optional neon accent frame) delivered to via TouchResponder
  Layers/SceneInvariants.swift             runtime audits: cumulative-z band escapes, nodes bypassing scene touch dispatch
  Layers/PixelGritPalette.swift            shared dark-background / neon-accent colors for every screen
  Layers/SKNodeAccessibilityIdentifier.swift  Swift-side accessibilityIdentifier storage for SKNode (SKNode never adopts UIAccessibilityIdentification); AccessibleSKView is what carries the value into a real accessibility element, and only for nodes under uiLayer in an AccessibleSKView-hosted scene - world/effects-layer identifiers stay invisible to XCUITest
  Layers/AccessibleSKView.swift            the hosted SKView subclass: publishes one UIAccessibilityElement per accessible uiLayer node, with a screen-space accessibilityFrame derived from the same coordinate path routeTouch(at:) hit-tests, so identifier/element-driven taps (XCUITest, the runtime probe, VoiceOver) land on the button instead of missing it
  Screens/MenuScreenNode.swift             the menu: title + neon PLAY button + placeholder HIGH SCORES entry, registered for .menu
  Screens/GameplayScreenNode.swift         skeleton .gameplay screen; mounts no full-bleed backdrop and, since CYBERPUN-17-5-t4, no text of its own, and (since CYBERPUN-17-7-t5) no accessibility marker either — the streamed city + player render through it, world touches fall through, and the screen mounts no children at all until the real HUD (CYBERPUN-17-12) lands
  Screens/DeathScreenNode.swift            the real .death screen: eight RunScoreCalculator rows + RUN AGAIN / back-to-menu buttons, recorded into HighScoreStore once per willEnter() - and never when the run summary is nil (no run happened), so a -goto death launch cannot persist a fake score: 0 row; a swallowed record failure is logged via Sources/Diagnostics/GameLog.swift's GameLog.persistence
  Screens/HighScoresScreenNode.swift       the real .highScores screen: the persisted table rebuilt every willEnter(), the just-finished run highlighted by id, real back-to-menu button; an unreadable table still renders as the empty state but is now logged via GameLog.persistence rather than silently swallowed
  PrivacyInfo.xcprivacy, *.entitlements
  Assets.xcassets/                         the single asset catalog for the target: Atlas/ (10 atlas-sheet imagesets, 1x only), Buildings/ (12 building-sprite imagesets, building_00...building_11, 1x only)
    AppIcon.appiconset/                    stub AppIcon slot (art not yet imported)
  Sources/Abilities/PulseAbility.swift     CYBERPUN-17-10 PR 1: the pulse ability's pure, SpriteKit-free decision layer (the HUD button, ring and full scene wiring landed in -t2/-t3 — see Deferred work). Per-instance cooldown ticked down in update(deltaTime:); trigger(...) returns nil while on cooldown, else a Result carrying the level-scaled radius plus one Hit (raccoon, new tile position, damage, wasCrushed) per living in-radius raccoon. The push is CollisionResolver.resolve applied to the *raccoon*, out to radius + pushOvershootEpsilon along the ray from the player, so footprint clamping is never reimplemented here; "crushed" (the second damage die) means the *resolved* position is still inside the radius — not merely short of the push target, since CollisionResolver slides per axis and a raccoon deflected off a footprint edge but still shoved clear of the radius takes one die
  Sources/Progression/LevelScaling.swift   CYBERPUN-17-10 PR 1: the pulse's level-keyed scaling table, kept next to the XPLevelSystem counter it reads — pulseRadiusMultiplier(forLevel:) (1.0 below level 3, 1.25 at 3-5, a *compounding* 1.25 * 1.25 == 1.5625 at 6+, a tuning reading that still needs a human thumbs-up) and pulseDamageDie(forLevel:) (1d6 below level 6, 1d8 at 6+); out of XPLevelSystem so "which weapon tier is equipped" stays separate from "how strong is an unrelated ability"
  Sources/Actors/Direction8.swift          8-way facing bin from a movement vector, screen-space (from(vector:)) and SpriteKit-space (from(spriteKitVector:)) overloads, no player-specific coupling so a future raccoon sheet (CYBERPUN-17-8) bins against the same unmodified type
  Sources/Actors/PlayerAnimator.swift      pure walk-cycle frame-timing state machine (8fps, 4-frame cycle, frame 0 while idle)
  Sources/Actors/PlayerSpriteSheet.swift   measured Direction8 -> (row, mirrored) table, anchor point and 14x10 hitbox for sprite_player_walk
  Sources/Actors/PlayerNode.swift          SKNode assembling the cached-per-cell walk-cycle body + ActorShadowNode + facing/frame state machine; update(deltaTime:movementVector:) resolves facing/frame/mirror but never touches position itself
  Sources/Actors/ActorShadowNode.swift     reusable 2:1-ellipse actor shadow, z-ordered beneath the body, actor-agnostic (no PlayerSpriteSheet/Direction8 coupling) so future actors (raccoon swarm, CYBERPUN-17-8) reuse it unmodified
  Sources/Assets/TextureLoading.swift      centralized nearest-filtering texture factory
  Sources/Assets/SpriteSheet.swift         measured-geometry contract: pixel/cell size, texture(col:row:)
  Sources/Assets/AtlasSheet.swift          the 10 sheet declarations + tileset_ground's 6 diamond sub-rects
  Sources/Assets/AtlasCellIndex.swift      one owning cell-index list per sheet family
  Sources/Assets/BuildingSprite.swift      manifest of the 12 building ids: measured size, footprint, height class
  Sources/Rendering/GroundTileCatalog.swift  GroundTileKind (the ground plane's own 6-case vocabulary: 2 asphalt orientations, junction stop-line, kerb/sidewalk, lot, building-footprint overhang) mapped onto AtlasGroundDiamond — a semantic relabeling, not a re-measurement; AtlasSheet.swift stays the one source of truth for the pixel rects
  Sources/Rendering/PixelCrispness.swift   PixelCrispness.apply(to:): the shared SKSpriteNode finalizer — .nearest filtering/no mipmaps, whole-integer xScale/yScale, position snapped to the nearest whole point — every future sprite consumer (buildings, actors, bullets, ...) goes through this, not just ground tiles. snappedPosition(for:scale:) rounds a position to the nearest whole *device pixel* at an explicit scale (for a position derived through the camera's tile on entry to .gameplay; it snaps the node, not the camera - snapping cameraNode.position is CYBERPUN-17-7's, the ticket that first moves it), and isIntegerScale(_:) is the standalone whole-integer-scale predicate, both added in CYBERPUN-17-6-t3 and simulated at @2x/@3x in PixelCrispnessTests without a live UIScreen
  Sources/World/IsometricProjection.swift  tileToScreen/screenToTile at 96x48 tile size, TilePoint tile-space type, tile(containing:) diamond-ownership rule floor(coord + 0.5) with both a screen-space and a tile-space overload so no call site re-derives it; Double math with a CGFloat cast only at the boundary
  Sources/World/DepthModel.swift           single source of truth for painter's-algorithm zPosition: band(forTile:) = -(tileX+tileY)*10, groundZPosition = band - 5000, buildingContentRange (<+3) / actorOffsetRange (6.5-9.9) in-band slots, signContentOffset (+1, a rooftop sign's child zPosition stacked on the building content floor - owned here, never a literal at RooftopSignRenderer), band(forActorAt:) rounds a fractional TilePoint to its owning tile (discontinuous by design) via IsometricProjection.tile(containing:)
  Sources/World/GroundTileRenderer.swift   maps a TileKind + TileCoordinate to a pixel-crisp SKSpriteNode: GroundTileCatalog for the crop rect (re-deriving .asphalt's corridor orientation, north-south vs east-west, from the tile coordinate's lattice-band position — TileKind alone doesn't carry it), IsometricProjection for screen position, DepthModel.groundZPosition + worldLayerRelativeZ for zPosition, PixelCrispness.apply for the finishing pass. Every produced node is meant as a direct child of GameScene.worldLayer
  Sources/World/SeedMixer.swift            explicit splitmix64-style bit mixer over (seed, tileX, tileY), wrapping arithmetic only - never Hasher/.hashValue, which is randomized per process
  Sources/World/WorldSeed.swift            thin UInt64-wrapping per-run seed type: "a run is fully described by its seed"
  Sources/World/TileKind.swift             asphalt/junctionStopLine/kerbSidewalk/lot/buildingFootprint + isWalkable (asphalt, sidewalk, stop-line and empty lot walkable; building footprint solid). An empty .lot never turns solid - buildings are placed on the already-solid .buildingFootprint interiors (Chunk.placementSurface)
  Sources/World/CityLatticeGenerator.swift pure classify(tileX:tileY:seed:) -> TileInfo: 6-tile period, 3x3 block + 3-tile street corridor, intersections structurally always street (seed never reaches street tiles), ~1-in-4 empty-lot decision made once per block via SeedMixer
  Sources/World/Chunk.swift                 8x8 tile data container (ChunkCoordinate origin, tiles[[TileInfo]]) + building-footprint reservation: placementSurface pins .buildingFootprint (never the deliberately empty .lot) as the surface, reservableFootprints(in:)/reserve(footprint:at:) refuse overlapping 1x1/2x2 footprints; LotReservationStore holds the state above the chunk cache so it survives eviction
  Sources/World/ChunkGenerator.swift        generate(chunkCoordinate:seed:reservations:) -> Chunk, calling classify once per tile in the chunk's own 8x8 world-tile footprint, no cross-chunk lookups
  Sources/World/ChunkStreamingManager.swift camera-driven resident-chunk window: updateCamera(worldPosition:) loads/evicts chunks within a fixed Chebyshev radius (3, sized from the worst-case 24-tile margin via coversViewport) of the camera's chunk, using IsometricProjection.tile(containing:) for camera tile ownership; owns the world's LotReservationStore; SpriteKit-free (plain TilePoint input) so it's unit-testable without a scene
  Sources/World/IsometricDepthSorting.swift building-specific zPosition(forBuildingFarCornerTile:) on top of DepthModel: keys off the footprint's far corner (max tileX+tileY across footprintTiles), not the base/lot tile, placed at DepthModel.buildingContentRange's floor — so a building can never draw over an actor standing in front of any part of its footprint; farCornerTile(amongFootprintTiles:) re-derives the far corner from the raw tile list
  Sources/World/TileFieldRenderer.swift    makeBuildingNode(for: BuildingPlacementRecord) -> SKSpriteNode: whole-sprite texture from BuildingCatalog/BuildingSprite (index-mapped via BuildingSprite(rawValue:)), anchorPoint (0.5, 0) (bottom-centre) at the lot tile's screen point rounded to whole device pixels, zPosition from IsometricDepthSorting + DepthModel.worldLayerRelativeZ, finished with PixelCrispness.apply — the building counterpart of GroundTileRenderer; configure(_:for:) reconfigures a pooled node in place and asserts DepthModel.isWithinSupportedDepthRange(forTile:) on the far corner in DEBUG. Mounted in production by GroundPlaneStreamer, which parents one node per Chunk.buildingPlacements record straight into GameScene.worldLayer alongside that chunk's ground nodes and drops both when the chunk is evicted
  Sources/World/BuildingObstruction.swift  isObstructed(_:by:)/isObstructed(_:byAnyOf:): footprint-only obstruction query over BuildingPlacementRecord.footprintTiles, never a rendered node's bounding box — the primitive a later story's movement/collision resolver (CYBERPUN-17-7) will call
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
  BuildingSpriteBaseAlignmentTests.swift   the measured basis for TileFieldRenderer's (0.5, 0) anchor, re-derived from pixel alpha for all 12 buildings (the AtlasGroundDiamondTests pattern): opaque content horizontally centred in its own PNG, running to the PNG's bottom edge with no transparent padding below, and exactly the three .twoByTwo buildings measuring wider than one 96px lot
  BuildingDepthAndAnchorTests.swift         TileFieldRenderer.makeBuildingNode anchor (0.5, 0) + whole-pixel position; IsometricDepthSorting keys off the footprint's far corner (not the base tile); an actor tile-sum smaller than the far corner's always resolves a greater z than the building; a 2x2 footprint (building_08) anchors at its base tile, not the merged footprint's centre, which projects exactly half a tile up-screen
  BuildingCollisionTests.swift              a tall (building_05) and a short (building_10) building sharing one footprint obstruct identically — same blocked tiles, same walkable approach boundary, and BuildingObstruction agrees between the two — while their rendered sprite heights differ enormously (that fixture proves the parity half only, since it derives its tile kinds from the record); the generation half is asserted against ChunkGenerator.generate output instead: a generated chunk that placed both a tall (building_05) and a lowest (building_10) building has every footprint tile of both classified solid by CityLatticeGenerator, and the same holds for every placement across a swept chunk range
  NoBuildingGeometryConstructionTests.swift source scan: no per-face/per-storey/prism geometry-construction markers in building-related Sources/ files, and "tileset_structure" appears nowhere in Sources/
  Direction8Tests.swift                    screen-space (from(vector:)) sector-binning table, all 8 cases plus zero-vector (nil)
  PlayerAnimatorTests.swift                walk-cycle frame-timing: idle freezes to frame 0, 8fps progression, exhaustive frame table
  PlayerSpriteSheetTests.swift             measured Direction8 -> (row, mirrored) table exhaustive over every case, anchor point + hitbox contract
  PlayerNodeTests.swift                    facing/mirror/texture per Direction8 case (SpriteKit-space vectors), idle-freezes-at-last-facing, walk-cycle timing, hitbox geometry, shadow z-ordering, pixel-crispness at construction
  PlayerDepthTests.swift                   DepthBanding's player-max tie-break, band+offset arithmetic, rounded-tile sampling, supported-depth-range guard, and PlayerNode.updateDepth wiring
  PlayerMountTests.swift                   GameScene mounts a real PlayerNode (+ ActorShadowNode) as a direct child of worldLayer on entry to .gameplay, placed at the camera's tile with DepthBanding's zPosition, reused (not duplicated) across RUN AGAIN, and driven once per frame by GameScene.update(_:)
  PixelCrispnessTests.swift                isIntegerScale(_:) true/false table incl. simulated @2x/@3x device scales; snappedPosition(for:scale:) lands on the exact expected device pixel at simulated @2x/@3x (10.24 -> 10.0 and -5.26 -> -5.5 at @2x), rounds to the nearest device pixel rather than the nearest whole point, leaves a whole point alone at every scale while moving a half point at @3x (on the grid only at @2x), is idempotent, is a no-op for a non-positive scale, and stays on the *nearest* device pixel across a sequence of simulated camera moves
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
  CyberpunkMonsterCrawlUITests.swift       menu present + PLAY hittable + tapping it unmounts the whole menu (PLAY *and* the durable menu.container anchor) with the app still foregrounded; it does NOT prove the destination screen end-to-end (GameplayScreenNode mounts no anchor until CYBERPUN-17-12) - PLAY -> .gameplay is pinned in-process by GameViewControllerCompositionTests
  AppLaunchAndRotationUITests.swift        launch shows the menu in portrait, rotation re-lays it out in landscape with nothing off-screen, PLAY dismisses the menu
docs/bootstrap.md                          original spec (source of truth)
.mothership/journeys/*.json                product-verification journeys, one per story with a user-visible state; each names its story in "stories" (the gate only runs a journey for the story it names) and carries the reviewer's brief in "demonstrates". menu-to-gameplay (CYBERPUN-17-5): launch -> screenshot the menu -> navigate to PLAY (plain language, located visually) -> screenshot the streamed city with no placeholder text over it. raccoon-swarm (CYBERPUN-17-8): ~30s/~50s waits so the swarm has crossed the off-screen spawn gap and reached the bite standoff ring. pickup-spawn (CYBERPUN-17-11): ~12s/~18s waits for a bobbing pickup on a street tile, with the first of those waits SPLIT so assert_running brackets PickupKind's 8s firstSpawnDelay (pinned by JourneyManifestTests.test_thePickupSpawnJourney_bisectsTheFirstSpawnDelayWithAssertRunningCheckpoints) -- the probe has twice reported the process gone shortly after that delay fires, and the checkpoints bisect it using the probe's own vocabulary rather than an in-app crash harness. auto-fire-weapons (CYBERPUN-17-9): the weapon overlay + the swarm in weapon range, and deliberately NO bullet frame (AC1 gates fire on movement; the probe has no drag verb). death-and-high-scores (CYBERPUN-17-13): a derived floor wait (JourneyManifestTests.secondsBeforeThePlayerCanBeDead, ~31s) and then wait_for_element on the RUN AGAIN button (mounts only once .death is entered) rather than a guessed HP-to-zero duration, screenshots the eight-row death summary, chains a second death off the RUN AGAIN run exiting via BACK TO MENU into HIGH SCORES, and screenshots the table rendered from the live store -- relaunch persistence is not probe-visible (no cold start) and stays owned by HighScoreStoreTests, as AC7 orientation/overlap (no rotate verb in the probe vocabulary) stays owned by ScreensTests
```

> `AGENT.md` and `CLAUDE.md` are the same document under two names. Every edit must land in both, byte for byte — `DocumentationParityTests` fails the suite if they ever diverge, so the two cannot drift into disagreeing instructions.

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
  it. Buildings mount into this same `worldLayer` alongside these ground
  nodes (`CYBERPUN-17-5-t2`): `mountChunk` walks each newly resident chunk's
  `Chunk.buildingPlacements` in the same pass and parents one
  `TileFieldRenderer` node per record just as directly, through a separate
  `buildingNodesByChunk`/`buildingPool` pair (so the ground plane's own "one
  node per resident tile" bound stays a statement about ground tiles, while
  a chunk's building count varies with how many block interiors it owns), and
  eviction drops a chunk's buildings in the same pass as its ground. The
  remaining world wiring - movement, building-collision resolution and
  camera-follow - is `CYBERPUN-17-7`'s.
  Nodes evicted from the resident window go into `GroundPlaneStreamer`'s
  recycle pool rather than being deallocated, and `unmountAll()` returns its
  nodes there too, so a restarted run re-mounts the window out of the pool;
  `GameScene.startGroundPlane()` keeps the existing streamer when `worldSeed`
  is unchanged (same seed = same city) and replaces it only when the seed
  changes, since a discarded streamer takes its pool with it
  (`ChunkStreamingGroundTests` pins both sequences)
- `GameScene` no longer carries the `SCAFFOLDING(CYBERPUN-17-7)` debug
  camera pan (`debugPanEnabled`, `debugPanTilesPerSecond`,
  `advanceDebugPanIfNeeded`): it existed only so multi-chunk streaming could
  be watched end-to-end during a manual run while there was no
  camera-follow, and `CYBERPUN-17-7` deleted it when real player/camera
  movement landed. It was deliberately **not** covered by any test, so the
  removal cost no green test. The `update(_:)` override that used to call it
  was **not** part of that scaffolding (`CYBERPUN-17-4-t4`): it also drains
  `groundPlane`'s incremental-mount queue every frame, unconditionally, in
  Release builds too — that half is a correctness fix (see
  `GroundPlaneStreamer` above), so `CYBERPUN-17-7` kept the override (which
  now also drives `advanceMovementAndCamera`) and deleted only its DEBUG call
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
  committing each placement; `ChunkGenerator.generate` then **folds** every
  record's `footprintTiles` into the world-lifetime `LotReservationStore`,
  so `chunk.reservedTiles` is non-empty for a chunk full of buildings and
  `reservableFootprints(in:)` never offers a tile a building stands on. The
  fold is idempotent — a set union of a decision that is a pure function of
  `(block, seed)` — so a chunk evicted and regenerated re-folds the
  identical tiles. `RooftopSignPlacement.generate(forBlock:
  placements:seed:)` runs on its own salted hash stream (~1-in-3 signed
  blocks) and only ever names a carrier lot that `placements` actually
  contains, returning `nil` unconditionally for an empty block.
  `ChunkGenerator.generate` aggregates both onto `Chunk.buildingPlacements`
  / `Chunk.roofSigns` for the blocks that chunk **owns**
  (`BuildingPlacement.blockCoordinates(ownedByChunk:)`: the chunk containing
  the block interior's lower corner), which partitions the plane so every
  block is generated by exactly one chunk. The earlier "fully contained
  interior only" rule dropped ~44% of building blocks — `Chunk.size` (8) is
  not a multiple of `CityLatticeGenerator.period` (6) — and borrowed a
  no-cross-chunk-lookup limit that does not apply here:
  `reservableFootprints(in:)` must consult `tiles` for a `TileKind`, while
  `BuildingPlacement.generate(forBlock:seed:)` reads nothing but
  `(block, seed)`.
- Building sprite presence: anchor, depth-sort & footprint-only collision
  primitive (implemented — `Sources/World/TileFieldRenderer.swift`,
  `IsometricDepthSorting.swift`, `BuildingObstruction.swift`;
  `BuildingDepthAndAnchorTests`, `BuildingSpriteBaseAlignmentTests`,
  `BuildingCollisionTests`,
  `NoBuildingGeometryConstructionTests` — `CYBERPUN-17-5-t2`).
  `TileFieldRenderer.makeBuildingNode(for:)` turns a `BuildingPlacementRecord`
  into a whole-sprite `SKSpriteNode` (`BuildingSprite(rawValue:
  record.building.index)`, never sliced or assembled from primitives):
  bottom-centre anchor (`(0.5, 0)`) at the lot tile's screen point rounded to
  whole device pixels, and a zPosition from `IsometricDepthSorting`, which
  keys off the footprint's *far* corner (`max(tileX + tileY)` across
  `footprintTiles`, re-derived from the raw tile list rather than trusted
  from the record) rather than the base tile — `DepthModel.band(forTile:)`'s
  monotonic ordering then guarantees any actor tile with a smaller sum than
  the far corner resolves a strictly greater zPosition, so a building can
  never draw over an actor standing in front of any part of its footprint.
  `GroundPlaneStreamer.mountChunk` is the **production mount** for these
  nodes (not a later story): it parents one node per
  `Chunk.buildingPlacements` record of every resident chunk directly into
  `GameScene.worldLayer` and evicts them with that chunk's ground nodes, so
  product gate 4 ("the city reads as a city ... building sprites placed
  across the blocks") is observable by tapping PLAY rather than only through
  a unit test that calls `makeBuildingNode` directly - the same reasoning
  `GroundTileRenderer`/`GroundPlaneStreamer` already state for the ground
  plane ("a factory with no caller renders nothing in a real build").
  `BuildingObstruction.isObstructed(_:by:)` is a small, named, footprint-only
  entry point (`BuildingPlacementRecord.footprintTiles` membership, never a
  rendered node's `calculateAccumulatedFrame()`/`size`) that a later story's
  live movement resolver can call — collision itself is already
  footprint-only by construction (`TileKind.buildingFootprint.isWalkable ==
  false` is decided at generation time, before any building sprite is even
  chosen for that tile), which `BuildingCollisionTests` pins directly by
  showing a tall (`building_05`) and a short (`building_10`) building
  sharing one footprint obstruct identically despite wildly different
  rendered heights. That fixture-based case proves the *parity* half only,
  because it derives its own tile kinds from the record it is testing, so the
  generation half is asserted against real
  `ChunkGenerator.generate(chunkCoordinate:seed:reservations:)` output as
  well: a generated chunk that happened to place both a `.tall` and a
  `.lowest` building has every footprint tile of both reported solid by
  `CityLatticeGenerator.classify` (which never sees which sprite was chosen),
  and the same holds for every placement across a swept chunk range.
  The anchor itself rests on measurements rather than on a claim about how
  the art was authored: `BuildingSpriteBaseAlignmentTests` re-derives from
  pixel alpha, for all 12 buildings, that the opaque content is horizontally
  centred in its own PNG and runs to the PNG's bottom edge, and that exactly
  the three `.twoByTwo` buildings measure wider than one 96px lot, while
  `BuildingDepthAndAnchorTests`'s 2x2 case pins the base-tile convention
  against the merged-footprint-centre alternative (half a tile up-screen) -
  the same treatment `GroundTileRenderer`'s anchor comment gives the 112px
  `overhangLot` crop. No live actor calls `BuildingObstruction` yet — the
  player actor itself has since landed (`CYBERPUN-17-6`, next bullet), so the
  remaining wiring (movement, collision resolution, camera) is
  `CYBERPUN-17-7`'s
- Rooftop sign rendering & scene streaming wiring (implemented —
  `Sources/Rendering/RooftopSignRenderer.swift`,
  `Sources/World/GroundPlaneStreamer.swift` (extended, not a new sibling
  streamer); `RooftopSignRenderingTests`, `RooftopSignSpriteAlignmentTests`,
  `BuildingSceneIntegrationTests`, `ChunkStreamingGroundTests` (recycle path)
  — `CYBERPUN-17-5-t3`). `RooftopSignRenderer.makeSignNode(for:parent:)` turns
  a `RooftopSignRecord` into a **distinct** `sprite_signs`-textured
  `SKSpriteNode`, added as a *child* of its carrier building node rather
  than composited into the building's own texture (AC7's rendering half):
  bottom-centre anchor at
  `(0, buildingNode.size.height - AtlasSignGlyphBand.bottomInset(...))` in
  the building node's own local coordinate space — the roofline's top-centre
  (a child's position is unaffected by its parent's anchor point), dropped by
  the measured transparent pad below that cell's glyphs so the glyph base,
  not the cell's empty bottom edge, rests on the roof — and
  `DepthModel.signContentOffset` as its child `zPosition` (owned by
  `DepthModel`, whose `buildingContentRange` names rooftop signs as its
  content, not a literal invented at the renderer; asserted against
  `DepthModel.isValidBuildingContentOffset` in DEBUG) so it draws in front of
  the roof. That anchor is a *measurement*, not an inference from the 48×48
  cell size: `RooftopSignSpriteAlignmentTests` re-derives from `sprite_signs`'
  alpha channel, for all 12 cells, that each cell's opaque content is
  horizontally centred (±4px), and that its glyphs sit in a *vertically
  centred* band (cell 0 occupies rows 18..<30 of its 48-row cell — the art is
  not bottom-flush) exactly matching the bands `AtlasSignGlyphBand.glyphRows`
  declares. That is what makes the renderer's `bottomInset` drop land a sign
  on the roofline instead of floating it 8-19px above the roof, and it turns
  re-authored or re-cut art red here rather than silently un-tuning the
  offset — the same treatment `BuildingSpriteBaseAlignmentTests` gives the
  building anchor.
  `GroundPlaneStreamer.mountChunk` already generically mounted/evicted
  building nodes per chunk (`CYBERPUN-17-5-t2`), so this task extended that
  existing streamer rather than adding a new sibling: it now also looks up
  `chunk.roofSigns` by `carrierLotTile` and attaches the matching sign as a
  child in the same pass a building node is mounted. Because a sign is only
  ever a *child* of its building node, it carries no bookkeeping of its own
  (no `signNodesByChunk` map, no separate pool) — **mount and eviction**
  follow the parent building node's lifecycle for free. **Recycle does not:**
  `dequeueOrMakeBuildingNode` strips any stale sign child (by name —
  `childNode(withName: RooftopSignRenderer.signNodeName)?.removeFromParent()`,
  not the broader `removeAllChildren()`) before reconfiguring a pooled node,
  so a recycled building never keeps rendering a previous occupant's sign,
  but the sign node itself is discarded and a fresh one is allocated on the
  next remount. Signs are therefore explicitly outside the "no further
  `SKSpriteNode` allocated once the window has filled" invariant `pool` /
  `buildingPool` state — a bounded, accepted allocation (~1 per 3 blocks per
  mount), not a covered case.
  `ChunkStreamingGroundTests.test_recycledBuildingNodes_carryNoStaleRooftopSign_afterAPanThatEvictsSignedBuildings`
  pins the strip through a real evict-then-remount (a fresh mount from an
  empty pool never reaches that line, so the stale-sign regression would
  otherwise ship green).
  `BuildingSceneIntegrationTests` drives the same production mount
  (`GroundPlaneStreamer`, not `TileFieldRenderer` called in isolation) and
  checks the AC1 "city reads visually" claim as far as it is checkable
  off-device: building nodes are actually mounted, carry non-nil textures,
  and their art carries a real alpha channel with transparent pixels outside
  the silhouette (never an opaque "navy placeholder box").
- Player sprite: row/mirror table, walk-cycle timing and node assembly
  (implemented — `Sources/Actors/Direction8.swift`,
  `PlayerAnimator.swift`, `PlayerSpriteSheet.swift`, `PlayerNode.swift`,
  `ActorShadowNode.swift`, `Sources/World/DepthBanding.swift`;
  `Direction8Tests`, `PlayerAnimatorTests`, `PlayerSpriteSheetTests`,
  `PlayerNodeTests`, `PlayerDepthTests` — `CYBERPUN-17-6-t1`/`-t2`).
  `Direction8` bins a movement vector into 8 sectors clockwise from
  screen-south, with a screen-space (`from(vector:)`, y-down pixel
  convention) and a SpriteKit-space (`from(spriteKitVector:)`, y-up scene
  convention) overload so no gameplay call site has to remember to negate
  `dy` itself; it carries no player-specific knowledge, so a future raccoon
  sheet (`CYBERPUN-17-8`) bins against the same unmodified type.
  `PlayerSpriteSheet` owns the player's `Direction8 -> (row, mirrored)`
  table (5 directly-authored facings, 3 mirrored from the row sharing their
  vertical component) plus the anchor point (`(18, 40)px`, bottom-centre)
  and the `14x10` hitbox, all measured/pinned against the shipped
  `sprite_player_walk` pixels rather than assumed. `PlayerAnimator` is a
  pure frame-timing state machine (8 fps, 4-frame walk cycle, frame 0 while
  idle). `PlayerNode` (`SKNode`) composes all three into a live node: a
  `.nearest`-filtered, cached-per-cell `SKSpriteNode` body plus a distinct
  `ActorShadowNode` (a reusable 2:1-ellipse shadow, z-ordered beneath the
  body, meant for reuse by future actors) — `update(deltaTime:
  movementVector:)` resolves facing/frame/mirror from a SpriteKit-space
  vector but never touches `position` itself (movement lands with
  `CYBERPUN-17-7`). `DepthBanding` extends `DepthModel`'s actor-offset slot
  (`6.5...9.9`) with the player-max tie-break: the player is always
  assigned the range's exact ceiling (`playerActorOffset`), and any other
  actor is expected to draw from `nonPlayerActorOffsetRange` (the same
  range with that ceiling excluded), so the player's zPosition is
  guaranteed the band's maximum by construction rather than by a per-frame
  comparison. `PlayerNode.updateDepth(atTilePosition:)` is the production
  wiring: `DepthBanding.playerZPosition(at:)` converted via
  `DepthModel.worldLayerRelativeZ(forAbsoluteZ:)` for a node parented
  directly under `worldLayer`, the same convention `GroundTileRenderer`
  uses. `GameScene.startPlayer()` (`CYBERPUN-17-6-t2`) is the production
  mount: entry to `.gameplay` parents a real `PlayerNode` directly under
  `worldLayer` at the camera's tile, reusing (not duplicating) it across a
  RUN AGAIN, and `GameScene.update(_:)` drives its per-frame state every
  frame. The player's screen position is re-derived from tile space on
  every mount/reposition and snapped via
  `PixelCrispness.snappedPosition(for:scale:)` to the running device's
  actual pixel grid (`CYBERPUN-17-6-t3`; falls back to a whole-*point* snap
  for a headless, view-less scene). That snap covers the *actor's* mount
  position only: `cameraNode.position` is not snapped anywhere, so once the
  camera moves off a whole device pixel every world-space child inherits the
  sub-pixel offset again — snapping the camera belongs with
  `CYBERPUN-17-7`, the ticket that first makes it move under gameplay.
  Movement itself landed with `CYBERPUN-17-7` (floating thumbstick, building
  collision, camera-follow), so a shipped build now walks the mounted player
  from real input: `GameScene.advanceMovementAndCamera(currentTime:)` pipes
  the stick through `PlayerMovementController` and `CollisionResolver`,
  commits position/depth, then drives `CameraController`. The scene (not any
  driver) is still the caller of `PlayerNode.update(deltaTime:movementVector:)`.
  `PlayerScaffoldingDriver`, `debugPlayerDemoEnabled` and the debug camera
  pan are deleted, costing no green test and no production call site
- Floating thumbstick input + player movement computation, the first PR of
  `CYBERPUN-17-7` (implemented — `Sources/UI/FloatingThumbstickNode.swift`,
  `Sources/Gameplay/PlayerMovementController.swift`;
  `FloatingThumbstickNodeTests`, `PlayerMovementControllerTests`,
  `ThumbstickMovementSeamTests`). Two self-contained, exhaustively
  unit-tested types, both **wired into the live scene** by `GameScene`
  (mount, touch routing, per-frame pipeline): `FloatingThumbstickNode` is the input
  *producer* — appears at first-touch location within the left half of the
  safe content area (excluding a reserved bottom-left HUD slot stacked
  above it for the future pulse-ability button, `CYBERPUN-17-10`), tracks
  a drag, clamps at `maxRadius`, and reports a plain `StickState` (unit
  direction, `0...1` magnitude, `isBeyondDeadZone`) — driven directly via
  `beginTouch(at:)`/`updateTouch(at:)`/`endTouch()` rather than by owning
  `UITouch` itself; `GameScene` routes all four touch phases into that seam
  via `activeStickTouch`. `PlayerMovementController` is the *consumer*:
  given a `StickState` and the render clock, it derives
  `frameDisplacement` (named for what it is — `deltaTime` is already folded
  in, so a caller must never re-apply the timestep; a tile-space step
  produced by scaling the stick's screen-space direction to
  `maxPointsPerSecond * magnitude * deltaTime` **while still in screen
  space** and only then passing it through the existing
  `IsometricProjection.screenToTile(_:)` inverse transform, never a
  duplicate projection. Because `screenToTile` is linear, that ordering
  preserves the screen distance exactly, so a full stick push covers the
  same on-screen distance in every heading; re-normalizing in tile space
  instead would pin the speed in tile units and make a sideways push travel
  exactly 2x as far per second on screen as an upward one on the 2:1
  projection — a ratio no tiles-per-second value can fix), `facingVector`
  (the stick's own raw screen-space direction, freezing at its last value
  below the dead zone — facing tracks the movement stick only, there is no
  aim stick in this story), and `isMoving` (exactly
  `StickState.isBeyondDeadZone`, exposed as stable API for the upcoming
  auto-fire story, `CYBERPUN-17-9`). `deltaTime` is clamped at derivation
  to `maxFrameDelta` (1/20s) as well as floored at `0`, so a backgrounded
  app, a debugger pause or the `.gameplay`-entry generation stall cannot
  hand the (later) collision resolver a single frame that steps many tiles
  and tunnels through a building. `canBeginTouch(at:)` requires
  `isRunActive`, which makes "no run => no stick interaction" hold from
  both directions rather than relying on each call site (the `didSet`
  already cancels an in-flight drag), and asserts in DEBUG that
  `layout(for:safeAreaInsets:)` has run, since a `.zero` `currentSize`
  makes `leftRegion` degenerate and would otherwise silently refuse every
  touch. `ThumbstickMovementSeamTests` still drives a real laid-out node
  through `beginTouch`/`updateTouch`/`endTouch` and pipes its own
  `stickState` straight into a real controller, so a y-sign, unit-vs-raw or
  dead-zone disagreement between producer and consumer cannot ship green
  even now that the scene owns the seam. The wiring itself (touch dispatch,
  `PlayerScaffoldingDriver` deletion, collision, camera-follow) landed in
  the later PRs of `CYBERPUN-17-7`; still open on the story is a per-run
  `worldSeed` (unticketed; see "not built yet" below); `GameplayScreenNode`'s
  `gameplay.container` marker was removed in `CYBERPUN-17-7-t5`
- Tile-grid collision — no `SKPhysicsBody`; buildings are flat footprints
  on a tile grid. `BuildingObstruction` (discrete) and the continuous,
  sliding `CollisionResolver` (`Sources/Gameplay/`, `CYBERPUN-17-7`) are wired
  into `advanceMovementAndCamera`, against `residentObstructions` each frame
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

## Deferred work

- Pulse ability (`CYBERPUN-17-10`) — decision layer only in `-t1` (`PulseAbility`/`LevelScaling`, no caller); the HUD button (`Sources/UI/PulseButton.swift`) landed unmounted in `-t2`. `-t3` (this PR) closed the gap: `Sources/Rendering/PulseRingNode.swift` (the sprite_pulse shockwave, **per-axis** scale-to-radius via `xScale(forRadiusTiles:)`/`yScale(forRadiusTiles:)` — a tile-space circle projects to a 2:1 screen *ellipse*, so a single uniform scale drew the ring ~29% narrow on x and ~41% tall on y; each axis divides by the ring's alpha-measured extent inside its cell (`AtlasPulseRingContent.widestFrameContentSize`, re-scanned off the shipped PNG by `PulseRingArtMeasurementTests` in the `AtlasSignGlyphBand`/`AtlasGroundDiamond` pattern) rather than by the 32px cell — a reserved relative zPosition sub-range inside `LayerConstants.effectsBand`) and `GameScene` wiring — `pulseButton` mounted at `FloatingThumbstickNode.reservedPulseButtonSlot`'s centre, hidden outside `.gameplay`; `applyPulseTrigger(raccoons:)` (fed `raccoonSpawnDirector.targetCandidates` by `pulseButton`'s `onPress`) applies each `PulseAbility.Hit`'s damage/pushed position to the live `RaccoonNode` and plays `pulseRing`; `RaccoonSpawnDirector.syncPushedPosition(_:for:)` (new) keeps the swarm director's own tracked position in step with a push so the next frame's steering does not silently revert it; `pulseAbility`/`pulseButton`'s cooldown display are both driven every `.gameplay` frame. Product gate 8 is now reachable on a running simulator. A RUN AGAIN mid-cooldown now starts the pulse **ready**: `PulseAbility.reset()` (new) plus `pulseButton.setCooldownProgress(...)` run on every fresh `.gameplay` entry, alongside `raccoonSpawnDirector.reset()`/`startPickups()`/`runStats.reset()` — this story deliberately does *not* inherit `WeaponFiringController`'s accepted carried-cooldown gap, because the weapon auto-fires (an invisible carry-over) whereas a dead pulse button reads to the player as a dropped input. Outstanding: the level-6 radius bonus ships *compounding* (1.5625, not additive 1.5) pending a human tuning call, and the button's bottom-**left** placement (`FloatingThumbstickNode.reservedPulseButtonSlot`, reserved in `-t2`) differs from the ticket's "bottom-right" wording — flagged for the human gate-8 reviewer to confirm or raise a relocation ticket, not settled here. `-t4` fixed a **stale-safe-area mis-placement** bug found while investigating the crash the runtime probe's `pulse-ability` journey hit right after entering `.gameplay` and again after pressing the pulse button -- **the crash cause itself is still unidentified and is NOT recorded as fixed**: closing it needs the symbolicated crash log / device output from a probe run, naming the frame (raised on PR #52 review, NO TICKET ID - file one before closing the story), and a now-green probe journey is *not* that evidence, since the probe's tap finally landing on a correctly placed button is enough to turn the journey green either way. Nothing in the `-t4` change can tear a process down: every reachable assert/precondition on the changed path is position-independent (`assertSceneInvariants()` = cumulative zPosition bands + `isUserInteractionEnabled`; `FloatingThumbstickNode`'s only `assert` is `currentSize != .zero`, already satisfied by `commonInit()`; `layoutPulseButton()`/`reservedPulseButtonSlot(...)` are pure arithmetic), and the new tests assert placement and invariants, not survival. What *was* real and is fixed: every pre-`-t4` pulse test drove `.gameplay` on either a headless (view-less) `GameScene` or an off-window `AccessibleSKView`, both of which always report `.zero` safe-area insets, so nothing had ever exercised `layoutPulseButton()`/`thumbstick.layout(...)` against a real, non-zero safe area that settles *after* `didMove(to:)` first runs but *before* a run starts -- a real cold-launch race no simulator-stable test reproduced. Per PR #52 review the fix is at the **cause**, not at one state transition: `GameScene.refreshLayoutForCurrentSafeArea()` (new -- re-lays out the active screen, thumbstick and pulse button, guarded so it no-ops unless the insets actually moved) is driven from `GameViewController.viewSafeAreaInsetsDidChange()` plus its existing `viewDidLayoutSubviews()`, so *every* consumer of `currentSafeAreaInsets` follows a late-settling safe area -- including the `.menu` screen (registered before `presentScene(_:)`, so first laid out with `view == nil` -> `.zero`, and previously carrying the identical hole) and including insets that settle mid-run with no size change. `updateWorldContent(for:)`'s `.gameplay` case calls that same refresh as a second line of defence, since UIKit does not promise the hosted `SKView`'s own insets have propagated when the controller-level callback runs and a non-`GameViewController` host gets no callback at all. `CyberpunkMonsterCrawlTests/PulseAbilityLiveCompositionTests.swift` is the new regression suite, hosting the composed scene in a real (non-`AccessibleSKView`, since that class is `final`) `SKView` subclass that overrides `safeAreaInsets`, and pins the `.gameplay` refresh, the menu/no-state-change refresh, the unchanged-insets no-op guard, the full journey (real PLAY tap -> ~2s of real elapsed `.gameplay` frames -> a real pulse-button tap, with `assertSceneInvariants()`'s own checks asserted directly throughout), and rotation mid-run. `-t5` investigated the still-unidentified crash cause named above: the leading hypothesis (a `sprite_pulse` measured-vs-declared dimension mismatch tripping `SpriteSheet.init`'s precondition) was checked directly against the shipped `Assets.xcassets/Atlas/sprite_pulse.imageset/sprite_pulse.png` bytes (256x32, matching `AtlasSheet.pulse`'s declared `pixelSize`/`cellSize` exactly -- already independently pinned by `PulseRingArtMeasurementTests`/`AtlasDimensionsTests`, see `AtlasSheet.pulse`'s own doc comment) and ruled out: no dimension mismatch exists, so that precondition cannot be firing. A second audit of every other path this journey uniquely reaches -- `PulseRingNode.play(...)`'s texture/frame lookups (bounded to `AtlasCellIndex.pulse`'s 8 real columns), `applyPulseTrigger(raccoons:)`'s `effectsSpacePoint` conversion, and `RaccoonSpawnDirector.syncPushedPosition(_:for:)` (a guarded, no-op-safe lookup by node identity) -- found no reachable force-unwrap/array-index/precondition risk either. **The crash cause remains genuinely unidentified.** What this PR adds instead: `CrashDiagnostics` (`Sources/Diagnostics/CrashDiagnostics.swift`), installed from `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before `SceneDelegate` ever builds `GameViewController`/`GameScene`, persists the crashing thread's symbolicated backtrace (POSIX signal handlers for SIGABRT/SIGILL/SIGSEGV/SIGFPE/SIGBUS/SIGTRAP -- the signals a Swift `precondition`/`fatalError`/force-unwrap/array-out-of-bounds trap or a memory violation actually raises) and any uncaught `NSException` to `last-crash.log` in the Caches directory, then re-raises so the process still terminates exactly as before -- so the *next* `pulse-ability` probe run leaves a symbolicated trace naming the actual frame instead of "process gone", closing the evidence gap `-t4` left open. Per PR #53 review that file is explicitly **scaffolding**, not permanent crash infrastructure: it carries a `SCAFFOLDING(CYBERPUN-17-10)` marker naming the still-unfiled crash-cause ticket as its removal owner (no ticket ID invented) and is gated `#if DEBUG` at both the file and the `AppDelegate` call site (that convention's original exemplar, `Sources/Debug/LaunchGotoState.swift`, has itself since been deleted as scaffolding by `CYBERPUN-17-13-t3`/PR #51 — named here as history, not as a file to go read), so no shipped binary has its process-wide `NSSetUncaughtExceptionHandler`/signal dispositions replaced by a debugging aid nobody owns. Its signal handler is **allocation-free**: the 64-entry frame buffer and the report header are pre-allocated by `install()` and the signal number is rendered by a hand-rolled decimal conversion rather than string interpolation, because `malloc` is not async-signal-safe and a handler that deadlocks on the malloc lock would leave the probe with *neither* a trace nor a clean crash. A stack-overflow `SIGSEGV` is out of scope (no `sigaltstack` is installed; recorded in the doc comment so nobody assumes coverage). Evidence is dated, never ambiguous: `install()` deletes any `last-crash.log` a previous launch left behind before arming either hook and both hooks stamp the report with this process's launch time, so a run that does not crash leaves no report and a probe cannot read a three-runs-old trace as fresh; `CrashDiagnosticsTests` writes only through explicit throwaway destinations (`persist(_:to:)`, a temp fd) and never deposits fabricated report text at the real Caches path. `PulseAbilityLiveCompositionTests` gained one more regression case (`test_livePulseAnimation_realWindowUnpausedRendering_survivesAFullRingPlaythrough`) that -- unlike every test before it, which keeps its `SKView` paused and off-window -- hosts the composed scene in a real `UIWindow` with the view unpaused, so SpriteKit's own display-link loop actually renders the mounted `PulseRingNode` and its texture through a full real play-through, the one condition nothing prior exercised; a green run there does not prove this was the crash's cause (still unidentified), only that a real render pass over this exact path does not, on its own, tear this test environment down. **`-t6` removed `CrashDiagnostics` entirely**: the still-unfiled crash-cause ticket its own removal-owner comment named was never filed (no ticket ID exists to close), so the sanctioned close-out per that comment's own audit instruction is deletion of the investigation-support code and its call site rather than a further extension. `CyberpunkMonsterCrawl/Sources/Diagnostics/CrashDiagnostics.swift` and `CyberpunkMonsterCrawlTests/CrashDiagnosticsTests.swift` are both gone, and `AppDelegate.application(_:didFinishLaunchingWithOptions:)` is back to a bare `return true` with no `#if DEBUG` install call. The crash itself remains genuinely unidentified and uninvestigated further by this PR; a grep for `CrashDiagnostics` across the tree now comes up empty, and this story owns no un-removed temporary artifact. One other change rode along in `-t6` and is recorded here rather than left to the diff: four floor-clamp assertions in `PulseRingNodeTests.test_scale_neverDropsBelowOne_...` were flipped to `accuracy: 1e-6`, out of this task's stated scope and against that test's own restored-four-times comment; **they were reverted to exact equality on PR #56 review** (restored a fifth time — PR #51/#53/#54/#55/#56), so `-t6` is now purely the deletion it claims to be and no assertion in this story was weakened. **Filing the crash-cause ticket is a precondition for closing `CYBERPUN-17-10`, not a resolved item.** Deleting the scaffolding closed out the un-owned temporary code but *re-opened* the evidence gap it existed to fill: the next `pulse-ability` probe run is back to "process gone, no frame named", now with neither instrumentation nor a ticket tracking it. The human gate-8 reviewer must file that ticket (a human call — no ID is invented here) and obtain the symbolicated crash log / device output naming the frame before this story can close; a green probe journey is still not that evidence.
- Ground pickups (`CYBERPUN-17-11`) — **the authoritative implemented-vs-outstanding list for this story; read this rather than inferring the remaining scope from `PickupKind`/`Pickup`/`PickupManager`/`PickupNode`/`RaccoonSeekBehavior`'s doc comments.**
  Implemented (`-t1`): `PickupKind` + `DiceSpec` (frozen tuning — 8s first spawn, 25s cadence, 20s lifetime, 1d10 med kit / 1d6 garbage can); `Pickup` (pure data); `PickupManager` (per-kind cadence timers; placement validated against `CityLatticeGenerator.classify` plus `BuildingObstruction` on the candidate tile *and* all 8 neighbours; one pickup per tile, so two icons never stack at the same depth offset; lifetime aged strictly by `deltaTime`, so a camera jump cannot expire a pickup early; `attemptCollectMedKit`/`attemptCollectGarbageCan`/`nearestGarbageCan` queries); `PickupNode` (untinted 32pt icon over an accent-tinted pad, bob action, `DepthBanding.nonPlayerActorOffsetRange` depth, non-integer 32/24 magnification documented and pinned). Implemented (`-t2`, each *effect* in its own file; the only shared code is the tuning table and `DiceSpec.roll(using:)` — the single dice roller, consolidated at PR #37 review from three separate copies of one spec, one of which used a different `Int.random(in:using:)` mapping): `PlayerNode.heal(_:)` applies a collected med kit's rolled amount capped at `maxHP` and returns the amount *actually applied*; the roll itself stays in `PickupManager.attemptCollectMedKit(at:radius:)`, the one call that owns the pickup record, so exactly one 1d10 exists per med kit (this file rolled a second, independent one until PR #37 review). `RaccoonSeekBehavior.divertTarget(...)`/`.seekTarget(...)`/`.updateWithDiversion(...)` divert a wounded, *live* raccoon within `garbageCanDiversionRangeTiles` to a garbage-can position, consume it for 1d6 capped at the raccoon's `maxHP` on arrival, and resume seeking the player afterward. Consuming is one-shot **without needing the caller's cooperation**: the arrival frame records the can on `RaccoonNode.consumedGarbageCanPosition` (cleared the first frame a different position — or `nil` — arrives), so a caller that discards the `@discardableResult` can no longer re-roll 1d6 every frame; and a dead raccoon (`isDead`, which `hp == 0` satisfies *while `isWounded` is also true*) neither steers nor heals, the healing-side mirror of `RaccoonNode+Combat.takeDamage(_:)`'s own `guard !isDead`. Both proven in isolation from GameScene/PickupManager per this PR's own AC.
  Implemented (`-t3`, the scene-wiring PR, closing the gap left above): `GameScene` builds one `PickupManager` in `commonInit()` (before `raccoonSpawnDirector`, handed a reference to it) and drives `pickupManager.update(deltaTime:visibleRect:)` every `.gameplay` frame, `visibleRect` derived each frame from the live camera/viewport (`GameScene.pickupVisibleTileRect()`); `syncPickupNodes()` diffs `activePickups` against a `[UUID: PickupNode]` map to mount/unmount into `worldLayer` (same depth-sort pass as buildings/actors); player collection feeds a non-nil `attemptCollectMedKit(at:radius:)` roll into `PlayerNode.heal(_:)`; `RaccoonSpawnDirector` now takes an optional `pickupManager` and, per raccoon per frame, feeds `nearestGarbageCan(within:of:)` into `RaccoonSeekBehavior.updateWithDiversion(...)`, retiring a consumed can via the new non-rolling, id-keyed `PickupManager.expireConsumedGarbageCan(id:)` instead of re-rolling. PR #38 review follow-ups: every fresh `.gameplay` entry runs `GameScene.startPickups()` → `PickupManager.reset(worldSeed:)`, so RUN AGAIN clears run 1's still-alive pickups, unmounts their nodes at the transition itself, re-arms both cadence timers and re-seeds placement against the city `startGroundPlane()` just streamed; and a candidate spawn tile must now also pass a screen-space `isVisibleOnScreen` predicate (`RaccoonSpawnDirector.isOnScreen(tile:cameraPosition:viewportSize:)`), because `pickupVisibleTileRect()` is only the axis-aligned *bounding box* of the visible diamond (~70% of the tiles it samples are off camera). All 8 story ACs are reachable through the live `GameScene` now — see `PickupIntegrationTests`. Outstanding, no invented ticket IDs: the `maxAlive: 2` cap stays unreachable at the frozen tuning (recorded on `PickupKind.Tuning.maxAlive`); pickup nodes are never culled by camera distance, only by age/consumption. **Runtime-evidence state (`-t6`)**: the `pickup-spawn` probe journey has now twice reported the app **process gone** at ~PLAY+12s and ~PLAY+18s — shortly after both kinds' shared 8s `firstSpawnDelay` fires, i.e. right as the first `Pickup` record is created and the first `PickupNode` is mounted — and two independent static audits (`-t5`, `-t6`) of `PickupManager`/`PickupNode`/`PickupKind`/`AtlasSheet.pickups`/`DepthBanding`/`GameScene`'s pickup wiring/`RaccoonSeekBehavior`'s diversion path found **no reachable crash site**; the cause is genuinely unidentified and `-t6` does **not** claim to fix it. `-t6`'s planned deliverable was to reinstate `CYBERPUN-17-10`'s `CrashDiagnostics` signal-handler/`NSException` harness to capture a symbolicated frame; **that was deliberately not implemented** — that harness was already shipped once (PR #53), carried on *this* story shipped **inert** (`install()` never called from `AppDelegate`), and deleted at close-out (PR #56) as un-owned scaffolding with its crash still unidentified, so re-adding it on this story's own terminal task re-enters that loop, and an in-app crash-capture harness is forbidden outright by this project's agent rules (the platform already returns a symbolicated faulting-thread backtrace when a probe run kills the process). What landed instead **bisects the death with the probe's own vocabulary**: `.mothership/journeys/pickup-spawn.json`'s single 12s post-PLAY wait is split into `wait 4` → `assert_running` → `wait 4` → `assert_running` → `wait 4`, so the next "process gone" report distinguishes "died before the spawn delay ever fires" from "died right as the first pickup is created/mounted" from "survived past it"; total elapsed time and both screenshot timings are unchanged, only the checkpoints are new, and `JourneyManifestTests.test_thePickupSpawnJourney_bisectsTheFirstSpawnDelayWithAssertRunningCheckpoints` binds both checkpoints to `PickupKind.medKit.tuning.firstSpawnDelay` (asserting both kinds still share it): the early arm must land strictly under the delay, and the FIRST checkpoint at or after it must land inside a narrow window (delay .. delay+2s, `checkpointWindowPastTheSpawnDelay`) rather than merely existing somewhere later — PR #61 review caught that the looser form passed vacuously against the `assert_running` steps already sitting after each screenshot (12s/18s past PLAY, both ≥ 8s), so the tight checkpoint could have been deleted with the suite still green. With the window, deleting either checkpoint, or a retune of the delay away from these waits, fails in-suite instead of silently losing the bisection. The early arm also moved from a nominal `PLAY+7s` to `PLAY+4s` (the 3s went into the following wait, screenshot timings unchanged): the waits start when the vision-located `navigate` step *returns*, not at the PLAY tap that starts `firstSpawnDelay`, so 1s of nominal margin could be eaten by the ~10s of cumulative slop the journey documents and invert the arm's conclusion. Outstanding and **not** closed by `-t6`, no invented ticket ID: a human must still file the root-cause ticket and re-run the journey — a bisection narrows what the next report can say, it does not name a frame. One repair outside this story's surface rode along in `-t6`: the pre-PR **platform** lint `spritekit-float32-equality` blocked the PR on `PulseRingNodeTests.test_scale_neverDropsBelowOne_...`, whose floor-clamp assertions have been restored to exact equality seven times (PR #51/#53/#54/#55/#56/#58/#59) against an `accuracy: 1e-6` that would swallow the exact `0.9999995` regression they exist to catch. Both sides are now satisfied with nothing weakened: those six comparisons stay **exact** and read from hoisted locals — the shape `PlayerSpriteSheetTests` already uses for the same kind of pure static `xScale(...)` result — so a line-scoped rule stops mis-reading a pure `Double` function call as an `SKNode.xScale` float32 read-back; and the two assertions in `test_play_appliesTheComputedPerAxisScale` that genuinely *do* read `node.xScale`/`node.yScale` back out of SpriteKit gained `accuracy: 1e-3`, sized to the ~10-30 whole-integer scales involved (float32's step there is ~2e-6, distinct scales are a full 1.0 apart), matching `RaccoonNodeTests`/`PickupNodeTests`. That lint is real but lives **outside** this repo as a pre-PR platform check, which is why PR #54/#55's in-repo audits of `.swiftlint*`/`project.yml`/`ci.yml`/`ios-build.yml` found nothing and concluded it was imaginary; the observed `file:line` + rule id is now recorded in that test's own comment so the next audit does not repeat it
- Raccoon swarm (`CYBERPUN-17-8`) — **the authoritative implemented-vs-outstanding list for this story; read this rather than inferring the remaining scope from `RaccoonNode`/`RaccoonSeekBehavior`/`RaccoonSpawnDirector`'s doc comments.**
  Implemented: the actor layer (`-t1`); off-screen spawning + per-frame seek/avoid steering (`-t2` — `RaccoonSpawnDirector`/`RaccoonSeekBehavior`/`BuildingAvoidance`, from `GameScene.advanceMovementAndCamera`, gated on `.gameplay`); and the combat/status-effect layer (`-t3` — `Damageable`/`RaccoonNode+Combat` (damage/death/removal/kill hook), `BiteComponent` (attack anim + damage + rabies roll, 1s cooldown so sustained contact can't re-trigger every frame), `RabiesStatusEffect` (d20-vs-tier-threshold, injectable RNG), `PlayerNode+Rabies` (HP + 1 HP/s DoT, ticked from `PlayerNode.update`), `RunSummaryStats`).
  Scene integration is **live** (PR #34 review): `RaccoonSpawnDirector.update(deltaTime:playerPosition:player:obstructions:)` decides contact via `BiteComponent.isInContact` on the same `RaccoonSeekBehavior.contactStandoffPoints(forTier:)` ring the swarm settles on and drives one `BiteComponent` per live raccoon, so a closed-in raccoon bites on a device; `RaccoonNode.runStats` is set on the production spawn path; `GameScene.startPlayer(at:)` calls `PlayerNode.resetCombatState()` so RUN AGAIN starts at full HP, uninfected (reused-node counterpart of `raccoonSpawnDirector.reset()`).
  Outstanding, no invented ticket IDs: the kill/XP hook's consumer is no longer among them — `CYBERPUN-17-9` (its own entry below) landed it: `Player` sets `RaccoonNode.onDeath` on the first bullet hit, so a raccoon is damaged, killed and counted (`RunStats`) in a real run. Still outstanding: a rabies HUD indicator and the playtesting retune of every named constant. **The HP-reaches-zero → `.death` transition itself is resolved (`CYBERPUN-17-13-t5`):** `GameScene.advanceMovementAndCamera(currentTime:)` now checks `player.hp <= 0` once per `.gameplay` frame — after every HP-affecting update that frame (raccoon bites/rabies above, and the player's own `update(...)`) has already applied — and transitions to `.death`. This closes the gap `CYBERPUN-17-13-t3`/PR #51 raised (that PR had deleted the DEBUG-only `LaunchGotoState` launch bridge, which until then was the only non-test caller able to reach `.death`, leaving *no build* able to transition there): `DeathScreenNode`, `RunScoreCalculator`, `HighScoreStore.recordRun`, `HighScoresScreenNode`'s just-finished-run highlight and `GameScene.startNewRun()` are all reachable by a player now, not only from a test's direct `stateMachine.transition(to: .death)` call. `PlayerDeathTriggerTests` pins it: HP reaching zero during `.gameplay` transitions to `.death`; a player with HP remaining never spuriously transitions across several frames; and `playerCombat` stays mounted through the transition so the death screen's `runSummaryProvider` still produces (and records) a real `RunSummary` rather than the no-run-happened placeholder
- Final gameplay HUD, death-screen run-summary rows and the high-scores list
  are explicitly out of scope for CYBERPUN-17-2 (see the story's "Out of
  scope" section): navigation (PLAY, RUN AGAIN, back-to-menu) is real; the
  visual content was not, at the time this note was written -
  `DeathScreenNode`/`HighScoresScreenNode` carried placeholder content until
  `CYBERPUN-17-13-t2` replaced it (see that entry below). `GameplayScreenNode` no longer carries placeholder *text*:
  CYBERPUN-17-5-t4 deleted its "GAMEPLAY - WORLD COMING SOON" label, because
  the streamed ground plane (CYBERPUN-17-4), the building/rooftop-sign nodes
  (CYBERPUN-17-5) and the player actor (CYBERPUN-17-6) all render behind that
  screen now - a label announcing "no world here yet" sat on top of the very
  content it denied, which reads as "feature not delivered" to a human or a
  screenshot-driven verification however correct the rendering behind it is.
  `ScreensTests.test_gameplayScreenNode_mountsNoComingSoonText` pins the
  removal by wording (walking the whole subtree, and deliberately *not*
  banning `SKLabelNode` outright so the real HUD text CYBERPUN-17-12 adds
  does not have to fight the gate), and
  `test_gameplayScreenNode_mountsNoChildren_andNoTextAnywhere` pins it
  structurally so a *reworded* placeholder fails too. The screen's former
  non-visual `gameplay.container` accessibility marker (`SCAFFOLDING
  (CYBERPUN-17-7)`) was removed in `CYBERPUN-17-7-t5` along with the two
  assertions that depended on its presence, since no durable HUD content
  existed to re-point them at; `GameplayScreenNode` now mounts no children
  at all until the real HUD (CYBERPUN-17-12) lands. Its
  `layout(for: safeAreaInsets:)` is deliberately a no-op
- Per-run `worldSeed`: **met for RUN AGAIN, with one deliberate carve-out — the first run of each process launch is still the fixed `0x0C17_5EED` default; that carve-out is a product call, raised on PR #51, and is NOT yet accepted by anyone. Do not read this bullet as "every run differs" being unconditionally true.** `CYBERPUN-17-13-t3` landed the RUN AGAIN half: `GameScene.startNewRun()` draws a fresh random `worldSeed` (and, with it, a fresh street-intersection starting junction via `RunSpawnSelector.selectSpawnTile(seed:)`) before transitioning straight to `.gameplay`; `GameViewController`'s `DeathScreenNode.onRunAgain` calls it instead of a plain `stateMachine.transition(to: .gameplay)`, which is the one and only production RUN AGAIN entry point and is why every other call site (the very first PLAY, and this codebase's own scene-wiring tests) keeps `worldSeed` unchanged. What that leaves open: gate 6's wording is "every run differs: new world seed and new starting street junction per run", and the very first PLAY of a launch still reaches `.gameplay` through the seed-neutral plain `transition(to:)`, so a player who launches, plays one run, dies and force-quits gets the identical city and identical starting junction on every launch, forever. Closing it unconditionally means also drawing a seed on the menu's PLAY path — deliberately not done in `-t3` because "is a deterministic first run per launch acceptable?" is a product decision the code cannot settle (and `worldSeed`'s own doc comment argues the seed-neutral `transition(to:)` contract several suites rely on). Resolve it one of two ways before the story closes: a human records the carve-out as accepted, or PLAY draws a seed too. See the `CYBERPUN-17-13` entry below for the full picture
- AC6 barrel-tip muzzle offset: **unmet** acceptance criterion of `CYBERPUN-17-9` ("muzzle flash = the first `sprite_hit_puff` frame drawn at the barrel tip") - the flash ships at the actor anchor (the player's feet). The previous `barrelTipOffset` table was derived against the cell centre while every actor here anchors bottom-centre, which put the south-facing barrel tips below the ground plane, so it was deleted rather than re-guessed - the same discipline `AtlasContractConventionTests`/`RaccoonSpriteSheetPixelTests` enforce. Closing it needs the muzzle pixel measured per direction off the shipped `sprite_player_weapons`, not invented numbers. Raised on PR #45; asked on `-t4`, still NO TICKET ID - file one here before closing the story, or the human reviewer decides `CYBERPUN-17-9` may close with AC6 open
- Real second evidence frame for `.mothership/journeys/auto-fire-weapons.json`: PR #45 review found `01-swarm-in-weapon-range.jpg` sharing git blob SHA `55aaeb78dcad6cf478e5342666439a27babb0acf` with `00-weapon-overlay-on-player.jpg`, i.e. one capture committed twice, so the swarm closed onto `RaccoonSeekBehavior.contactStandoffPoints` (inside `WeaponTier.handgun.rangeTiles`) - the whole reason that frame exists, and most of this story's runtime evidence given a probe run can never show a bullet - is the one thing not evidenced. The duplicate has been deleted and `.mothership/evidence/CYBERPUN-17-9-t4/journey-auto-fire-weapons/README.md` records what must be re-captured, following the call made on `CYBERPUN-17-11-t4` after PR #39: an unusable bundle that looks like a complete one invites a reviewer to record the gate as evidenced when it is only asserted. The surviving frame was kept because the weapon-overlay claim is reviewable from those bytes either way. Needs the runtime probe re-run and the genuine second capture committed before the story closes; it is a re-capture, not a source change, so no code edit can satisfy it
- Auto-fire, bullets, weapon overlay and XP/level progression (`CYBERPUN-17-9`) — **the authoritative implemented-vs-outstanding list for this story; read this rather than inferring the remaining scope from `WeaponTier`/`WeaponFiringController`/`TargetSelection`/`BulletPool`/`WeaponOverlayRenderer`'s doc comments, each of which still describes its own PR's slice as though no production caller existed yet.**
  Implemented (`-t1` decision layer, `-t2` rendering, `-t3` composition + scene mount): `WeaponTier` (per-tier fire interval/range/damage plus the `sprite_player_weapons` row and `sprite_bullets` column seams); `TargetSelection.nearestLivingTarget` (tile-space nearest, `isDead` filtered *before* any distance compare so an already-dead target can never be selected, first-wins tie-break); `WeaponFiringController` (the cooldown counts down every frame while only the *fire* is gated on `isMoving`, so standing still can never bank a shot; `setTier` swaps in place without resetting the in-flight cooldown); `BulletPool`/`BulletNode` (fixed-capacity, pre-mounted, per-tier sprite column, `zRotation` set once at fire time from the shot vector against screen-right-authored art); `HitEffects` (muzzle flash = `sprite_hit_puff` frame 0, hit puff animated at the impact point); `WeaponOverlayRenderer` (a `sprite_player_weapons` cell parented to `PlayerNode.body` at construction on the *same* 36x40 cell and anchor, never gated on having a target/kill/level-up, with the body's inherited mirror cancelled from `PlayerSpriteSheet.xScale(for:)` rather than read back off `body.xScale`); `XPLevelSystem` (named level curve + `tier(forLevel:)` — handgun below 3, SMG 3-5, assault rifle 6+, no manual-switch API) and `RunStats` (kill count + cumulative damage for the run summary). `Player` (`Sources/Actors/Player.swift`, a plain reference type, *not* a node) composes all of them and owns bullet flight/hit resolution; `GameScene.startPlayer(at:)` builds it lazily on the first `PlayerNode` mount (reused, `reset()`, across RUN AGAIN) and `advanceMovementAndCamera` drives `playerCombat.update(...)` every `.gameplay` frame from `raccoonSpawnDirector.targetCandidates` — so gunfire, kills, XP and the same-frame level-3/6 tier+overlay swap all happen in a real build, not only under a test double. Two failure modes are pinned rather than claimed: every projected point is converted out of `worldLayer`'s space into `effectsLayer`'s (`PlayerCombatSceneWiringTests` asserts a fired bullet's *scene*-space position lands on the shooter — a child count or an `activeCount` cannot see that bug), and a target that leaves the scene graph mid-flight releases its bullet undamaged instead of leaking it from the pool.
  Outstanding, no invented ticket IDs: AC6's barrel-tip muzzle offset — carried as its own **unmet** bullet above (raised on PR #45, still NO TICKET ID, file one there before closing the story), because a clause inside this paragraph is not a work item and nothing schedules it — the flash spawns at the actor anchor (his feet) until someone measures the muzzle pixel per direction off the shipped `sprite_player_weapons`, deliberately not re-guessed (recorded on `WeaponTier` and at `Player.handleFire`); `WeaponFiringController` exposes no cooldown reset, so a RUN AGAIN mid-cooldown can delay the new run's first shot by up to one `fireIntervalSeconds`; the playtesting retune of every named constant; and the XP/level/kill HUD, which is `CYBERPUN-17-12`'s. **Runtime-probe limit:** `.mothership/journeys/auto-fire-weapons.json` can evidence the always-mounted weapon overlay and the swarm closed into weapon range, but never a bullet/muzzle flash/hit puff — AC1 gates fire on movement (`PlayerMovementController.isMoving` == `StickState.isBeyondDeadZone`) and the probe's iOS step vocabulary has no press-drag-release verb, so the floating thumbstick never leaves its dead zone and auto-fire stays suppressed *by design*. Read that journey's `demonstrates` before reading a bullet-free frame as a missing feature; AC1 end-to-end is owned by `WeaponFiringControllerIntegrationTests`/`PlayerCombatSceneWiringTests`, not by a screenshot
- `CYBERPUN-17-13` death screen / high scores: data layer (`-t1`: `RunScoreCalculator`/`HighScoreStore` - bounded top-10 table, deterministic score-desc/sequence-asc ranking, throwing reads/writes with quarantine-not-overwrite on an unreadable payload, versioned + tolerant decoding, failable `init?(suiteName:)`) and screen content (`-t2`: `DeathScreenNode` renders the real eight-row summary from `GameScene`'s live `runStats`/`playerCombat`/the new `runElapsedSeconds` timer and records it into the new `GameScene.highScoreStore` exactly once per `willEnter()`, never on a rotation-driven `layout()`; `HighScoreStore.recordRun(_:id:)` grew a defaulted `id` param so the caller retains the recorded entry's identity; `HighScoresScreenNode` rebuilds its (variable-count) rows every `willEnter()` from the sorted table and highlights the just-finished run by that retained id via `DeathScreenNode.lastRecordedRunID`, threaded through `GameViewController.makeGameScene`'s composition - matched by id rather than score so a tie still highlights the right row; both screens' pre-existing RUN AGAIN/back-to-menu/high-scores navigation from `CYBERPUN-17-2` is untouched, and the scaffolding markers on both are gone) have both landed; RUN AGAIN's new-seed/new-junction/full-reset (`-t3`) has now also landed - `GameScene.startNewRun()` draws a fresh random `worldSeed` (so `RunSpawnSelector.selectSpawnTile(seed:)` lands on a different street-intersection junction) and transitions straight to `.gameplay` with no menu detour, and every run-scoped counter this story's own systems already reset on a fresh `.gameplay` entry (`RunStats`/`XPLevelSystem`/`RunSummaryStats`/`PlayerNode.resetCombatState()`/`runElapsedSeconds`) needed no further change - `GameViewController`'s `DeathScreenNode.onRunAgain` is the one production caller, so a plain `stateMachine.transition(to: .gameplay)` (the very first PLAY, and this codebase's own scene-wiring tests) still leaves `worldSeed` untouched, deliberately; `-t3` also deleted the DEBUG-only `LaunchGotoState` launch bridge (the two doc references that outlived that file — `CrashDiagnostics.swift`'s `#if DEBUG` exemplar and `AppDelegate`'s gating note — were re-pointed on PR #51 review, so nothing now cites a path that no longer exists), which for a stretch left nothing in any build transitioning to `.death`. **`-t5` closed that gap:** `GameScene.advanceMovementAndCamera(currentTime:)` now transitions to `.death` once per `.gameplay` frame when `player.hp <= 0`, after every HP-affecting update that frame has already applied - the real production entry point the `CYBERPUN-17-8` entry above called for. This story's whole surface (death screen, recorded run, high-scores highlight, RUN AGAIN/`startNewRun()`) is reachable by a player now, pinned by `PlayerDeathTriggerTests` (over a scratch `UserDefaults` suite via `GameViewController.makeGameScene(size:highScoreStore:)`, so a test run never appends a row to the player's real high-score table). Still outstanding, unchanged by `-t5` and not implemented by it: **the SCAFFOLDING marker grep gate** - a grep for `SCAFFOLDING` now comes up clean (this story removed the last literal, its condition genuinely closed), which is exactly why the gate itself is still owed; audio, app icon art, launch screen polish, App Store metadata/submission also remain out of scope
- Game Center/online leaderboards, pause, settings, revives, manual weapon switching (weapons auto-progress per spec)

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
