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
  PrivacyInfo.xcprivacy, *.entitlements
  Atlas/AtlasContract.swift                atlas contract + measurement
  Assets.xcassets/Atlas/                   10 atlas-sheet imagesets (1x only)
  Sources/Assets/TextureLoading.swift      centralized nearest-filtering texture factory
  Resources/Assets.xcassets/               stub AppIcon slot (art not yet imported)
CyberpunkMonsterCrawlTests/
  CyberpunkMonsterCrawlTests.swift         proof-of-life (GameViewController)
  AtlasContractTests.swift                 atlas contract rules + catalog gate
  TextureLoadingTests.swift                nearest-filtering assertion for TextureLoading
docs/bootstrap.md                          original spec (source of truth)
```

## Planned architecture (from docs/bootstrap.md)

- UIKit + single `SKView` host (implemented in this PR)
- Bootstrap `BootScene` showing the project name (implemented in this PR)
- Atlas contract type (`CyberpunkMonsterCrawl/Atlas/AtlasContract.swift`)
  recording each sheet's measured pixel size, cell grid and owned cell
  indices — measured programmatically from the imported image, never
  inferred from filenames — plus the acceptance gate in
  `AtlasContractTests` that fails when any referenced image id is missing
  from the catalog (implemented)
- Asset catalog: the 10 atlas sheets are imported as 1× imagesets under
  `CyberpunkMonsterCrawl/Assets.xcassets/Atlas/` (implemented — asset-import
  PR). The 12 building sprites (`building_00` … `building_11`) are still not
  in the repo, so `AtlasContract.current.sheets` stays empty for now, which
  the contract still reports as a violation — filling in the sheet
  declarations (cell sizes, owned cell indices) and the building imagesets is
  a later PR's job, not this one's
- Central texture loader (`CyberpunkMonsterCrawl/Sources/Assets/TextureLoading.swift`)
  enforcing `.nearest` filtering, no mipmaps (implemented — asset-import PR).
  No production consumer calls it yet; that lands with the sprites/tiles that
  actually render (future PRs)
- `menu → gameplay → death → highScores` state machine (deferred — future PR)
- Scene graph z-layering: `worldLayer < effectsLayer < uiLayer`, `uiLayer`
  pinned to camera with first touch refusal, plus an ordering test
  (deferred — future PR)
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

- Binary asset pack import (remainder): the 12 building PNGs
  (`building_00` … `building_11`) into `Assets.xcassets` as 1× imagesets, plus
  filling `AtlasContract.current.sheets` with each atlas-sheet family's cell
  size and owned cell index list, and deleting the `XCTExpectFailure`
  scaffolding in `AtlasContractTests.test_shippedAssetCatalog_satisfiesAtlasContract`
  — that expectation is strict, so it fails once the full catalog satisfies
  the contract and cannot be left muting the gate. The 10 atlas sheets
  themselves are already imported (this PR); `tileset_structure.png` and the
  HTML companion files were not imported.
- Wiring every real texture consumer (player, raccoons, bullets, pickups,
  pulse, hit puff, signs, ground tiles) through
  `TextureLoading.texture(named:)` as each is built — the factory exists and
  is tested, but nothing in the render path calls it yet
- Menu/gameplay/death/highScores state machine
- Scene z-layering enforcement + ordering test
- Depth module
- Procedural world generation + chunk streaming
- Tile-grid collision system
- UI-test target with real XCUITest coverage
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
