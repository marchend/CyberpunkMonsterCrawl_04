# Bootstrap Plan — CyberpunkMonsterCrawl

## In scope (this PR)

**Project:** iOS app, Swift + SpriteKit, UIKit app delegate hosting a single
`SKView`. This PR ships the smallest runnable shell that proves the
XcodeGen → Xcode → SpriteKit toolchain works end-to-end: the app builds,
launches to one visible screen showing the project name, and one unit test
passes against the test target.

**Tech-stack decisions (from docs/bootstrap.md):**
- Language: Swift, iOS 17 deployment target
- Framework: SpriteKit (no SwiftUI in render path), UIKit app delegate
- Project generation: XcodeGen (`project.yml`) — no hand-crafted `.xcodeproj`
- Test framework: XCTest (unit test target only for bootstrap; UI-test
  target is future work, not declared empty per hard rule against empty
  test bundles)

**Directory structure:**
```
CyberpunkMonsterCrawl/
├── project.yml
├── setup.sh
├── .gitignore
├── docs/
│   └── bootstrap.md
├── bootstrap_plan.md
├── CLAUDE.md
├── AGENT.md
├── CyberpunkMonsterCrawl/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── GameViewController.swift        (hosts the SKView)
│   ├── BootScene.swift                 (trivial SKScene, shows project name)
│   ├── PrivacyInfo.xcprivacy
│   ├── CyberpunkMonsterCrawl.entitlements
│   └── Resources/
│       └── Assets.xcassets/
│           ├── Contents.json
│           └── AppIcon.appiconset/
│               └── Contents.json
└── CyberpunkMonsterCrawlTests/
    └── CyberpunkMonsterCrawlTests.swift
```

**Files this PR creates** (every one directly supports Hello World):
- `project.yml` — XcodeGen spec: app target + unit-test target, iOS 17,
  code-signing disabled for CI, entitlements wired, `parallelizable: false`.
- `AppDelegate.swift` / `SceneDelegate.swift` — standard UIKit scene wiring
  (no Info.plist file; synthesised via `GENERATE_INFOPLIST_FILE`).
- `GameViewController.swift` — creates an `SKView`, presents `BootScene`.
- `BootScene.swift` — a single `SKScene` with `.nearest` texture filtering
  set as the shell's central-loader convention starting point, and one
  `SKLabelNode` reading "CyberpunkMonsterCrawl".
- `PrivacyInfo.xcprivacy`, `<target>.entitlements`, `Assets.xcassets` stub —
  required CI-hardening boilerplate per bootstrap policy.
- `CyberpunkMonsterCrawlTests.swift` — one XCTest instantiating
  `GameViewController` to prove the test target links against the app
  module.
- `.gitignore`, `setup.sh` — XcodeGen materialisation helpers.
- `CLAUDE.md` / `AGENT.md` — project docs, planned architecture, deferred
  work, git workflow.

**How to run locally:** `./setup.sh` (installs XcodeGen if missing, runs
`xcodegen generate`, opens the project in Xcode). Build/run the
`CyberpunkMonsterCrawl` scheme on a simulator.

**How to run tests:** In Xcode, run the `CyberpunkMonsterCrawlTests` target
(Cmd+U), or `xcodebuild test -scheme CyberpunkMonsterCrawl`.

**Definition of Hello World:** App launches to a single SpriteKit scene
showing the label "CyberpunkMonsterCrawl" on screen (portrait or landscape),
and one unit test passes proving the test target compiles and links.

## Out of scope — deferred to future work

- Asset catalog import of the 10 atlas sheets + 12 building sprites, and the
  programmatically-measured atlas contract type — future PR.
- Menu → gameplay → death → highScores state machine — future PR.
- Scene graph z-layering (`worldLayer` / `effectsLayer` / `uiLayer`) and the
  associated ordering test — future PR.
- Depth module (painter's-algorithm bands, ground plane offset, actor tile
  sampling) — future PR.
- Central texture loader enforcing `.nearest` filtering / no mipmaps across
  all consumers — future PR (bootstrap only demonstrates the setting once).
- Pure-function world generation (`(tileX, tileY, seed)` → chunk), 8×8 chunk
  streaming, 6-tile city lattice period — future PR.
- Tile-grid collision (no `SKPhysicsBody`) — future PR.
- UI-test target with real XCUITest coverage — future PR.
- Local high-score persistence — future PR.
- `// SCAFFOLDING:` marker convention enforcement / grep gate — future PR.
- Audio, app icon art, launch screen, privacy strings beyond the stub
  manifest, App Store submission — explicitly deferred per the spec itself.
- Game Center / online leaderboards, pause, settings, revives, manual
  weapon switching — explicitly deferred per the spec itself.
