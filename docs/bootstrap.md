# Bootstrap — CyberpunkMonsterCrawl_04

## What we're building

A portrait-and-landscape iOS survivor game: the player runs through an endless,
procedurally generated neon city, auto-firing at raccoon swarms and surviving as
long as possible. Visual direction is **"Pixel Grit"** — gritty, high-contrast
neon cyberpunk pixel art (weathered surfaces, heavy dark, hot neon rim light).

This is a **rebuild of v1**, which shipped unplayable with an empty asset catalog
and the world node rendering over the UI, while every unit test passed. The
bootstrap must make both of those failure classes structurally hard.

MVP target: a playable game. Audio, app icon, launch screen and App Store
submission furniture are deliberately deferred.

## Stack decisions

- **Swift + SpriteKit, iOS.** Named directly in the brief. SpriteKit gives us the
  2D scene graph, texture atlas slicing and per-node filtering control the pixel
  art demands, without a third-party engine.
- **UIKit app delegate + a single `SKView` host.** One view controller owning the
  scene(s); no SwiftUI in the render path — we need direct control over drawable
  scale and node placement to keep pixels crisp.
- **Portrait AND landscape.** The MVP must support both (the mock set ships both
  variants of all five screens). All HUD layout is safe-area aware and re-lays out
  on rotation.
- **No physics engine for world collision.** Buildings are flat base-diamond
  footprints on a tile grid; collision is a tile query, not `SKPhysicsBody`.
  Visual height must never affect collision, and a tile query makes that
  impossible to get wrong.
- **Pure-function world generation** from `(tileX, tileY, seed)`, with 8×8 chunk
  streaming. No chunk consults its neighbours, so chunks agree at every boundary
  by construction and generation is trivially testable.
- **Whole pre-rendered building sprites, never assembled in code.** The pack ships
  12 complete transparent buildings; the generator only decides WHICH sprite,
  WHERE, and in WHAT depth order. Procedural building geometry is the single
  biggest source of "the render doesn't match the art".
- **1× art only, integer scaling.** `SKTexture.filteringMode = .nearest`, no
  mipmaps, whole-integer scale, every sprite snapped to whole device pixels. No
  `@2x`/`@3x` renditions of pack art — integer nearest-neighbour upscaling of 1×
  pixel art is lossless.
- **Local persistence only** for high scores. No network, no Game Center.

## First runnable shell

1. **Xcode project** (`CyberpunkMonsterCrawl`), iOS app target, Swift, SpriteKit,
   plus a unit-test target and a UI-test target. Repo is currently empty apart
   from a README.
2. **Asset catalog with the pack landed**: the 10 atlas sheets and the 12 building
   sprites imported as imagesets, plus an **atlas contract** type recording each
   sheet's measured dimensions, cell grid and cell indices — measured
   programmatically, never inferred from filenames, with one owning index list per
   family. A test fails if any sheet, cell index or building imageset is missing.
   `tileset_structure.png` and the HTML companion files are **not** imported.
3. **App shell**: launches into a menu in both orientations, with a
   `menu → gameplay → death → highScores` state machine, and a scene graph whose
   layer order is enforced by named z-constants: `worldLayer` < `effectsLayer` <
   `uiLayer`, with `uiLayer` pinned to the camera and given first refusal on every
   touch. A test asserts the UI layer's minimum z exceeds the world's maximum.
4. **Depth module** written before the first renderer PR: painter's-algorithm
   bands of `-(tileX + tileY) * 10`, ground plane 5000 below all bands, building
   content under +3 in-band, actor offsets 6.5–9.9, actors sampling their rounded
   tile.
5. **Central texture loader** applying `.nearest` and no mipmaps, so no consumer
   can forget.
6. **Scaffolding convention**: any temporary label, overlay or debug driver is
   marked `// SCAFFOLDING:` so the final gate story can grep and remove all of it.

World constants for the shell: isometric 2:1 diamonds at **96×48px** (supersedes
the earlier 128×64), 8×8 tile chunks, and a city lattice with a **6-tile period
per axis** — a 3×3 building block ringed by a 3-tile street corridor. The street
corridor **is** the navmesh; every intersection tile is street under every seed.

## Deferred

- Audio and music (never specified in the brief).
- App icon, launch screen, privacy strings, App Store metadata and submission.
- Game Center / online leaderboards — high scores are local.
- Pause, settings, revives, manual weapon switching (weapons auto-progress).
- Additional building art: variety is added by adding sprites to the set, not by
  changing code.