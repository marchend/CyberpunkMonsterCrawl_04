import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-1 AC 5 (this PR's slice): every `BuildingSprite` case must
/// resolve to a real imageset and measure exactly as its table row declares.
///
/// `BuildingCatalogTests` separately gates catalog existence + distinctness
/// (duplicate / mirrored art) off decoded pixel fingerprints; this file
/// focuses on the per-building **table contract** — declared pixel size,
/// footprint, height class — and on the whole-image `TextureLoading` path
/// buildings are required to use instead of a sliced cell rect.
final class BuildingSpriteTests: XCTestCase {

    /// Guards every loop below against silently iterating zero/duplicate
    /// cases.
    func test_buildingSprite_allCases_covers12DistinctImageIDs() {
        XCTAssertEqual(BuildingSprite.allCases.count, 12)
        XCTAssertEqual(Set(BuildingSprite.allCases.map(\.imageID)).count, 12)
    }

    /// Every case's `measuredPixelSize` must resolve (i.e. the imageset must
    /// exist) and must equal `declaredPixelSize` — the same measure-not-infer
    /// convention `SpriteSheet.init` enforces for the atlas sheets. A missing
    /// imageset would trip `measuredPixelSize`'s `precondition` and abort the
    /// test process outright, which is the intended hard-failure behavior.
    func test_everyBuildingSprite_measuresExactlyAsTheTableDeclares() {
        for building in BuildingSprite.allCases {
            let measured = building.measuredPixelSize

            XCTAssertGreaterThan(measured.width, 0, "\(building.imageID) resolved to a zero-width image.")
            XCTAssertGreaterThan(measured.height, 0, "\(building.imageID) resolved to a zero-height image.")
            XCTAssertEqual(
                measured,
                building.declaredPixelSize,
                "\(building.imageID) measures \(measured) but the table declares \(building.declaredPixelSize)."
            )
        }
    }

    /// Pins the story's dimension table row-for-row, so a future edit to
    /// `BuildingSprite`'s switch statements cannot silently drift from the
    /// spec even though `measuredPixelSize` would still pass against
    /// whatever the (also edited) declared size says.
    func test_declaredPixelSize_matchesTheStorysBuildingTable() {
        let expected: [BuildingSprite: CGSize] = [
            .building00: CGSize(width: 96, height: 112),
            .building01: CGSize(width: 96, height: 112),
            .building02: CGSize(width: 96, height: 112),
            .building03: CGSize(width: 96, height: 112),
            .building04: CGSize(width: 96, height: 176),
            .building05: CGSize(width: 96, height: 240),
            .building06: CGSize(width: 96, height: 144),
            .building07: CGSize(width: 96, height: 144),
            .building08: CGSize(width: 144, height: 136),
            .building09: CGSize(width: 144, height: 136),
            .building10: CGSize(width: 96, height: 80),
            .building11: CGSize(width: 192, height: 192),
        ]

        XCTAssertEqual(expected.count, 12, "Table fixture must cover every BuildingSprite case.")
        for (building, size) in expected {
            XCTAssertEqual(building.declaredPixelSize, size, "\(building.imageID) declared size mismatch.")
        }
    }

    /// Pins the story's footprint column: `building_08`, `building_09` and
    /// `building_11` are the only 2×2 lots; every other building is 1×1.
    func test_footprint_matchesTheStorysBuildingTable() {
        let twoByTwo: Set<BuildingSprite> = [.building08, .building09, .building11]

        for building in BuildingSprite.allCases {
            let expected: BuildingSprite.Footprint = twoByTwo.contains(building) ? .twoByTwo : .oneByOne
            XCTAssertEqual(building.footprint, expected, "\(building.imageID) footprint mismatch.")
        }
    }

    /// Pins the story's height-class column.
    func test_heightClass_matchesTheStorysBuildingTable() {
        let expected: [BuildingSprite: BuildingSprite.HeightClass] = [
            .building00: .low,
            .building01: .low,
            .building02: .low,
            .building03: .low,
            .building04: .mid,
            .building05: .tall,
            .building06: .mid,
            .building07: .mid,
            .building08: .mid,
            .building09: .mid,
            .building10: .lowest,
            .building11: .large,
        ]

        XCTAssertEqual(expected.count, 12, "Table fixture must cover every BuildingSprite case.")
        for (building, heightClass) in expected {
            XCTAssertEqual(building.heightClass, heightClass, "\(building.imageID) height class mismatch.")
        }
    }

    /// Buildings load whole through the centralized `TextureLoading` factory
    /// — nearest-filtered, no mipmaps, non-zero size — never a sliced cell.
    func test_texture_loadsWholeThroughTextureLoading_nearestFiltered_nonZeroSized() {
        for building in BuildingSprite.allCases {
            let texture = building.texture

            XCTAssertEqual(
                texture.filteringMode,
                .nearest,
                "\(building.imageID) must be nearest-filtered so pixel-art scaling stays crisp."
            )
            XCTAssertFalse(texture.usesMipmaps, "\(building.imageID) must not use mipmaps.")
            XCTAssertGreaterThan(texture.size().width, 0, "\(building.imageID) resolved to a zero-width texture.")
            XCTAssertGreaterThan(texture.size().height, 0, "\(building.imageID) resolved to a zero-height texture.")
        }
    }
}
