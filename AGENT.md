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
  Sources/World/IsometricProjection.swift  tileToScreen/screenToTile at 96x48 tile size, TilePoint tile-space type, tile(containing:) diamond-ownership rule; Double math with a CGFloat cast only at the boundary
  Sources/World/SeedMixer.swift            explicit splitmix64-style bit mixer over (seed, tileX, tileY), wrapping arithmetic only - never Hasher/.hashValue, which is randomized per process
  Sources/World/WorldSeed.swift            thin UInt64-wrapping per-run seed type: "a run is fully described by its seed"
  Sources/World/TileKind.swift             asphalt/junctionStopLine/kerbSidewalk/lot/buildingFootprint + isWalkable (asphalt, sidewalk, stop-line and empty lot walkable; building footprint solid)
  Sources/World/CityLatticeGenerator.swift pure classify(tileX:tileY:seed:) -> TileInfo: 6-tile period, 3x3 block + 3-tile street corridor, intersections structurally always street (seed never reaches street tiles), ~1-in-4 empty-lot decision made once per block via SeedMixer
CyberpunkMonsterCrawlTests/
  CyberpunkMonsterCrawlTests.swift         proof-of-life (GameViewController)
  IsometricProjectionTests.swift           round-trip sweep (-50...50, both axes, incl. negatives) over tileToScreen/screenToTile + off-centre and on-seam cases pinning tile(containing:)
  CityLatticeGeneratorTests.swift          6-tile period test, intersection-always-street test, ~1-in-4 empty-lot-ratio test, per-block decision consistency, determinism
  ConnectivityTests.swift                  flood-fill over classify's walkable output across >=20 seeds and a 12x12-block region, reaching every intersection tile; private BFS helper over a Set<Coord>
  ConcurrencyDeterminismTests.swift        dispatches classify for the same and for many distinct (tileX, tileY, seed) inputs across DispatchQueue.concurrentPerform and asserts every result matches a single-threaded reference
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
  GameViewControllerCompositionTests.swift composition root builds GameScene, mounts MenuScreenNode + the three skeleton screens, wires PLAY to the state machine
CyberpunkMonsterCrawlUITests/
  CyberpunkMonsterCrawlUITests.swift       menu present + PLAY hittable + tapping it starts a run and lands on the gameplay screen
  AppLaunchAndRotationUITests.swift        launch shows the menu in portrait, rotation re-lays it out in landscape with nothing off-screen, PLAY dismisses the menu
docs/bootstrap.md                          original spec (source of truth)
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
  `worldLayer` \u2014 a full-bleed backdrop there would swallow every touch and
  paint over `worldLayer`. Menu/death/high-scores backdrops are full-bleed on
  purpose (they hide the world); the scene's own `backgroundColor` supplies
  the dark base behind gameplay
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
  `IsometricProjectionTests`). No production consumer places a tile-space
  node via it yet; that lands with the ground-plane/depth-model PR
- Depth module: painter's-algorithm bands `-(tileX+tileY)*10`, ground plane
  5000 below, building content <+3 in-band, actor offsets 6.5–9.9 sampling
  rounded tile (deferred — future PR)
- Pure-function per-tile world generation `(tileX, tileY, seed) → TileInfo`
  (implemented — `Sources/World/CityLatticeGenerator.swift`,
  `Sources/World/SeedMixer.swift`, `Sources/World/WorldSeed.swift`,
  `Sources/World/TileKind.swift`). Wrapping this into 8×8 chunks with
  camera-driven streaming and no cross-chunk neighbour lookups is deferred
  — `CYBERPUN-17-3-t3`. CYBERPUN-17-3 is deliberately split in three: `-t1`
  shipped the isometric coordinate transform, `-t2` ships the pure seeded
  city-lattice function below, `-t3` wraps it into chunks and streaming
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
  determinism contracts, `ConnectivityTests` flood-fills the walkable
  output across >=20 seeds and a 12x12-block region and reaches every
  intersection tile, and `ConcurrencyDeterminismTests` proves thread safety.
  Chunk-boundary agreement (AC2) and the bounded resident-chunk window
  (AC8) are `CYBERPUN-17-3-t3`'s concern once chunking exists — this PR is
  scoped to the pure per-tile function only, no chunking, no streaming
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
- Depth module
- Chunk assembly (8×8), lot-reservation hooks and camera-driven chunk
  streaming with a bounded resident-chunk window — tracked as
  `CYBERPUN-17-3-t3` (the third of CYBERPUN-17-3's three PRs; `-t1` shipped
  the coordinate transform, `-t2` shipped the pure seeded city-lattice
  function itself)
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
