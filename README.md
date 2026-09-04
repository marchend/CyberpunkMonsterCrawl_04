# CyberpunkMonsterCrawl_04

A portrait-and-landscape iOS survivor game: the player runs through an
endless, procedurally generated neon city, auto-firing at raccoon swarms and
surviving as long as possible. Visual direction is "Pixel Grit" — gritty,
high-contrast neon cyberpunk pixel art.

Swift + SpriteKit, UIKit app delegate hosting a single `SKView` (no SwiftUI
in the render path — see `docs/bootstrap.md`). See `AGENT.md` / `CLAUDE.md`
for the full architecture and deferred-work notes.

## Prerequisites

- Xcode 15+ (iOS 17 deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Setup

The `.xcodeproj` is generated, not committed — run this after cloning (and
again any time `project.yml` changes):

```
./setup.sh
```

This installs XcodeGen if it's missing, runs `xcodegen generate`, and opens
the generated project in Xcode. Manual equivalent:

```
brew install xcodegen
xcodegen generate
open CyberpunkMonsterCrawl.xcodeproj
```

Build/run the `CyberpunkMonsterCrawl` scheme on an iOS simulator.

## Tests

Cmd+U in Xcode on the `CyberpunkMonsterCrawl` scheme, or:

```
xcodebuild test -scheme CyberpunkMonsterCrawl
```
