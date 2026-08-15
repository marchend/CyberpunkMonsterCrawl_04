import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6-t2: `DepthBanding` extends `DepthModel`'s painter's-algorithm
/// scheme with an actor-offset input and the player-max tie-break, and
/// `PlayerNode.updateDepth(atTilePosition:)` is the production consumer that
/// wires a live node into it.
final class PlayerDepthTests: XCTestCase {

    // MARK: - The player's offset is DepthModel's actorOffsetRange ceiling

    func test_playerActorOffset_isTheTopOfDepthModelsActorOffsetRange() {
        XCTAssertEqual(DepthBanding.playerActorOffset, DepthModel.actorOffsetRange.upperBound, accuracy: 1e-9)
    }

    func test_nonPlayerActorOffsetRange_excludesThePlayersOffset_butStartsAtTheSameFloor() {
        XCTAssertEqual(DepthBanding.nonPlayerActorOffsetRange.lowerBound, DepthModel.actorOffsetRange.lowerBound)
        XCTAssertEqual(DepthBanding.nonPlayerActorOffsetRange.upperBound, DepthBanding.playerActorOffset)
        XCTAssertFalse(DepthBanding.nonPlayerActorOffsetRange.contains(DepthBanding.playerActorOffset))
    }

    // MARK: - Player's z within its band is the max of any co-banded actor

    func test_playerZPosition_exceedsAnyNonPlayerActorOffset_inTheSameBand() {
        let position = TilePoint(x: 4, y: 6)
        let playerZ = DepthBanding.playerZPosition(at: position)

        let sampleOffsets: [CGFloat] = [
            DepthBanding.nonPlayerActorOffsetRange.lowerBound,
            8.0,
            9.0,
            9.899,
        ]

        for offset in sampleOffsets {
            XCTAssertTrue(DepthBanding.nonPlayerActorOffsetRange.contains(offset), "\(offset) must be a legal non-player offset for this test to be meaningful.")
            let otherActorZ = DepthBanding.actorZPosition(forActorAt: position, offset: offset)
            XCTAssertLessThan(
                otherActorZ,
                playerZ,
                "A co-banded actor at offset \(offset) must never reach the player's zPosition."
            )
        }
    }

    func test_playerZPosition_equalsBandPlusPlayerActorOffset() {
        let position = TilePoint(x: -3, y: 9)
        let expectedBand = DepthModel.band(forActorAt: position)

        XCTAssertEqual(
            DepthBanding.playerZPosition(at: position),
            expectedBand + DepthBanding.playerActorOffset,
            accuracy: 1e-9
        )
    }

    // MARK: - Actor depth samples the ROUNDED tile coordinate, not a continuous position

    func test_playerZPosition_forFractionalPositions_matchesTheRoundedWholeTilesZPosition() {
        let wholeTile = TileCoordinate(tileX: 4, tileY: 6)
        let expectedZ = DepthBanding.playerZPosition(at: TilePoint(x: 4, y: 6))

        let fractionalPositions = [
            TilePoint(x: 4.2, y: 6.2),
            TilePoint(x: 3.6, y: 5.6),
            TilePoint(x: 4.49, y: 6.49),
        ]

        for position in fractionalPositions {
            XCTAssertEqual(
                DepthBanding.playerZPosition(at: position),
                expectedZ,
                accuracy: 1e-9,
                "\(position) should round to tile \(wholeTile) and share its zPosition."
            )
        }
    }

    // MARK: - A tall building sharing the band never draws above the player

    /// Building content (`DepthModel.buildingContentRange`, `0..<3`) and
    /// actor content (`DepthModel.actorOffsetRange`, `6.5...9.9`) are
    /// disjoint ranges within the same band, regardless of the building's
    /// height class -- a taller building (e.g. `BuildingCatalog.HeightClass
    /// .tall`/`.large`) still only ever occupies an in-band offset inside
    /// `buildingContentRange`; its height is expressed by the *sprite's own
    /// pixel height*, drawn upward from its base tile, never by a larger
    /// in-band offset. So this holds for every height class without this
    /// test needing to render an actual building sprite.
    func test_playerZPosition_alwaysExceeds_anyBuildingContentZPosition_inTheSameBand() {
        let position = TilePoint(x: 10, y: -2)
        let playerZ = DepthBanding.playerZPosition(at: position)
        let band = DepthModel.band(forActorAt: position)

        // Every height class (`.lowest`/`.low`/`.mid`/`.tall`/`.large`)
        // shares the same catalog-wide in-band content range; sample its
        // ceiling explicitly, since that is the closest a building of any
        // height can get to the player's offset -- a building's height is
        // expressed by its sprite's own pixel height drawn upward from its
        // base tile, never by a larger in-band offset.
        let heightClasses: [BuildingCatalog.HeightClass] = [.lowest, .low, .mid, .tall, .large]
        for heightClass in heightClasses {
            let tallestLegalBuildingContentOffset = DepthModel.buildingContentRange.upperBound - 0.001
            let buildingZ = band + tallestLegalBuildingContentOffset

            XCTAssertLessThan(
                buildingZ,
                playerZ,
                "A \(heightClass) building sharing the player's band must never reach the player's zPosition."
            )
        }
    }

    // MARK: - Production wiring: PlayerNode actually uses DepthBanding

    func test_playerNode_updateDepth_setsZPosition_toDepthBandingsWorldLayerRelativeValue() {
        let player = PlayerNode()
        let position = TilePoint(x: 7, y: -11)

        player.updateDepth(atTilePosition: position)

        let expectedAbsolute = DepthBanding.playerZPosition(at: position)
        let expectedRelative = DepthModel.worldLayerRelativeZ(forAbsoluteZ: expectedAbsolute)

        // `player.zPosition` is read back from a live `SKNode`, which (unlike
        // the pure-Swift `DepthModel`/`DepthBanding` math above) SpriteKit is
        // free to store internally at `Float` (32-bit) precision. At this
        // zPosition's magnitude (tens of thousands) a `Float`'s own ULP is on
        // the order of a few thousandths, so a tight `1e-9` accuracy -- fine
        // for the pure-math assertions elsewhere in this file -- would flake
        // on nothing more than that internal truncation. `0.01` is far
        // larger than that truncation error yet far smaller than the
        // `bandSpacing`/offset differences this test actually needs to
        // catch.
        XCTAssertEqual(player.zPosition, expectedRelative, accuracy: 0.01)
    }
}
