import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 1: `PickupNode` -- standalone SpriteKit composition
/// (untinted icon over a tinted pad), size, and depth-sort conformance, with
/// no scene mount.
final class PickupNodeTests: XCTestCase {

    // MARK: - Icon untinted, pad accent-tinted

    func test_icon_carriesNoTint() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertEqual(node.icon.colorBlendFactor, 0, "\(kind)'s icon must carry zero color blend")
            assertColorsMatch(
                node.icon.color, .clear,
                "\(kind)'s icon must carry no tint color"
            )
        }
    }

    /// Component-wise color comparison, with tolerance.
    ///
    /// `SKSpriteNode.color` round-trips through SpriteKit's own storage, so
    /// a color assigned as `.clear` (`UIExtendedGrayColorSpace 0 0`) can read
    /// back in a different, but numerically equivalent, color space
    /// (`UIExtendedSRGBColorSpace 0 0 0 0`) - both are fully transparent
    /// black, just represented in different models. `XCTAssertEqual` on the
    /// `UIColor`/`SKColor` objects themselves fails on that representation
    /// difference alone, not on any actual color discrepancy, so the
    /// comparison is done on extracted RGBA components instead.
    private func assertColorsMatch(
        _ lhs: SKColor, _ rhs: SKColor, _ message: String = "", accuracy: CGFloat = 1e-6,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        XCTAssertEqual(lr, rr, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lg, rg, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lb, rb, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(la, ra, accuracy: accuracy, message, file: file, line: line)
    }

    /// `CYBERPUN-17-25`: `garbageCan`'s pad moved from a flat
    /// `neonSecondary` color fill to a soft radial-glow texture (see
    /// `test_garbageCanPad_glowTexture_hasSoftRadialFalloff_notAHardSquare`
    /// below for the actual shape assertion) -- the same treatment
    /// `CYBERPUN-17-18` gave `medKit`'s pad.
    func test_garbageCanPad_isGlowTextured_notAFlatColorFill() {
        let node = PickupNode(kind: .garbageCan)
        XCTAssertNotNil(node.pad.texture, "garbageCan's pad must use the glow texture, not a flat color fill")
        XCTAssertEqual(node.pad.colorBlendFactor, 0, "garbageCan's pad must not additionally tint its glow texture")
        XCTAssertEqual(node.pad.size, PickupNode.padSize)
    }

    /// `CYBERPUN-17-18`: medKit's pad moved from a flat `neonAccent` color
    /// fill to a soft radial-glow texture (see
    /// `test_medKitPad_glowTexture_hasSoftRadialFalloff_notAHardSquare`
    /// below for the actual shape assertion); this pins the structural
    /// change -- textured, untinted, sized to `padSize` -- that the old
    /// `.color`-based assertion could no longer express.
    func test_medKitPad_isGlowTextured_notAFlatColorFill() {
        let node = PickupNode(kind: .medKit)
        XCTAssertNotNil(node.pad.texture, "medKit's pad must use the glow texture, not a flat color fill")
        XCTAssertEqual(node.pad.colorBlendFactor, 0, "medKit's pad must not additionally tint its glow texture")
        XCTAssertEqual(node.pad.size, PickupNode.padSize)
    }

    func test_medKitAndGarbageCan_useDistinctPadTreatments() {
        let medKit = PickupNode(kind: .medKit)
        let garbageCan = PickupNode(kind: .garbageCan)
        XCTAssertNotNil(medKit.pad.texture, "medKit's pad must be textured (the glow)")
        XCTAssertNotNil(garbageCan.pad.texture, "garbageCan's pad must be textured (the glow, CYBERPUN-17-25)")
        XCTAssertFalse(
            medKit.pad.texture === garbageCan.pad.texture,
            "medKit and garbageCan must use their own distinct glow textures (different accent colors)"
        )
    }

    /// Pins AC2 ("use `neonSecondary` as the glow's base color, same accent
    /// as today") as a *measured* fact rather than leaving it to the
    /// `=== `-identity check above, which can never fail for a color reason
    /// (`makeGlowTexture(forColor:)` always returns two distinct `SKTexture`
    /// instances, whatever color each is built from). Samples each glow's
    /// center pixel -- opaque per `makeGlowCGImage(accent:)`'s "opaque at
    /// the center, fading to transparent" contract, so no premultiply
    /// correction is needed there -- straight off the same `CGImage` the
    /// production texture is built from (PR #83 review).
    func test_medKitAndGarbageCanGlows_useTheirOwnAccentColor() throws {
        let medKitImage = try XCTUnwrap(
            PickupNode.medKitGlowCGImageForTesting(),
            "the medKit glow image must be constructible from its fixed, valid CoreGraphics configuration"
        )
        let garbageCanImage = try XCTUnwrap(
            PickupNode.garbageCanGlowCGImageForTesting(),
            "the garbage can glow image must be constructible from its fixed, valid CoreGraphics configuration"
        )

        let medKitCenter = try XCTUnwrap(
            rgba(atX: medKitImage.width / 2, y: medKitImage.height / 2, in: medKitImage),
            "medKit center pixel must be sampleable"
        )
        let garbageCanCenter = try XCTUnwrap(
            rgba(atX: garbageCanImage.width / 2, y: garbageCanImage.height / 2, in: garbageCanImage),
            "garbageCan center pixel must be sampleable"
        )

        assertColorsMatch(
            SKColor(
                red: CGFloat(medKitCenter.r) / 255, green: CGFloat(medKitCenter.g) / 255,
                blue: CGFloat(medKitCenter.b) / 255, alpha: CGFloat(medKitCenter.a) / 255
            ),
            PixelGritPalette.neonAccent,
            "medKit's glow must be tinted with neonAccent at its (opaque) center",
            accuracy: 1.0 / 255.0
        )
        assertColorsMatch(
            SKColor(
                red: CGFloat(garbageCanCenter.r) / 255, green: CGFloat(garbageCanCenter.g) / 255,
                blue: CGFloat(garbageCanCenter.b) / 255, alpha: CGFloat(garbageCanCenter.a) / 255
            ),
            PixelGritPalette.neonSecondary,
            "garbageCan's glow must be tinted with neonSecondary at its (opaque) center",
            accuracy: 1.0 / 255.0
        )
    }

    // MARK: - Icon size

    func test_iconSize_is32x32Points() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertEqual(node.icon.size, CGSize(width: 32, height: 32))
        }
    }

    // MARK: - Icon slice: the right atlas column per kind

    func test_icon_usesTheMeasuredSheetsColumnForItsKind() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)
            XCTAssertTrue(node.icon.texture === PickupNode.texture(forColumn: kind.atlasColumn))
        }
    }

    func test_medKitAndGarbageCan_useDifferentAtlasColumns() {
        XCTAssertNotEqual(PickupKind.medKit.atlasColumn, PickupKind.garbageCan.atlasColumn)
        XCTAssertFalse(
            PickupNode.texture(forColumn: PickupKind.medKit.atlasColumn)
                === PickupNode.texture(forColumn: PickupKind.garbageCan.atlasColumn)
        )
    }

    // MARK: - Pixel crispness

    /// Pixel-crispness of the icon and pad, restated so it measures what it
    /// claims.
    ///
    /// This replaces `PixelCrispness.isIntegerScale(icon.xScale)`
    /// assertions that were trivially true: all of the icon's magnification
    /// lives in `SKSpriteNode.size` (`PickupNode.iconSize`), so
    /// `xScale`/`yScale` are always exactly 1 and the assertion read as
    /// coverage of a draw scale it never saw -- the same vacuity
    /// `RaccoonNodeTests.test_body_isPixelCrisp_andCarriesNoMagnificationInItsScale`
    /// was written to replace. The invariant actually worth pinning is that
    /// no magnification ever reaches the scale properties (which is what
    /// stops `PixelCrispness.apply(to:)` rounding it), with the effective
    /// magnification pinned separately below.
    func test_iconAndPad_arePixelCrisp_andCarryNoMagnificationInTheirScale() {
        for kind in PickupKind.allCases {
            let node = PickupNode(kind: kind)

            XCTAssertEqual(node.icon.texture?.filteringMode, .nearest)
            XCTAssertEqual(node.icon.texture?.usesMipmaps, false)

            XCTAssertEqual(
                abs(node.icon.xScale), 1, accuracy: 1e-6,
                "\(kind): the icon's xScale must never carry magnification."
            )
            XCTAssertEqual(
                abs(node.icon.yScale), 1, accuracy: 1e-6,
                "\(kind): the icon's yScale must never carry magnification."
            )
            XCTAssertEqual(abs(node.pad.xScale), 1, accuracy: 1e-6, "\(kind): the pad's xScale must be unscaled.")
            XCTAssertEqual(abs(node.pad.yScale), 1, accuracy: 1e-6, "\(kind): the pad's yScale must be unscaled.")
        }
    }

    /// The story's 32pt icon stated as the *effective* magnification (the
    /// measured source cell to the drawn size) rather than as an `xScale`
    /// that never carries it.
    ///
    /// The icon is deliberately **outside** `PixelCrispness`'s
    /// integer-scale rule: 32/24 is 1.333x, so the compositor resamples the
    /// source pixels unevenly. That trade is the story's, documented on
    /// `PickupNode.iconSize`, and pinned here so nobody reads the crispness
    /// test above as a promise the magnification is integral.
    func test_icon_effectiveMagnification_isTheStorys32ptIconOverTheMeasured24pxCell() throws {
        let cellSize = try XCTUnwrap(
            AtlasSheet.pickups.sheet.cellSize,
            "sprite_pickups must declare a uniform cell size for this magnification to be meaningful"
        )
        let node = PickupNode(kind: .medKit)

        let horizontal = node.icon.size.width / cellSize.width
        let vertical = node.icon.size.height / cellSize.height

        XCTAssertEqual(
            horizontal, 32.0 / 24.0, accuracy: 1e-6,
            "The icon's drawn width (\(node.icon.size.width)) is not the story's 32pt over the measured "
                + "\(cellSize.width)px cell."
        )
        XCTAssertEqual(
            vertical, 32.0 / 24.0, accuracy: 1e-6,
            "The icon's drawn height (\(node.icon.size.height)) is not the story's 32pt over the measured "
                + "\(cellSize.height)px cell."
        )

        XCTAssertFalse(
            PixelCrispness.isIntegerScale(horizontal),
            "The icon's \(horizontal)x magnification is non-integer by design (docs on PickupNode.iconSize). "
                + "If it has become integral, the opt-out documented there is stale and should be removed "
                + "rather than this assertion."
        )
    }

    // MARK: - Depth-sort conformance

    /// The depth-sort key must place a pickup above the ground plane at the
    /// same tile -- the same "actor draws above ground" invariant every
    /// other world-space actor in this repo (`PlayerNode`, `RaccoonNode`)
    /// satisfies via `DepthBanding`.
    func test_updateDepth_placesThePickupAboveTheGroundPlane_atTheSameTile() {
        let node = PickupNode(kind: .medKit)
        let position = TilePoint(x: 14, y: -6)

        node.updateDepth(atTilePosition: position)

        let groundAbsoluteZ = DepthModel.groundZPosition(forTile: TileCoordinate(tileX: 14, tileY: -6))
        let groundRelativeZ = DepthModel.worldLayerRelativeZ(forAbsoluteZ: groundAbsoluteZ)

        XCTAssertGreaterThan(node.zPosition, groundRelativeZ)
    }

    /// The depth-sort key must resolve via `DepthBanding
    /// .nonPlayerActorOffsetRange` exactly the way `RaccoonNode` does, so a
    /// pickup and a synthetic building sharing the same tile draw in the
    /// correct relative order: the building's content offset
    /// (`IsometricDepthSorting`, inside `DepthModel.buildingContentRange`,
    /// strictly `< 3`) must always resolve *behind* the pickup's actor
    /// offset (`DepthModel.actorOffsetRange`, `6.5...9.9`).
    func test_updateDepth_placesThePickupAboveASyntheticBuildingAtTheSameTile() {
        let node = PickupNode(kind: .garbageCan)
        let tile = TileCoordinate(tileX: 3, tileY: 9)
        let position = TilePoint(x: Double(tile.tileX), y: Double(tile.tileY))

        node.updateDepth(atTilePosition: position)

        let buildingAbsoluteZ = IsometricDepthSorting.zPosition(forBuildingFarCornerTile: tile)
        let buildingRelativeZ = DepthModel.worldLayerRelativeZ(forAbsoluteZ: buildingAbsoluteZ)

        XCTAssertGreaterThan(
            node.zPosition, buildingRelativeZ,
            "a pickup must draw above a building occupying the same tile"
        )
    }

    /// Pins the exact value, the same way `PlayerDepthTests
    /// .test_playerNode_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue`
    /// does for the player -- `accuracy:` because `SKNode.zPosition` is free
    /// to store the assigned `CGFloat` at `Float` (32-bit) precision
    /// internally, unlike the pure-Swift `DepthModel`/`DepthBanding` math it
    /// is compared against.
    func test_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue() {
        let node = PickupNode(kind: .medKit)
        let position = TilePoint(x: -4, y: 20)

        node.updateDepth(atTilePosition: position)

        let expectedAbsolute = DepthBanding.actorZPosition(forActorAt: position, offset: PickupNode.depthOffset)
        let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)

        XCTAssertEqual(node.zPosition, expectedRelative, accuracy: 0.01)
    }

    func test_depthOffset_isWithinTheNonPlayerActorOffsetRange() {
        XCTAssertTrue(DepthBanding.nonPlayerActorOffsetRange.contains(PickupNode.depthOffset))
    }

    // MARK: - Bobbing animation present

    func test_icon_hasABobbingAction() {
        let node = PickupNode(kind: .medKit)
        XCTAssertNotNil(node.icon.action(forKey: PickupNode.bobActionKey))
    }

    // MARK: - Pickup pad glow shape (CYBERPUN-17-18, CYBERPUN-17-25)

    /// The bug: the pad read as a flat, hard-edged cyan square around the
    /// icon rather than a glow. Pinned here against the pure-CoreGraphics
    /// image the production texture is built from (`PickupNode
    /// .medKitGlowCGImageForTesting()`), decoded through the same
    /// known-layout RGBA8 context `ImagePixelSampling` uses, rather than via
    /// `SKTexture.cgImage()`'s GPU-backed readback -- so this assertion
    /// does not depend on a GPU/Metal context being available to the test
    /// process.
    func test_medKitPad_glowTexture_hasSoftRadialFalloff_notAHardSquare() throws {
        let cgImage = try XCTUnwrap(
            PickupNode.medKitGlowCGImageForTesting(),
            "the med kit glow image must be constructible from its fixed, valid CoreGraphics configuration"
        )

        let centerAlpha = try XCTUnwrap(
            alpha(atX: cgImage.width / 2, y: cgImage.height / 2, in: cgImage),
            "center pixel must be sampleable"
        )
        let cornerAlpha = try XCTUnwrap(
            alpha(atX: 0, y: 0, in: cgImage),
            "corner pixel must be sampleable"
        )

        XCTAssertGreaterThan(
            centerAlpha, cornerAlpha,
            "the glow must fade out toward the pad's corners (center alpha \(centerAlpha), corner alpha "
                + "\(cornerAlpha)) -- a flat fill would read the same alpha everywhere"
        )
        XCTAssertLessThan(
            cornerAlpha, 40,
            "the pad's corners must read as (near-)transparent for a soft circular glow, not a filled square "
                + "(measured corner alpha \(cornerAlpha) of 255)"
        )
    }

    /// `CYBERPUN-17-25`: the identical bug for `garbageCan`'s pad -- a
    /// flat, hard-edged magenta square rather than a glow -- pinned the
    /// same way as `test_medKitPad_glowTexture_hasSoftRadialFalloff_notAHardSquare`
    /// above, against `PickupNode.garbageCanGlowCGImageForTesting()`.
    func test_garbageCanPad_glowTexture_hasSoftRadialFalloff_notAHardSquare() throws {
        let cgImage = try XCTUnwrap(
            PickupNode.garbageCanGlowCGImageForTesting(),
            "the garbage can glow image must be constructible from its fixed, valid CoreGraphics configuration"
        )

        let centerAlpha = try XCTUnwrap(
            alpha(atX: cgImage.width / 2, y: cgImage.height / 2, in: cgImage),
            "center pixel must be sampleable"
        )
        let cornerAlpha = try XCTUnwrap(
            alpha(atX: 0, y: 0, in: cgImage),
            "corner pixel must be sampleable"
        )

        XCTAssertGreaterThan(
            centerAlpha, cornerAlpha,
            "the glow must fade out toward the pad's corners (center alpha \(centerAlpha), corner alpha "
                + "\(cornerAlpha)) -- a flat fill would read the same alpha everywhere"
        )
        XCTAssertLessThan(
            cornerAlpha, 40,
            "the pad's corners must read as (near-)transparent for a soft circular glow, not a filled square "
                + "(measured corner alpha \(cornerAlpha) of 255)"
        )
    }

    /// Decodes `cgImage` into a known-layout (premultiplied-last RGBA8)
    /// buffer before sampling, the same approach `ImagePixelSampling
    /// .pixels(ofImageNamed:)` uses for named catalog assets -- so the byte
    /// offset read below does not depend on whatever internal pixel layout
    /// `cgImage` itself happens to carry.
    private func alpha(atX x: Int, y: Int, in cgImage: CGImage) -> UInt8? {
        rgba(atX: x, y: y, in: cgImage)?.a
    }

    /// Same decode as `alpha(atX:y:in:)`, widened to the full RGBA8 tuple
    /// (PR #83 review) so a test can pin a glow's *color*, not just its
    /// alpha falloff shape -- e.g.
    /// `test_medKitAndGarbageCanGlows_useTheirOwnAccentColor` above.
    private func rgba(atX x: Int, y: Int, in cgImage: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let width = cgImage.width
        let height = cgImage.height
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        let byteCount = width * height * 4
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        buffer.initialize(repeating: 0, count: byteCount)
        defer {
            buffer.deinitialize(count: byteCount)
            buffer.deallocate()
        }

        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let offset = (y * width + x) * 4
        return (r: buffer[offset], g: buffer[offset + 1], b: buffer[offset + 2], a: buffer[offset + 3])
    }
}
