import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-14-t2` (PR 2): the single, consolidated pin of every named
/// animation state's atlas index -- across every actor family the pack
/// defines -- plus every placeable building id, in one file a reviewer can
/// read top-to-bottom instead of cross-referencing `PlayerSpriteSheetTests`
/// / `RaccoonAnimationControllerTests` / `WeaponOverlayRendererTests` /
/// `BuildingCatalogTests` separately.
///
/// **What this PR's audit found.** Re-reading every atlas contract file,
/// its owning row/column table, and its existing pixel-measurement tests
/// turned up no mis-indexed cell to fix: `PlayerSpriteSheet.rowMappingTable`,
/// `RaccoonAnimationController.rowMappingTable`,
/// `WeaponOverlayRenderer.column(for:)`, and `BuildingSprite`/
/// `BuildingCatalog`'s asset-name tables already carry the
/// measured-against-shipped-art proofs the earlier stories built (see each
/// type's own doc comment, and `PlayerSpriteSheetTests`
/// `.test_theRowsTheTableNeverReads_carryNoArtBeyondTheMirrorOfTheirSourceRow`
/// / `WeaponOverlayRendererTests`
/// `.test_everyWeaponCell_carriesAuthoredArt_andNoWestColumnIsAnUnflippedCopyOfItsEast`
/// / `RaccoonSpriteSheetPixelTests`'s equivalent, all of which re-decode the
/// shipped PNGs rather than trusting the tables). What this file adds is not
/// a fix but a single place the *whole* named-state -> (sheet, row, column)
/// map is exercised at once against each family's own production texture
/// accessor (`PlayerNode.texture(row:column:)`,
/// `RaccoonNode.texture(state:row:column:)`,
/// `WeaponOverlayRenderer.texture(tier:direction:)`,
/// `BuildingSprite.texture`), so a future change to any one family's table
/// is caught here too, not only in that family's own test file.
///
/// **Every expectation in this file is a literal, never a re-derivation of
/// the code under test** (PR #65 review). An assertion that recomputes its
/// expected row/column the way the production accessor computes it cannot
/// fail whatever happens to the enum or the sheet, which would make this
/// file's "consolidated pin" claim empty. So the direction -> row, direction
/// -> column and tier -> row tables below are typed out by hand from each
/// type's own doc comment, and the one claim that no index comparison can
/// settle -- that the raccoon's walk and attack sheets are two different
/// images -- is measured off the decoded PNGs.
final class AtlasSlicingTests: XCTestCase {

    // MARK: - The documented row/mirror convention, typed out as literals

    /// The `Direction8 -> (row, mirrored)` shape *both* actor families
    /// document: 5 directly-authored rows sweeping due-south (row 0) to
    /// due-north (row 4) up the sheet's east side, and 3 west facings
    /// produced by horizontally mirroring the row that shares their
    /// vertical component -- `.southwest` from row 1 (`.southeast`),
    /// `.west` from row 2 (`.east`), `.northwest` from row 3
    /// (`.northeast`). See `PlayerSpriteSheet.rowMappingTable` /
    /// `RaccoonAnimationController.rowMappingTable`.
    ///
    /// Literal on purpose: deriving the expectation from the table under
    /// test (`.southwest.row == .southeast.row`), or asserting only that no
    /// cell has 3+ occupants, leaves the regression this file advertises
    /// undetectable. Pointing `.north` at row 0 would keep every direction
    /// resolving a non-zero cached cell and keep every shared cell down to
    /// two occupants, while drawing the south pose for a north-facing
    /// actor.
    private static let expectedRowMappings: [(direction: Direction8, row: Int, mirrored: Bool)] = [
        (.south, 0, false),
        (.southeast, 1, false),
        (.east, 2, false),
        (.northeast, 3, false),
        (.north, 4, false),
        (.southwest, 1, true),
        (.west, 2, true),
        (.northwest, 3, true),
    ]

    /// The only three row-sharing sets the convention allows -- a mirrored
    /// pair each.
    private static let expectedMirroredPairs: Set<Set<Direction8>> = [
        [.southeast, .southwest],
        [.east, .west],
        [.northeast, .northwest],
    ]

    /// The two facings whose row is theirs alone: due-south and due-north
    /// have no lateral component to mirror.
    private static let expectedUnsharedDirections: Set<Direction8> = [.south, .north]

    /// Asserts one family's row/mirror table against the convention above:
    /// every facing's literal row *and* mirror flag, the exact set of
    /// facings sharing each row, and that `.south`/`.north` share their row
    /// with nothing.
    ///
    /// Takes the mapping as a closure so the identical check serves both
    /// `PlayerSpriteSheet.RowMapping` and
    /// `RaccoonAnimationController.RowMapping` -- two distinct types of the
    /// same shape -- rather than being typed out twice.
    private func assertRowMappingsFollowTheDocumentedConvention(
        family: String,
        mapping: (Direction8) -> (row: Int, mirrored: Bool),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Set(Self.expectedRowMappings.map { $0.direction }), Set(Direction8.allCases),
            "\(family): the literal table in this file must cover every Direction8 case -- a newly "
                + "added facing must be pinned here, not silently unchecked.",
            file: file, line: line
        )

        for expected in Self.expectedRowMappings {
            let actual = mapping(expected.direction)
            XCTAssertEqual(
                actual.row, expected.row,
                "\(family): .\(expected.direction) reads sheet row \(actual.row), but the documented "
                    + "table puts it on row \(expected.row) -- this facing would draw another "
                    + "facing's pose.",
                file: file, line: line
            )
            XCTAssertEqual(
                actual.mirrored, expected.mirrored,
                "\(family): .\(expected.direction) has mirrored == \(actual.mirrored), but the "
                    + "documented table says \(expected.mirrored) -- an unmirrored west facing draws "
                    + "an east-posed actor walking backwards.",
                file: file, line: line
            )
        }

        var directionsByRow: [Int: Set<Direction8>] = [:]
        for direction in Direction8.allCases {
            directionsByRow[mapping(direction).row, default: []].insert(direction)
        }

        let sharedSets = Set(directionsByRow.values.filter { $0.count > 1 })
        let sharedDescription = sharedSets
            .map { $0.map { "\($0)" }.sorted().joined(separator: "+") }
            .sorted()
        XCTAssertEqual(
            sharedSets, Self.expectedMirroredPairs,
            "\(family): the facings sharing a sheet row measure as \(sharedDescription), but the "
                + "documented convention allows exactly {southeast, southwest}, {east, west} and "
                + "{northeast, northwest} -- any other pairing mirrors the wrong vertical pose.",
            file: file, line: line
        )

        for direction in Self.expectedUnsharedDirections {
            let occupants = directionsByRow[mapping(direction).row] ?? []
            XCTAssertEqual(
                occupants, [direction],
                "\(family): row \(mapping(direction).row) is .\(direction)'s alone, but it is shared "
                    + "with \(occupants.subtracting([direction]).map { "\($0)" }.sorted()).",
                file: file, line: line
            )
        }

        for pair in Self.expectedMirroredPairs {
            let mirroredCount = pair.filter { mapping($0).mirrored }.count
            XCTAssertEqual(
                mirroredCount, 1,
                "\(family): exactly one of \(pair.map { "\($0)" }.sorted()) may be the mirrored half "
                    + "of the pair, but \(mirroredCount) are marked mirrored.",
                file: file, line: line
            )
        }
    }

    // MARK: - Player walk: every Direction8 x every walk-cycle frame

    /// `(direction, frameColumn) -> (sheet row, sheet column)` for
    /// `sprite_player_walk`, read against `PlayerNode`'s own production
    /// texture cache rather than a second crop of the sheet -- so this pins
    /// what the game actually draws, not a parallel computation that could
    /// drift from it.
    func test_playerWalk_everyDirectionAndFrame_resolvesANonZeroCachedCell() {
        for direction in Direction8.allCases {
            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            for frameColumn in 0..<PlayerAnimator.frameCount {
                let texture = PlayerNode.texture(row: mapping.row, column: frameColumn)
                let sameCellAgain = PlayerNode.texture(row: mapping.row, column: frameColumn)

                XCTAssertTrue(
                    texture === sameCellAgain,
                    ".\(direction) frame \(frameColumn) (row \(mapping.row)) must resolve the exact same "
                        + "cached texture on every call."
                )
                XCTAssertGreaterThan(
                    texture.size().width, 0,
                    ".\(direction) frame \(frameColumn) (row \(mapping.row), col \(frameColumn)) resolved "
                        + "to a zero-sized texture."
                )
                XCTAssertGreaterThan(
                    texture.size().height, 0,
                    ".\(direction) frame \(frameColumn) (row \(mapping.row), col \(frameColumn)) resolved "
                        + "to a zero-sized texture."
                )
            }
        }
    }

    /// Every facing's literal sheet row and mirror flag, plus the exact
    /// pairing that may share a row.
    ///
    /// This replaces an earlier "at most 2 directions may share a cell"
    /// scan that PR #65's review showed could not fail on the regression it
    /// advertised: pointing `.north` at row 0 leaves row 0 with two
    /// occupants (`.south`, `.north`) and row 4 with none, which that scan
    /// accepted while a north-facing player drew the south pose. The
    /// pairing is now asserted against the convention
    /// `PlayerSpriteSheet.rowMappingTable`'s doc comment states, so that
    /// edit fails here.
    func test_playerWalk_rowMappings_matchTheDocumentedMirroredPairConvention() {
        assertRowMappingsFollowTheDocumentedConvention(family: "PlayerSpriteSheet") { direction in
            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            return (row: mapping.row, mirrored: mapping.mirrored)
        }
    }

    // MARK: - Raccoon walk + attack: every Direction8 x every frame, both sheets

    /// The raccoon's own row/mirror table, pinned against the same
    /// documented convention as the player's -- both families' doc comments
    /// state the identical shape, so one helper serves both.
    func test_raccoonWalkAndAttack_rowMappings_matchTheDocumentedMirroredPairConvention() {
        assertRowMappingsFollowTheDocumentedConvention(family: "RaccoonAnimationController") { direction in
            let mapping = RaccoonAnimationController.rowMapping(for: direction)
            return (row: mapping.row, mirrored: mapping.mirrored)
        }
    }

    /// `(direction, frameColumn) -> (sheet row, sheet column)` for both
    /// `sprite_raccoon_walk` and `sprite_raccoon_attack`, read against
    /// `RaccoonNode`'s own production texture caches -- one per sheet.
    ///
    /// **What the `===` assertion below pins, and what it does not** (PR
    /// #65 review). It pins *cache isolation*: `RaccoonNode` keeps one
    /// `[Int: SKTexture]` per sheet, so collapsing them into a single cache
    /// keyed only on `(row, column)` -- which would hand back whichever
    /// sheet's crop was requested first -- fails here. It does **not**
    /// prove the two cells carry different art: comparing
    /// `ObjectIdentifier`s of two distinct `SKTexture` crops differs
    /// whether or not the pixels underneath are identical or empty, the
    /// exact pitfall `WeaponOverlayRenderer`'s doc comment already records
    /// for `test_everyTierDirectionPair_resolvesADistinctTexture`. The
    /// "two distinct sheets" half is measured off the decoded PNGs by
    /// `test_theTwoRaccoonSheets_shipDistinctArt_onEveryAuthoredRow` below.
    func test_raccoonWalkAndAttack_everyDirectionAndFrame_resolveANonZeroCell_andEachSheetKeepsItsOwnCache() {
        for direction in Direction8.allCases {
            let mapping = RaccoonAnimationController.rowMapping(for: direction)
            for frameColumn in 0..<RaccoonAnimationController.frameCount {
                let walkTexture = RaccoonNode.texture(state: .walk, row: mapping.row, column: frameColumn)
                let attackTexture = RaccoonNode.texture(state: .attack, row: mapping.row, column: frameColumn)

                XCTAssertGreaterThan(
                    walkTexture.size().width, 0,
                    "walk .\(direction) frame \(frameColumn) (row \(mapping.row)) resolved to a "
                        + "zero-sized texture."
                )
                XCTAssertGreaterThan(
                    attackTexture.size().width, 0,
                    "attack .\(direction) frame \(frameColumn) (row \(mapping.row)) resolved to a "
                        + "zero-sized texture."
                )
                XCTAssertFalse(
                    walkTexture === attackTexture,
                    "walk and attack .\(direction) frame \(frameColumn) (row \(mapping.row)) resolved "
                        + "the same cached texture -- RaccoonNode's two per-sheet caches have been "
                        + "collapsed into one keyed only on (row, column)."
                )
            }
        }
    }

    /// The discriminating half of the claim above: the walk and attack
    /// sheets must actually be two different images. Measured off the
    /// decoded PNGs -- the way `RaccoonSpriteSheetPixelTests` measures both
    /// sheets -- because no `SKTexture` identity comparison can see it: a
    /// `RaccoonNode.texture(state:row:column:)` that sliced
    /// `cachedWalkSheet` for `.attack` while keeping two caches would still
    /// produce two distinct crop objects, and an attack cell drawing walk
    /// art would pass the `===` check silently.
    ///
    /// Asserted per authored row rather than per cell on purpose: reusing a
    /// single frame between the two cycles is a legitimate authoring
    /// choice, whereas a whole facing whose four frames are byte-identical
    /// across the two sheets is the duplicate-export failure -- one sheet
    /// re-exported under both names, which would make every attack look
    /// like a walk.
    func test_theTwoRaccoonSheets_shipDistinctArt_onEveryAuthoredRow() throws {
        let walkPixels = try decodedPixels(of: .raccoonWalk)
        let attackPixels = try decodedPixels(of: .raccoonAttack)

        let authoredRows = Set(Direction8.allCases.map { RaccoonAnimationController.rowMapping(for: $0).row })
        XCTAssertEqual(
            authoredRows, Set(0...4),
            "this measurement assumes the table authors rows 0-4; it measured "
                + "\(authoredRows.sorted()) instead, so the row scan below is stale."
        )

        for row in authoredRows.sorted() {
            var framesThatDiffer = 0
            for frameColumn in 0..<RaccoonAnimationController.frameCount {
                let walkCell = raccoonCell(column: frameColumn, row: row, of: walkPixels)
                let attackCell = raccoonCell(column: frameColumn, row: row, of: attackPixels)
                if walkCell.fingerprint != attackCell.fingerprint {
                    framesThatDiffer += 1
                }
            }

            XCTAssertGreaterThan(
                framesThatDiffer, 0,
                "row \(row) is byte-identical across sprite_raccoon_walk and sprite_raccoon_attack in "
                    + "all \(RaccoonAnimationController.frameCount) frames -- the two imagesets are the "
                    + "same art, so every attack for this facing draws the walk pose. Re-export the "
                    + "attack sheet rather than relaxing this measurement."
            )
        }
    }

    // MARK: - Raccoon pixel-measurement helpers

    private func decodedPixels(of atlasSheet: AtlasSheet) throws -> ImagePixelSampling.Pixels {
        try XCTUnwrap(
            ImagePixelSampling.pixels(ofImageNamed: atlasSheet.imageID),
            "\(atlasSheet.imageID) could not be decoded from Assets.xcassets -- the measurement above "
                + "would otherwise pass vacuously on an empty image."
        )
    }

    /// One `(column, row)` cell of a decoded raccoon sheet, lifted into its
    /// own `Pixels` so `ImagePixelSampling`'s fingerprint helper applies to
    /// it directly -- the same per-cell crop
    /// `RaccoonSpriteSheetPixelTests` uses, and per cell rather than per
    /// whole row for the same reason: a row-wide comparison would fold four
    /// frames together and hide a single swapped cell.
    private func raccoonCell(
        column: Int,
        row: Int,
        of pixels: ImagePixelSampling.Pixels
    ) -> ImagePixelSampling.Pixels {
        let cellWidth = Int(RaccoonAnimationController.cellSize.width)
        let cellHeight = Int(RaccoonAnimationController.cellSize.height)

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

    // MARK: - Weapon overlay: every WeaponTier x every Direction8

    /// `sprite_player_weapons`' documented column ordering, typed out as
    /// literals from `WeaponOverlayRenderer`'s "Column ordering" paragraph
    /// (south, southeast, east, northeast, north, northwest, west,
    /// southwest).
    ///
    /// Literal for the same reason `test_weaponOverlay_tierRows_matchTheDesignTable`
    /// pins `0/1/2` literally: `WeaponOverlayRenderer.column(for:)` *is*
    /// `Direction8.allCases.firstIndex(of:)`, so asserting it against a
    /// second `firstIndex(of:)` call compares the implementation with
    /// itself and can never fail -- which is what this test did before PR
    /// #65's review. With the columns written out, an accidentally
    /// reordered `Direction8` case (which silently moves every column of
    /// this sheet) fails here.
    private static let expectedWeaponColumns: [(direction: Direction8, column: Int)] = [
        (.south, 0),
        (.southeast, 1),
        (.east, 2),
        (.northeast, 3),
        (.north, 4),
        (.northwest, 5),
        (.west, 6),
        (.southwest, 7),
    ]

    /// `(tier, direction) -> (weaponSheetRow, column)` for
    /// `sprite_player_weapons`, pinned against `WeaponOverlayRenderer`'s own
    /// production accessor. `WeaponOverlayRendererTests` already proves
    /// every one of these 24 cells carries authored art and that the west
    /// columns are correctly mirror-authored (not unflipped duplicates);
    /// this pins the row/column *identity* alongside every other family's
    /// pin in the same file.
    func test_weaponOverlay_everyTierAndDirection_resolvesANonZeroCell_atTheDesignTableRowAndColumn() {
        XCTAssertEqual(
            Set(Self.expectedWeaponColumns.map { $0.direction }), Set(Direction8.allCases),
            "the literal column table must cover every Direction8 case -- a newly added facing must be "
                + "pinned to a column here, not left unchecked."
        )

        for tier in WeaponTier.allCases {
            for expected in Self.expectedWeaponColumns {
                XCTAssertEqual(
                    WeaponOverlayRenderer.column(for: expected.direction), expected.column,
                    ".\(expected.direction) resolves column "
                        + "\(WeaponOverlayRenderer.column(for: expected.direction)) of "
                        + "sprite_player_weapons, but the sheet's documented column ordering puts it at "
                        + "\(expected.column) -- every facing past a reordered case would draw another "
                        + "facing's gun."
                )

                let texture = WeaponOverlayRenderer.texture(tier: tier, direction: expected.direction)
                XCTAssertGreaterThan(
                    texture.size().width, 0,
                    "\(tier)/\(expected.direction) (row \(tier.weaponSheetRow), col \(expected.column)) "
                        + "resolved to a zero-sized texture."
                )
                XCTAssertGreaterThan(
                    texture.size().height, 0,
                    "\(tier)/\(expected.direction) (row \(tier.weaponSheetRow), col \(expected.column)) "
                        + "resolved to a zero-sized texture."
                )
            }
        }
    }

    /// The tier -> row mapping the sheet's own comment documents
    /// ("rows 0/1/2 = handgun/SMG/AR"), pinned literally so a reordering of
    /// `WeaponTier`'s cases (which would silently reorder `allCases`
    /// iteration elsewhere) cannot quietly relabel which row is which tier.
    func test_weaponOverlay_tierRows_matchTheDesignTable() {
        XCTAssertEqual(WeaponTier.handgun.weaponSheetRow, 0)
        XCTAssertEqual(WeaponTier.smg.weaponSheetRow, 1)
        XCTAssertEqual(WeaponTier.assaultRifle.weaponSheetRow, 2)
    }

    // MARK: - Buildings: every one of the 12 placeable ids

    /// Every building id `0...11` must resolve to its own `building_NN`
    /// imageset, load a non-zero-sized texture, and agree with the World
    /// layer's independently-typed-out `BuildingCatalog` restatement. The
    /// "12 distinct pieces of art, none a duplicate or mirror of another"
    /// gate and the "carries an alpha channel with real transparent pixels
    /// outside its silhouette" gate already live, measured off decoded
    /// pixels, in `BuildingCatalogTests` -- this pins the *identity* side
    /// (one id, one name, one resolvable texture) alongside every other
    /// family's animation-state pin in the same file, rather than
    /// re-running the pixel scan a second time.
    func test_everyBuildingID_resolvesItsOwnImagesetName_andANonZeroTexture() {
        for index in 0...11 {
            guard let building = BuildingSprite(rawValue: index) else {
                XCTFail("BuildingSprite has no case for index \(index).")
                continue
            }

            let expectedName = String(format: "building_%02d", index)
            XCTAssertEqual(building.imageID, expectedName)

            let texture = building.texture
            XCTAssertGreaterThan(texture.size().width, 0, "\(expectedName) resolved to a zero-width texture.")
            XCTAssertGreaterThan(texture.size().height, 0, "\(expectedName) resolved to a zero-height texture.")

            let entry = BuildingCatalog.entry(atIndex: index)
            XCTAssertEqual(
                entry.assetName, expectedName,
                "BuildingCatalog entry \(index) names \(entry.assetName), not \(expectedName)."
            )
        }
    }

    /// Anti-vacuity: the loop above must actually walk all 12 ids, not
    /// silently iterate zero.
    func test_buildingSprite_declaresExactlyTwelveIDs_zeroThroughEleven() {
        XCTAssertEqual(BuildingSprite.allCases.count, 12)
        XCTAssertEqual(Set(BuildingSprite.allCases.map(\.rawValue)), Set(0...11))
    }
}
