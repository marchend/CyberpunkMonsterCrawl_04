# CYBERPUN-17-18 Fix Plan — Med kit pad glow

## Bug

Med kit pickups render with a flat, hard-edged cyan square pad behind the
icon instead of a soft glow, making the pickup look like it's "embedded in
a cyan square" (reported for raccoons/player, but ground pickups have a
single shared rendering path — `PickupNode` — so there is no separate
raccoon/player-held visual to touch).

## Root cause

`PickupNode.pad` is built as an opaque, flat-color `SKSpriteNode(color:size:)`
40×40pt fill (`padColor(for:)` → `PixelGritPalette.neonAccent` for med
kits). It carries no alpha falloff, gradient, or texture, so it renders as a
hard-edged solid box rather than a glow.

## Scope

- **In scope:** `PickupKind.medKit`'s pad visual only, in
  `CyberpunkMonsterCrawl/Sources/Pickups/PickupNode.swift`.
- **Out of scope:** `PickupKind.garbageCan`'s pad (`neonSecondary`, stays a
  flat color fill, untouched), the icon sprite (content/position/size/bob
  animation/depth-sorting), and `PickupManager` spawn/collection/lifetime
  logic.

## Changes

### `CyberpunkMonsterCrawl/Sources/Pickups/PickupNode.swift`

1. Add a private static factory, e.g.
   `private static func makeMedKitGlowTexture() -> SKTexture`, that
   procedurally bakes a **40×40-pixel** `CGImage` (via `CGContext`)
   containing a pixel-stepped (hard-banded, non-antialiased) radial alpha
   falloff of `PixelGritPalette.neonAccent` — concentric square/diamond
   rings of decreasing alpha from center to edge. This stays consistent
   with the project's no-antialiasing pixel-art convention (cf.
   `ActorShadowNode`'s explicit `isAntialiased = false`) rather than
   introducing a smooth/blurred gradient foreign to the rest of the game's
   rendering.
2. Build the `SKTexture` via `SKTexture(cgImage:)` (not
   `SKTexture(image:)`) so `.size()` is deterministically `(40, 40)`
   points regardless of device/screen scale — this keeps the pad's
   effective magnification at exactly 1x (`node.pad.size / texture.size()
   == 1`), so no new `PixelCrispnessSweepTests` exemption/`accepted`
   parameter is needed.
3. Cache the texture once as `private static let medKitGlowTexture`
   (same hoisted-static pattern `cachedSheet`/`textureCache` already use
   in this file).
4. In `init(kind:)`, branch pad construction by `kind`:
   - `.medKit` → `SKSpriteNode(texture: Self.medKitGlowTexture, color: .clear, size: Self.padSize)`.
     The texture carries the tint; `colorBlendFactor` stays at its
     default `0` so the baked pixel colors show through untouched, the
     same "untinted, texture is the whole visual" convention the icon
     already follows.
   - `.garbageCan` → unchanged:
     `SKSpriteNode(color: Self.padColor(for: kind), size: Self.padSize)`.
5. `padColor(for:)` is unchanged (still used for the garbageCan branch).
   `pad.zPosition`, the existing `PixelCrispness.apply(to: pad)` call,
   add order, and the bob animation (`icon`-only) are all unchanged.

## Tests

### `CyberpunkMonsterCrawlTests/PickupNodeTests.swift`

- `test_pad_isAccentTinted`: branch assertion per kind —
  - `.garbageCan`: keep the existing `pad.color != .clear` assertion.
  - `.medKit`: assert `pad.texture != nil` instead (the tint now lives in
    the baked texture, not `.color`, which is `.clear` by construction).
- `test_medKitAndGarbageCan_useDistinctPadAccentColors`: leave the
  assertion as-is (still mechanically true: `.clear != neonSecondary`),
  but add a short comment noting kind-distinctness is now also carried by
  texture identity for medKit, not just `.color`.
- **New regression test** (the test that should have caught this bug),
  e.g. `test_medKitPad_isTextureBacked_withExactPadSizeMagnification`:
  - `node.pad.texture` is non-nil for `.medKit`.
  - `node.pad.texture?.filteringMode == .nearest` and
    `usesMipmaps == false`.
  - `node.pad.texture!.size() == PickupNode.padSize` exactly — pins the
    1x-magnification invariant the whole fix relies on, so a future
    change can't silently reintroduce a non-integer magnification (which
    would require a `PixelCrispnessSweepTests` exemption) without this
    test going red first.

### `CyberpunkMonsterCrawlTests/PixelCrispnessSweepTests.swift`

- No functional change expected: `assertPixelCrisp(node.pad, ...)` in
  `test_pickupNode_icon_isPixelCrisp_forEveryKind` already handles a
  textured node generically (nearest-filtering check +
  `assertEffectiveMagnification`), and since the new texture reports
  `.size() == padSize`, magnification resolves to exactly `1x` — already
  within the default (non-exempted) integer rule.
- Optional: tighten the stale comment "`pad` is an untextured color
  fill -- `assertPixelCrisp` skips the (vacuous) filtering checks for it"
  to clarify that this is now only true for `garbageCan`'s pad.

## Non-goals (explicitly preserved)

- No change to garbage can rendering.
- No change to spawn/collection/lifetime logic (`PickupManager`).
- No new raccoon- or player-specific pickup visuals — ground pickups stay
  a single shared `PickupNode` type.

## Verification

- `code_run_tests` (backend/iOS native toolchain is not available in this
  container — this call is expected to skip/no-op and must not be read as
  a substitute for the real merge-gate suite run).
- Manual code read-through confirming:
  - `medKitGlowTexture.size() == PickupNode.padSize` exactly (pixel-exact
    CGImage dimensions, no scale-factor surprises from `UIImage`/
    `UIGraphicsImageRenderer`).
  - `garbageCan`'s pad construction byte-for-byte unchanged.
  - `PickupNodeTests` and `PixelCrispnessSweepTests` updated/added as
    above, consistent with each other and with the acceptance criteria.
