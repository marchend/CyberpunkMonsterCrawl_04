# CYBERPUN-17-20 Fix Plan — "Enemies start too far"

## Root cause
`RaccoonSpawnDirector`'s tunable constants (`initialSpawnInterval = 3.0s`,
`farAxisMinimumTiles = 40`) are far more conservative than the off-screen
invariant actually requires, producing an ~11.7s floor before any enemy
can be visible to the player:

```
floor = initialSpawnInterval (3.0s)
      + offScreenGapTiles (40 - 18 = 22 tiles) * tileHalfWidth (48pt/tile)
        / RaccoonSeekBehavior.pointsPerSecond (~120.75 pts/s)
      ≈ 3.0 + 8.73 ≈ 11.73s
```

## Changes
File: `CyberpunkMonsterCrawl/Sources/Spawning/RaccoonSpawnDirector.swift`

1. `initialSpawnInterval: TimeInterval = 3.0` → `1.0`
2. `farAxisMinimumTiles: Double = 40` → `33`
3. `farAxisMaximumTiles: Double = 56` → `49` (keeps the original 16-tile spread)
4. `nearAxisRange` left unchanged at `-15...15`
5. Updated the doc comment above `farAxisMinimumTiles` that walks through the
   worked numbers: `40 - (15+3) = 22` tiles / `1,056` pts → `33 - (15+3) = 15`
   tiles / `720` pts; and "roughly the first 16-32 tiles" (of obstruction-free
   walk) → "roughly the first 9-25 tiles" (`farAxisMinimumTiles`/`farAxisMaximumTiles`
   minus `ChunkStreamingManager.guaranteedMarginTiles` = 24).

## Resulting floor
```
floor = 1.0 + (33 - 18) tiles * 48pt / 120.75pt/s
      = 1.0 + 15 * 48 / 120.75
      = 1.0 + 5.96 ≈ 6.96s
```
Matches the ~7s target from the acceptance criteria.

## Off-screen guarantee preserved
- Existing documented proof: `offScreenGapTiles * tileHalfWidth = 15 * 48 = 720pt`,
  which still exceeds half the width of the largest supported viewport
  (`ChunkStreamingManager.referenceViewportPoints`, 683pt).
- Independently verified via the exact two-axis geometry (`screenX = (dx-dy)*48`,
  `screenY = (dx+dy)*24` against half-width 683pt / half-height 512pt): a spawn is
  guaranteed off-screen for *any* near-axis draw whenever the far-axis magnitude
  exceeds ≈17.8 tiles. `farAxisMinimumTiles = 33` clears that threshold with a
  large margin, independent of `nearAxisRange`, so
  `RaccoonSpawnDirectorTests.test_selectSpawnTile_isNeverOnScreen_fortheLargestSupportedViewport`
  (500 random samples against the real `isOnScreen` check) holds comfortably.

## Tests
No test file edits required:
- `JourneyManifestTests.secondsBeforeARaccoonCanBeOnScreen` derives the floor
  dynamically from these same production constants (string-interpolated, no
  hardcoded literals), so it recomputes automatically to ~6.96s and all
  dependent assertions (`test_aJourneyExistsForThisStorysCombatWork_...`,
  `test_theOnScreenFloor_isStrictlyStrongerThanTheSpawnIntervalAlone`, the
  death-floor ordering check) keep passing.
- Existing journey JSON wait times (e.g. the raccoon-swarm journey's 30s wait)
  only need to satisfy `waitSeconds >= floor`; a *lower* floor only adds
  margin, never breaks this check.
- `RaccoonSpawnDirectorTests` reads the constants dynamically too, so no
  hardcoded-value tests needed updating.

## Status
Code changes implemented in `RaccoonSpawnDirector.swift` (see commit on
`claude_fix/cyberpun-17-20`). This document records the rationale and the
verification math for reviewers.
