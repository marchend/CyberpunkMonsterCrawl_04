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
  GameViewController.swift                 hosts the SKView
  BootScene.swift                          bootstrap SpriteKit scene
  GameStateMachine.swift                   menu/gameplay/death/highScores GKStateMachine wrapper
  GameScene.swift                          three persistent layers (worldLayer/effectsLayer/uiLayer), state-driven screen registry, UI-first touch routing
  Layers/LayerConstants.swift              named zPosition bands enforcing worldLayer < effectsLayer < uiLayer
  Layers/ScreenNode.swift                  ScreenNode protocol + PlaceholderScreenNode test double (concrete screens land in PR 3)
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
CyberpunkMonsterCrawlTests/
  CyberpunkMonsterCrawlTests.swift         proof-of-life (GameViewController)
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
  LayerOrderingTests.swift                 zPosition ordering invariant (named constants) + live GameScene layer/registry checks
  TouchRoutingTests.swift                  UI-first touch routing: an overlapping UI node always wins over a world node
  GameSceneScreenSwitchingTests.swift      state-machine-driven screen registry swap, using PlaceholderScreenNode doubles
CyberpunkMonsterCrawlUITests/
  CyberpunkMonsterCrawlUITests.swift       proof-of-life (app launches), tagged SCAFFOLDING(CYBERPUN-17-2); real flow coverage lands with the CYBERPUN-17-2 PR that ships concrete screens
docs/bootstrap.md                          original spec (source of truth)
```

> `AGENT.md` and `CLAUDE.md` are the same document under two names. Every edit
> must land in both, byte for byte — `DocumentationParityTests` fails the suite
> if they ever diverge, so the two cannot drift into disagreeing instructions.

## Planned architecture (from docs/bootstrap.md)

- UIKit + single `SKView` host (implemented in this PR)
- Bootstrap `BootScene` showing the project name (implemented in this PR)
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
  production caller as of PR 2 — concrete menu/gameplay/death/highScores
  screens and wiring `GameViewController` to present `GameScene` instead of
  `BootScene` land in PR 3)
- Scene graph z-layering: `worldLayer < effectsLayer < uiLayer`, `uiLayer`
  pinned to the scene's camera with first refusal on every touch, backed by
  named `LayerConstants` and a state-driven `[GameState: ScreenNode]`
  registry that swaps the active screen in `uiLayer` on every
  `GameStateMachine` transition (implemented — `GameScene.swift`,
  `Layers/LayerConstants.swift`, `Layers/ScreenNode.swift`;
  `LayerOrderingTests`, `TouchRoutingTests` and
  `GameSceneScreenSwitchingTests` cover the ordering invariant, UI-first
  touch routing and the registry swap respectively, all via
  `PlaceholderScreenNode` test doubles since no concrete screen exists yet)
- Depth module: painter's-algorithm bands `-(tileX+tileY)*10`, ground plane
  5000 below, building content <+3 in-band, actor offsets 6.5–9.9 sampling
  rounded tile (deferred — future PR)
- Pure-function world generation `(tileX, tileY, seed) → chunk`, 8×8 chunk
  streaming, no cross-chunk neighbour lookups (deferred — future PR)
- Tile-grid collision — no `SKPhysicsBody`; buildings are flat footprints
  on a tile grid (deferred — future PR)
- City lattice: 6-tile period per axis, 3×3 building block ringed by a
  3-tile street corridor that doubles as the navmesh (deferred — future PR)
- Local high-score persistence, no network/Game Center (deferred — future PR)
- `// SCAFFOLDING:` marker convention + grep-based removal gate
  (deferred — future PR)

## Deferred work

- Wiring every real texture consumer (player, raccoons, bullets, pickups,
  pulse, hit puff, signs, ground tiles, buildings) into an actual on-screen
  scene — `TextureLoading.texture(named:)` / `BuildingSprite.texture` exist
  and are tested, but no scene places any sprite yet (later PRs)
- PR 3 (next in CYBERPUN-17-2) — the concrete menu/gameplay/death/highScores
  screens registered with `GameScene.register(_:for:)`, the menu screen's
  working PLAY button, and wiring `GameViewController` to present
  `GameScene` instead of `BootScene`. The layered scene architecture, the
  named zPosition contract, the state-driven screen registry and UI-first
  touch routing are already implemented and unit-tested (PR 2 — see above);
  what remains is real screen content and the composition-root swap
- Depth module
- Procedural world generation + chunk streaming
- Tile-grid collision system
- Real XCUITest flow coverage — lands with the CYBERPUN-17-2 PR that ships
  the concrete screens it exercises (the `CyberpunkMonsterCrawlUITests`
  target exists with a proof-of-life launch test carrying a
  `// SCAFFOLDING(CYBERPUN-17-2)` marker; the acceptance
  assertions — menu screen present, PLAY button hittable, tapping it enters
  gameplay — land with the scenes they exercise)
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
