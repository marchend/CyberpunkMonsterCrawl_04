# CYBERPUN-17-25 — Fix plan

**Bug:** raccoon med kit not rendered properly

## Root cause

PickupNode.init(kind:)'s switch on `kind` only gives `.medKit` the soft radial-glow texture (`medKitGlowTexture`/`makeMedKitGlowCGImage`) added in CYBERPUN-17-18; `.garbageCan` was left constructing `pad` as a flat `SKSpriteNode(color: PixelGritPalette.neonSecondary, size: padSize)`, which renders as a hard-edged magenta square instead of a glow, exactly as CYBERPUN-17-18's own code comments called out as "out of scope for that ticket".

## Plan

## Fix Plan — CYBERPUN-17-25

**Root cause:** `PickupNode.init(kind:)`'s pad-construction switch only grants `.medKit` the CYBERPUN-17-18 soft radial-glow texture (`medKitGlowTexture`/`makeMedKitGlowCGImage`); `.garbageCan` still falls through to a flat `SKSpriteNode(color: PixelGritPalette.neonSecondary, size: padSize)`, which renders as the reported hard-edged magenta square instead of a glow. `neonSecondary`'s value is correct and must not change — only the pad's *shape* needs to match `medKit`'s treatment.

**Changes — `CyberpunkMonsterCrawl/Sources/Pickups/PickupNode.swift`:**
1. Generalize `makeMedKitGlowCGImage()` into `makeGlowCGImage(accent color: SKColor) -> CGImage?`, replacing the hardcoded `padColor(for: .medKit)` read with the `color` parameter — the radial-gradient drawing logic itself is unchanged.
2. Replace the single `medKitGlowTexture` closure with a shared `makeGlowTexture(forColor:) -> SKTexture` helper (builds the `CGImage`, wraps it in an `SKTexture`, stamps `.nearest`/no-mipmaps, falls back to a blank texture on failure — identical to today's behavior) and two static lets: `medKitGlowTexture = makeGlowTexture(forColor: padColor(for: .medKit))` and `garbageCanGlowTexture = makeGlowTexture(forColor: padColor(for: .garbageCan))`.
3. Add `garbageCanGlowCGImageForTesting()` test seam mirroring `medKitGlowCGImageForTesting()`.
4. In `init(kind:)`, change the `.garbageCan` case to `pad = SKSpriteNode(texture: Self.garbageCanGlowTexture, size: Self.padSize)`.
5. Correct the now-stale doc comments (on `pad` and above the `switch`) that describe `garbageCan` as "out of scope for CYBERPUN-17-18" and flat-filled — state both kinds now share the glow treatment, differing only by base color.

**Tests — `CyberpunkMonsterCrawlTests/PickupNodeTests.swift`:**
- Rewrite `test_garbageCanPad_isAccentTinted` → `test_garbageCanPad_isGlowTextured_notAFlatColorFill`, asserting `pad.texture != nil`, `colorBlendFactor == 0`, `size == padSize` (mirrors the existing `medKit` structural test).
- Update `test_medKitAndGarbageCan_useDistinctPadTreatments` to assert both pads are textured but use distinct texture identities (`!==`) rather than one textured/one nil.
- Add `test_garbageCanPad_glowTexture_hasSoftRadialFalloff_notAHardSquare`, mirroring `test_medKitPad_glowTexture_hasSoftRadialFalloff_notAHardSquare`, sampling `PickupNode.garbageCanGlowCGImageForTesting()` via the existing shared `alpha(atX:y:in:)` helper to confirm center alpha > corner alpha and corner alpha is near-transparent.
- No changes needed to `medKit`'s existing tests — non-goal preserved.

**Non-goals:** no change to `medKit`'s glow, no change to `neonSecondary`'s RGB value, no new pickup kinds or API surface.
