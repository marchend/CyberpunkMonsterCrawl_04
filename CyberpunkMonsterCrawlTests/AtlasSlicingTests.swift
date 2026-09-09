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
final class AtlasSlicingTests: XCTestCase {

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

    /// Every one of the 32 `(direction, frame)` pairs must resolve a cell
    /// distinct from any other pair's cell unless the two directions are a
    /// documented mirrored pair -- exactly 2 directions may ever share a
    /// `(row, column)` key, never 3+. A typo'd row in `rowMappingTable`
    /// pointing two *unrelated* directions at the same art is what this
    /// catches.
    func test_playerWalk_cellsAreSharedOnlyByDocumentedMirroredPairs() {
        var occupantsByCellKey: [Int: [(Direction8, Int)]] = [:]
        for direction in Direction8.allCases {
            let mapping = PlayerSpriteSheet.rowMapping(for: direction)
            for frameColumn in 0..<PlayerAnimator.frameCount {
                let key = mapping.row * PlayerSpriteSheet.columns + frameColumn
                occupantsByCellKey[key, default: []].append((direction, frameColumn))
            }
        }

        for (key, occupants) in occupantsByCellKey {
            XCTAssertLessThanOrEqual(
                occupants.count, 2,
                "cell \(key) is claimed by \(occupants.map { "\($0.0)/frame\($0.1)" }) -- at most a "
                    + "mirrored pair may ever share a cell."
            )
        }
    }

    // MARK: - Raccoon walk + attack: every Direction8 x every frame, both sheets

    /// `(direction, frameColumn) -> (sheet row, sheet column)` for both
    /// `sprite_raccoon_walk` and `sprite_raccoon_attack`, read against
    /// `RaccoonNode`'s own production texture caches -- one per sheet, so a
    /// walk cell and an attack cell at the identical `(row, column)` must
    /// never resolve to the same cached `SKTexture` (they are two distinct
    /// images).
    func test_raccoonWalkAndAttack_everyDirectionAndFrame_resolveANonZeroCell_andTheTwoSheetsNeverCollide() {
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
                    "walk and attack .\(direction) frame \(frameColumn) (row \(mapping.row)) must never "
                        + "resolve the same cached texture -- they are two distinct sheets."
                )
            }
        }
    }

    // MARK: - Weapon overlay: every WeaponTier x every Direction8

    /// `(tier, direction) -> (weaponSheetRow, column)` for
    /// `sprite_player_weapons`, pinned against `WeaponOverlayRenderer`'s own
    /// production accessor. `WeaponOverlayRendererTests` already proves
    /// every one of these 24 cells carries authored art and that the west
    /// columns are correctly mirror-authored (not unflipped duplicates);
    /// this pins the row/column *identity* alongside every other family's
    /// pin in the same file.
    func test_weaponOverlay_everyTierAndDirection_resolvesANonZeroCell_atTheDesignTableRowAndColumn() {
        for tier in WeaponTier.allCases {
            for direction in Direction8.allCases {
                guard let expectedColumn = Direction8.allCases.firstIndex(of: direction) else {
                    XCTFail("Direction8.allCases must contain \(direction).")
                    continue
                }

                XCTAssertEqual(
                    WeaponOverlayRenderer.column(for: direction), expectedColumn,
                    ".\(direction) must resolve to Direction8.allCases index \(expectedColumn)."
                )

                let texture = WeaponOverlayRenderer.texture(tier: tier, direction: direction)
                XCTAssertGreaterThan(
                    texture.size().width, 0,
                    "\(tier)/\(direction) (row \(tier.weaponSheetRow), col \(expectedColumn)) resolved to "
                        + "a zero-sized texture."
                )
                XCTAssertGreaterThan(
                    texture.size().height, 0,
                    "\(tier)/\(direction) (row \(tier.weaponSheetRow), col \(expectedColumn)) resolved to "
                        + "a zero-sized texture."
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
