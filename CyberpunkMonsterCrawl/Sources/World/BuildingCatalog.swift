import Foundation

/// The world-generation layer's own manifest of the 12 placeable building
/// sprites (`building_00` … `building_11`), independent of `Sources/Assets`
/// and SpriteKit entirely.
///
/// `BuildingPlacement`/`RooftopSignPlacement` are pure logic per this PR's
/// scope (`CYBERPUN-17-5-t1`) — they must never import SpriteKit merely to
/// know a building's footprint size or height class. `Sources/Assets/
/// BuildingSprite.swift` is the separate, SpriteKit-facing manifest that
/// actually loads the art; this table intentionally restates the same three
/// facts (asset name, footprint, height class) from the same story's
/// building table (`CYBERPUN-17-1`) rather than importing that enum, so the
/// `World` layer keeps its "zero SpriteKit dependency" contract. A rendering
/// consumer (a later story) is the piece that translates a
/// `BuildingCatalog.Entry.index` into the matching `BuildingSprite` case
/// (`BuildingSprite(rawValue: index)`).
enum BuildingCatalog {
    /// Coarse height category, straight from the story's building table —
    /// mirrors `BuildingSprite.HeightClass` case-for-case.
    enum HeightClass: Equatable {
        /// `building_10`, ~1 storey.
        case lowest
        /// `building_00`–`building_03`, ~2 storey.
        case low
        /// `building_04`, `building_06`, `building_07`, `building_08`,
        /// `building_09`: ~2–3 storey.
        case mid
        /// `building_05`, ~4 storey.
        case tall
        /// `building_11`, large tower.
        case large
    }

    /// One placeable building: its shipped-art asset name, world-grid
    /// footprint, and height class.
    struct Entry: Equatable {
        /// This entry's position in `BuildingCatalog.entries` — also its
        /// `building_NN` suffix (`0...11`).
        let index: Int
        /// Imageset name backing this entry: `building_00` … `building_11`.
        let assetName: String
        /// World-grid footprint this building reserves when placed —
        /// `.twoByTwo` for `building_08`/`building_09`/`building_11`,
        /// `.oneByOne` for every other entry, per the story's building
        /// table.
        let footprintSize: BuildingFootprintSize
        /// Coarse height category from the story's building table.
        let heightClass: HeightClass
    }

    /// The 12 entries, in `building_00` … `building_11` order — an
    /// order-independent lookup table (mirrors `GroundTileCatalog`'s own
    /// precedent of a static, semantic table over a measured asset family),
    /// kept in ascending index order here purely for readability against
    /// the story's table.
    static let entries: [Entry] = (0...11).map(makeEntry)

    /// Every entry whose footprint is `.oneByOne` — exactly the 9 entries
    /// that are *not* `building_08`/`building_09`/`building_11`. Exposed so
    /// `BuildingPlacement` can deterministically fall back to a 1x1 pick
    /// when a seed-chosen 2x2 building would not fit at the current lot,
    /// without re-deriving the footprint table itself.
    static let oneByOneEntries: [Entry] = entries.filter { $0.footprintSize == .oneByOne }

    /// The entry at `index` (`0...11`). Traps on an out-of-range index —
    /// every caller in this module indexes with a value already reduced
    /// modulo `entries.count`.
    static func entry(atIndex index: Int) -> Entry {
        entries[index]
    }

    private static func makeEntry(_ index: Int) -> Entry {
        Entry(
            index: index,
            assetName: String(format: "building_%02d", index),
            footprintSize: footprintSize(forIndex: index),
            heightClass: heightClass(forIndex: index)
        )
    }

    private static func footprintSize(forIndex index: Int) -> BuildingFootprintSize {
        switch index {
        case 8, 9, 11:
            return .twoByTwo
        default:
            return .oneByOne
        }
    }

    private static func heightClass(forIndex index: Int) -> HeightClass {
        switch index {
        case 0, 1, 2, 3:
            return .low
        case 4, 6, 7, 8, 9:
            return .mid
        case 5:
            return .tall
        case 10:
            return .lowest
        case 11:
            return .large
        default:
            preconditionFailure("BuildingCatalog index \(index) is outside the declared 0...11 range")
        }
    }
}
