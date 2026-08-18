import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 2: `WeaponOverlayRenderer` -- the weapon overlay
/// composited on the same 36x40 cell and anchor as the player's body
/// sprite, indexed `weapon[tier][dir]`.
final class WeaponOverlayRendererTests: XCTestCase {

    /// A stand-in body sprite carrying the exact size/anchor the real
    /// `PlayerNode.body` uses, so this file never re-derives (or
    /// hand-picks) the cell geometry the overlay is supposed to match.
    private func makeBody(xScale: CGFloat = 1) -> SKSpriteNode {
        let body = SKSpriteNode(texture: nil, color: .clear, size: PlayerSpriteSheet.cellSize)
        body.anchorPoint = PlayerSpriteSheet.anchorPointNormalized
        body.xScale = xScale
        return body
    }

    // MARK: - Same cell rect/anchor as the body, for every direction and tier

    func test_overlaySizeAndAnchor_matchTheBody_forEveryDirection_andEveryTier() {
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let body = makeBody()
                let renderer = WeaponOverlayRenderer(body: body, tier: tier, direction: direction)

                XCTAssertEqual(
                    renderer.overlay.size, body.size,
                    "\(tier)/\(direction): overlay size must equal the body's cell size."
                )
                XCTAssertEqual(
                    renderer.overlay.anchorPoint, body.anchorPoint,
                    "\(tier)/\(direction): overlay anchor must equal the body's anchor."
                )
                XCTAssertTrue(
                    renderer.overlay.parent === body,
                    "\(tier)/\(direction): overlay must be parented directly under the body node."
                )
            }
        }
    }

    // MARK: - Texture indexes [tier][direction] correctly

    func test_initialTexture_isTheTierAndDirectionsCell() {
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let body = makeBody()
                let renderer = WeaponOverlayRenderer(body: body, tier: tier, direction: direction)
                let expected = WeaponOverlayRenderer.texture(tier: tier, direction: direction)

                XCTAssertTrue(
                    renderer.overlay.texture === expected,
                    "\(tier)/\(direction): overlay texture did not match the expected [tier][dir] cell."
                )
            }
        }
    }

    func test_update_swapsTextureToTheNewTiersRow_sameDirection() {
        let body = makeBody()
        let renderer = WeaponOverlayRenderer(body: body, tier: .handgun, direction: .east)

        renderer.update(tier: .assaultRifle, direction: .east)

        let expected = WeaponOverlayRenderer.texture(tier: .assaultRifle, direction: .east)
        XCTAssertTrue(renderer.overlay.texture === expected)
        XCTAssertEqual(renderer.tier, .assaultRifle)
        XCTAssertEqual(renderer.direction, .east)
    }

    func test_update_swapsTextureToTheNewDirectionsColumn_sameTier() {
        let body = makeBody()
        let renderer = WeaponOverlayRenderer(body: body, tier: .smg, direction: .south)

        renderer.update(tier: .smg, direction: .northwest)

        let expected = WeaponOverlayRenderer.texture(tier: .smg, direction: .northwest)
        XCTAssertTrue(renderer.overlay.texture === expected)
    }

    /// Distinct tiers/directions must never collide on the same cached
    /// texture -- otherwise two genuinely different cells would render
    /// identically.
    func test_everyTierDirectionPair_resolvesADistinctTexture() {
        var seen: [ObjectIdentifier: (WeaponTier, Direction8)] = [:]
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let texture = WeaponOverlayRenderer.texture(tier: tier, direction: direction)
                let id = ObjectIdentifier(texture)
                if let existing = seen[id] {
                    XCTFail("\(tier)/\(direction) shares a texture with \(existing.0)/\(existing.1).")
                }
                seen[id] = (tier, direction)
            }
        }
        XCTAssertEqual(seen.count, WeaponTier.allCases.count * Direction8.allCases.count)
    }

    // MARK: - Column ordering is a bijection over Direction8.allCases

    func test_column_isABijection_overAllEightDirections() {
        let columns = Direction8.allCases.map { WeaponOverlayRenderer.column(for: $0) }
        XCTAssertEqual(Set(columns).count, 8, "every direction must map to a distinct column 0..<8")
        XCTAssertEqual(Set(columns), Set(0..<8))
    }

    // MARK: - Mirrored body facings never leave the overlay art backwards

    func test_construction_withAMirroredBody_cancelsTheInheritedFlip() {
        let mirroredBody = makeBody(xScale: -1)
        let renderer = WeaponOverlayRenderer(body: mirroredBody, tier: .handgun, direction: .west)

        XCTAssertEqual(
            renderer.overlay.xScale, PlayerSpriteSheet.xScale(for: .west),
            "overlay xScale must cancel the parent's -1 flip so the unmirrored weapon art renders true."
        )
        XCTAssertEqual(renderer.overlay.xScale, -1)
    }

    func test_overlayXScale_matchesTheOwningTable_forEveryDirection() {
        for direction in Direction8.allCases {
            let body = makeBody(xScale: PlayerSpriteSheet.xScale(for: direction))
            let renderer = WeaponOverlayRenderer(body: body, tier: .smg, direction: direction)

            XCTAssertEqual(
                renderer.overlay.xScale, PlayerSpriteSheet.xScale(for: direction),
                "\(direction): overlay xScale must come from PlayerSpriteSheet.xScale(for:)."
            )
        }
    }

    /// The mirror sign comes from `PlayerSpriteSheet.xScale(for:)` -- the
    /// accessor on the table that owns the `Direction8 -> mirrored` mapping
    /// -- and not from reading the parent's `xScale` sign back off the node.
    ///
    /// This is the discriminating case: `PlayerNode.update(deltaTime:
    /// movementVector:)` is what writes `body.xScale`, so a scene-wiring
    /// caller that drives this renderer *before* the body that frame (or
    /// that changes facing on a `.zero` movement vector, which `PlayerNode`
    /// keeps facing across) hands the renderer a mirrored `direction` while
    /// the parent still carries the previous frame's sign. Sourcing the sign
    /// from the parent shows one frame of overlay flipped against the
    /// texture it is displaying; sourcing it from the table cannot.
    func test_mirrorSign_comesFromTheTable_notTheParentsStaleXScale() {
        // Body still unmirrored (stale: it has not been updated this frame),
        // renderer handed a mirrored facing.
        let staleUnmirroredBody = makeBody(xScale: 1)
        let renderer = WeaponOverlayRenderer(body: staleUnmirroredBody, tier: .handgun, direction: .east)
        renderer.update(tier: .handgun, direction: .west)

        XCTAssertEqual(
            renderer.overlay.xScale, -1,
            "a mirrored facing must cancel the flip the body is about to inherit, even when the "
                + "parent's own xScale has not been written yet this frame."
        )

        // The inverse: body still mirrored from last frame, renderer handed
        // an unmirrored facing.
        let staleMirroredBody = makeBody(xScale: -1)
        let inverse = WeaponOverlayRenderer(body: staleMirroredBody, tier: .handgun, direction: .west)
        inverse.update(tier: .handgun, direction: .east)

        XCTAssertEqual(
            inverse.overlay.xScale, 1,
            "an unmirrored facing must not carry the previous frame's flip cancellation."
        )
    }

    // MARK: - The "all 8 columns are authored art" claim, measured off the shipped pixels

    /// `WeaponOverlayRenderer`'s doc comment states two things about the
    /// shipped `sprite_player_weapons` PNG that no other assertion in this
    /// file checks against the PNG: that every one of its 24 cells carries
    /// authored art, and that the west columns are not mirrored copies of
    /// the east ones. `AtlasSheet.playerWeapons` pins only the grid, and
    /// `test_everyTierDirectionPair_resolvesADistinctTexture` above compares
    /// `ObjectIdentifier`s of distinct `SKTexture` crops -- which differ
    /// whether or not the pixels underneath are empty or duplicated. So this
    /// is the discriminating measurement, in the shape
    /// `PlayerSpriteSheetTests`
    /// `.test_theRowsTheTableNeverReads_carryNoArtBeyondTheMirrorOfTheirSourceRow`
    /// already established for the walk sheet.
    ///
    /// Two failure modes matter, and both are silent at render time:
    ///
    /// - **An empty cell.** That facing/tier draws an invisible gun.
    /// - **A west column that is *pixel-identical* to its east counterpart.**
    ///   The column would then hold an east-pointing gun, and since
    ///   `overlay.xScale` cancels the body's inherited mirror (net `+1`),
    ///   that art draws unflipped on a west-facing body: a backwards gun on
    ///   3 of 8 facings.
    ///
    /// A west column that is the horizontal *flip* of its east counterpart
    /// is a different matter and is measured separately, in
    /// `test_theWestColumns_areHorizontalFlipsOfTheirEastCounterparts` --
    /// that is what the shipped sheet actually is, and it is what makes the
    /// flip-cancellation correct rather than what breaks it.
    ///
    /// **If this fails, do not loosen it.** An empty cell means the sheet
    /// needs re-exporting; an unflipped duplicate means the renderer must
    /// stop cancelling the body's flip for that facing (the walk sheet's own
    /// `mirrored: true` shape). The failure message reports the measured
    /// numbers so the reader can tell which case holds.
    func test_everyWeaponCell_carriesAuthoredArt_andNoWestColumnIsAnUnflippedCopyOfItsEast() throws {
        let sheet = AtlasSheet.playerWeapons.sheet
        let cellSize = try XCTUnwrap(
            sheet.cellSize,
            "AtlasSheet.playerWeapons must declare a uniform cellSize for this scan to crop cells."
        )
        let pixels = try weaponPixels()

        XCTAssertEqual(
            CGSize(width: CGFloat(pixels.width), height: CGFloat(pixels.height)),
            sheet.pixelSize,
            "the decoded sheet must match the declared atlas geometry, or every cell crop below "
                + "addresses the wrong pixels."
        )

        // 1. No empty cells: an unauthored column draws an invisible weapon.
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                let column = WeaponOverlayRenderer.column(for: direction)
                let cellPixels = cell(column: column, row: tier.weaponSheetRow, of: pixels, cellSize: cellSize)
                let opaque = opaquePixelCount(of: cellPixels)

                XCTAssertGreaterThan(
                    opaque, 0,
                    "\(tier)/\(direction) (column \(column), row \(tier.weaponSheetRow)) measures 0 opaque "
                        + "pixels: that cell is unauthored, so the overlay draws an invisible weapon for "
                        + "this facing while the suite stays green."
                )
            }
        }

        // 2. The west half is its own art, not a copy of the east half.
        //    Pairing is by vertical component, the same way
        //    `PlayerSpriteSheet.rowMappingTable` pairs its mirrored rows.
        let westEastPairs: [(west: Direction8, east: Direction8)] = [
            (.northwest, .northeast),
            (.west, .east),
            (.southwest, .southeast),
        ]

        for tier in WeaponTier.allCases {
            for pair in westEastPairs {
                let westColumn = WeaponOverlayRenderer.column(for: pair.west)
                let eastColumn = WeaponOverlayRenderer.column(for: pair.east)
                let west = cell(column: westColumn, row: tier.weaponSheetRow, of: pixels, cellSize: cellSize)
                let east = cell(column: eastColumn, row: tier.weaponSheetRow, of: pixels, cellSize: cellSize)

                XCTAssertNotEqual(
                    west.fingerprint, east.fingerprint,
                    "\(tier): column \(westColumn) (.\(pair.west)) is pixel-identical to column "
                        + "\(eastColumn) (.\(pair.east)). WeaponOverlayRenderer draws the overlay at a "
                        + "net xScale of +1 for every facing, so an east-posed copy in a west column "
                        + "renders a backwards gun on a west-facing body. Point .\(pair.west) at column "
                        + "\(eastColumn) with the flip left inherited, instead of relaxing this assertion."
                )
                XCTAssertNotEqual(
                    opaqueSilhouette(of: west), opaqueSilhouette(of: east),
                    "\(tier): column \(westColumn) (.\(pair.west)) has the same silhouette as column "
                        + "\(eastColumn) (.\(pair.east)) unflipped, which is the backwards-gun case above."
                )
            }
        }
    }

    /// The measured relationship between the sheet's west and east halves,
    /// pinned because `WeaponOverlayRenderer`'s doc comment cites it.
    ///
    /// **This is the finding the pixel scan turned up.** PR 2 originally
    /// asserted by convention that `sprite_player_weapons` authors "real,
    /// unmirrored art" for all 8 columns and that there was "nothing to
    /// measure". Measured, the sheet is mirror-authored the same way
    /// `sprite_player_walk` is: for every tier row, the northwest/west/
    /// southwest columns (5/6/7) are the horizontal flips of the
    /// northeast/east/southeast columns (3/2/1) they pair with by vertical
    /// component.
    ///
    /// That does **not** break the renderer -- it is what makes it right.
    /// Each west column already holds art posed for its own facing (a
    /// west-pointing gun), so the overlay must draw it *unflipped*, which is
    /// exactly the net `+1` `overlay.xScale`'s cancellation of the body's
    /// inherited `-1` produces. What was wrong was the stated reason, not the
    /// behaviour.
    ///
    /// **If this fails, the doc comment is now stale.** A re-export that
    /// authors genuinely distinct west-side art (e.g. the gun moved to the
    /// other hand) still renders correctly at net `+1`, but
    /// `WeaponOverlayRenderer`'s "Every column carries its own art"
    /// paragraph cites this measurement, so re-word that paragraph -- and
    /// re-check the gun-hand against the body's own mirrored pose -- rather
    /// than deleting this test.
    func test_theWestColumns_areHorizontalFlipsOfTheirEastCounterparts() throws {
        let sheet = AtlasSheet.playerWeapons.sheet
        let cellSize = try XCTUnwrap(sheet.cellSize)
        let pixels = try weaponPixels()

        let westEastPairs: [(west: Direction8, east: Direction8)] = [
            (.northwest, .northeast),
            (.west, .east),
            (.southwest, .southeast),
        ]

        for tier in WeaponTier.allCases {
            for pair in westEastPairs {
                let westColumn = WeaponOverlayRenderer.column(for: pair.west)
                let eastColumn = WeaponOverlayRenderer.column(for: pair.east)
                let west = cell(column: westColumn, row: tier.weaponSheetRow, of: pixels, cellSize: cellSize)
                let east = cell(column: eastColumn, row: tier.weaponSheetRow, of: pixels, cellSize: cellSize)

                XCTAssertEqual(
                    opaqueSilhouette(of: west), mirroredOpaqueSilhouette(of: east),
                    "\(tier): column \(westColumn) (.\(pair.west)) is no longer the horizontal flip of "
                        + "column \(eastColumn) (.\(pair.east)). The art may well be fine -- rendering "
                        + "stays correct as long as the column is posed for its own facing -- but "
                        + "WeaponOverlayRenderer's doc comment cites this measurement and now needs "
                        + "re-wording."
                )
            }
        }
    }

    // MARK: - Pixel measurement helpers

    private func weaponPixels() throws -> ImagePixelSampling.Pixels {
        let imageID = AtlasSheet.playerWeapons.imageID
        return try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: imageID),
            "\(imageID) could not be decoded from Assets.xcassets - the art measurement would "
                + "otherwise pass vacuously on an empty image."
        )
    }

    /// One cell of the decoded sheet, lifted into its own `Pixels` so
    /// `ImagePixelSampling`'s fingerprint/mirror helpers apply to it
    /// directly -- the same per-cell crop `PlayerSpriteSheetTests` uses, and
    /// per *cell* for the same reason: the mirror this renderer cancels is a
    /// negative x-scale on one drawn cell, not on a whole row.
    private func cell(
        column: Int,
        row: Int,
        of pixels: ImagePixelSampling.Pixels,
        cellSize: CGSize
    ) -> ImagePixelSampling.Pixels {
        let cellWidth = Int(cellSize.width)
        let cellHeight = Int(cellSize.height)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cellWidth * cellHeight * 4)
        for y in (row * cellHeight)..<((row + 1) * cellHeight) {
            for x in (column * cellWidth)..<((column + 1) * cellWidth) {
                let base = (y * pixels.width + x) * 4
                bytes.append(contentsOf: pixels.rgba[base..<(base + 4)])
            }
        }
        return ImagePixelSampling.Pixels(width: cellWidth, height: cellHeight, rgba: bytes)
    }

    private func opaquePixelCount(of cell: ImagePixelSampling.Pixels) -> Int {
        cell.width * cell.height - cell.fullyTransparentPixelCount
    }

    /// The cell's opaque/transparent mask, row-major. Silhouette rather than
    /// full RGBA decides the mirror question: a re-export can shift a byte
    /// of colour without changing which pixels are drawn, while an authored
    /// west-side pose changes the outline.
    private func opaqueSilhouette(of cell: ImagePixelSampling.Pixels) -> [Bool] {
        var mask: [Bool] = []
        mask.reserveCapacity(cell.width * cell.height)
        for y in 0..<cell.height {
            for x in 0..<cell.width {
                mask.append(cell.isOpaque(x: x, y: y))
            }
        }
        return mask
    }

    private func mirroredOpaqueSilhouette(of cell: ImagePixelSampling.Pixels) -> [Bool] {
        var mask: [Bool] = []
        mask.reserveCapacity(cell.width * cell.height)
        for y in 0..<cell.height {
            for x in 0..<cell.width {
                mask.append(cell.isOpaque(x: cell.width - 1 - x, y: y))
            }
        }
        return mask
    }
}
