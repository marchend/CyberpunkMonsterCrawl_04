# CYBERPUN-17-21 Fix Plan — Med Kit heal indicator

## Bug
Running over a Med Kit should visibly update the player's HUD health bar
and show a floating "+N" indicator over the player that rises and fades.
Per grooming, the HP/HUD update path (`PickupManager.attemptCollectMedKit`
→ `PlayerNode.heal(_:)` → `GameScene.updatePickups` → `hudLayer?.refresh()`)
already works and is covered by existing tests. The only real gap is that
no floating heal-amount indicator exists anywhere in the codebase.

## Root cause
`GameScene.updatePickups(...)` calls `player?.heal(healedAmount)` on a
successful med-kit collection but produces no visual feedback for it —
there was never a "+N" floating-text node implemented, only the
(already-correct) HP-bar refresh.

## Complexity
Assessed as **simple** (score 2): ~29 LOC of production code across 2
files, no schema/API change, directly reuses an existing pattern
(`HitEffects.swift`'s transient-effect factory + `GameScene`'s
`effectsSpacePoint(fromWorldSpace:)` world→effects conversion helper).

## Changes

### 1. New file: `CyberpunkMonsterCrawl/Sources/Pickups/HealFloatIndicator.swift`
A stateless factory enum, mirroring `HitEffects.swift`'s shape:
- `spawn(healedAmount: Int, at position: CGPoint) -> SKLabelNode`
- Builds a "+<amount>" `SKLabelNode`: `Menlo-Bold`, small/low-key
  `fontSize` (16pt — below `KillCountLabel`'s 20pt HUD text, since this
  draws directly over gameplay), `fontColor = PixelGritPalette.neonAccent`
  (the same cyan already used for the med-kit pickup's own tint).
- Wires its own `SKAction.sequence([.group([moveBy(y: riseDistance,
  duration:), fadeOut(duration:)]), .removeFromParent()])` (rise 36pt,
  duration 0.8s) so the caller only needs to `addChild` the returned node
  — no separate cleanup call required, no leaked/orphaned nodes.

### 2. Edit: `CyberpunkMonsterCrawl/GameScene.swift` — `updatePickups(...)`
In the existing `if let healedAmount = pickupManager.attemptCollectMedKit(...)`
branch:
- Capture `player?.heal(healedAmount)`'s **actually-applied** return value
  (not the raw dice roll — correct behavior when the player is near
  `maxHP`, per `PlayerNode.heal(_:)`'s own documented contract).
- When the applied amount is `> 0`, convert the player's current
  `worldLayer`-space position into `effectsLayer` space via the existing
  `effectsSpacePoint(fromWorldSpace:)` helper (the same conversion
  `HitEffects`'s call sites and `pulseRing` already use), and
  `effectsLayer.addChild(HealFloatIndicator.spawn(healedAmount:at:))`.
- No change to the heal math, the `syncPickupNodes()` call ordering, or
  any other branch of this method.

## Non-goals (per ticket)
- No change to heal math, HP cap, or `PlayerNode.heal(_:)`.
- No change to `HPSegmentBar`/`HUDLayer` internals (HP/HUD path confirmed
  already correct).
- No equivalent floating-number treatment for damage or the garbage-can
  pickup — med-kit heal only.

## Tests (regression coverage this bug should have caught)
- **New** `CyberpunkMonsterCrawlTests/HealFloatIndicatorTests.swift`:
  pins the label's "+N" text for various healed amounts, its small
  font size, and that `spawn(...)` attaches a running action (so a
  caller can rely on self-cleanup).
- **Extended** `CyberpunkMonsterCrawlTests/PickupIntegrationTests.swift`'s
  `test_walkingThePlayerOverASpawnedMedKit_reducesTheManagersActiveCount_andHealsThePlayer`:
  after the real `GameScene.update(_:)` frame resolves the med-kit
  collision, assert a `"+"`-prefixed `SKLabelNode` is mounted under
  `scene.effectsLayer` — proving the indicator is reachable from a live
  scene frame, not just from isolated factory construction.

## Status
Implementation already written in this pass:
- `CyberpunkMonsterCrawl/Sources/Pickups/HealFloatIndicator.swift` (created)
- `CyberpunkMonsterCrawl/GameScene.swift` (edited)
- `CyberpunkMonsterCrawlTests/HealFloatIndicatorTests.swift` (created)
- `CyberpunkMonsterCrawlTests/PickupIntegrationTests.swift` (edited)

Next steps: run the test suite, commit to `claude_fix/cyberpun-17-21`, and
open a PR.
