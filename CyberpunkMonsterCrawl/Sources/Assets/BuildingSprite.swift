import CoreGraphics
import SpriteKit

/// The 12 building sprites the city lattice places whole (`building_00` …
/// `building_11`), declared here as the single owning manifest.
///
/// Each case records its declared pixel size, world-grid footprint and a
/// coarse height class straight from the story's building table
/// (CYBERPUN-17-1). `measuredPixelSize` checks the declared size against the
/// shipped art with a hard `precondition` — the same measurement convention
/// `SpriteSheet.init` uses for the atlas sheets, reusing
/// `SpriteSheet.measuredPixelSize(forImageNamed:)` rather than a second copy
/// of the decode logic that could drift from it. `BuildingSpriteTests`
/// enumerates every case and asserts the imageset exists and measures as
/// declared; `BuildingCatalogTests` additionally asserts the 12 pieces of art
/// are distinct (no duplicate or horizontally-mirrored building).
///
/// Buildings are loaded whole via `TextureLoading.texture(named:)` (exposed
/// here as `texture`) and never sliced, which is why this is not a
/// `SpriteSheet`: there is no cell grid to measure.
///
/// Placement logic, footprint reservation and depth-sorting are out of scope
/// here — a later story (footprint reservation lands with rooftop signs)
/// consumes this data; this manifest only records the measured facts.
enum BuildingSprite: Int, CaseIterable {
    case building00 = 0
    case building01 = 1
    case building02 = 2
    case building03 = 3
    case building04 = 4
    case building05 = 5
    case building06 = 6
    case building07 = 7
    case building08 = 8
    case building09 = 9
    case building10 = 10
    case building11 = 11

    /// World-grid footprint a building reserves when placed on a lot.
    enum Footprint: Equatable {
        case oneByOne
        case twoByTwo
    }

    /// Coarse height category from the story's building table.
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

    /// Imageset name backing this case: `building_00` … `building_11`.
    var imageID: String {
        String(format: "building_%02d", rawValue)
    }

    /// Declared full-sprite pixel size, taken verbatim from the story's
    /// building table and checked against the shipped art by
    /// `measuredPixelSize`.
    var declaredPixelSize: CGSize {
        switch self {
        case .building00, .building01, .building02, .building03:
            return CGSize(width: 96, height: 112)
        case .building04:
            return CGSize(width: 96, height: 176)
        case .building05:
            return CGSize(width: 96, height: 240)
        case .building06, .building07:
            return CGSize(width: 96, height: 144)
        case .building08, .building09:
            return CGSize(width: 144, height: 136)
        case .building10:
            return CGSize(width: 96, height: 80)
        case .building11:
            return CGSize(width: 192, height: 192)
        }
    }

    /// World-grid footprint this building reserves.
    var footprint: Footprint {
        switch self {
        case .building08, .building09, .building11:
            return .twoByTwo
        default:
            return .oneByOne
        }
    }

    /// Coarse height class from the story's building table.
    var heightClass: HeightClass {
        switch self {
        case .building00, .building01, .building02, .building03:
            return .low
        case .building04, .building06, .building07, .building08, .building09:
            return .mid
        case .building05:
            return .tall
        case .building10:
            return .lowest
        case .building11:
            return .large
        }
    }

    /// Measures this building's shipped art and asserts it matches
    /// `declaredPixelSize` — a hard failure (`precondition`), never a silent
    /// pass, exactly the convention `SpriteSheet.init` uses for the atlas
    /// sheets. A missing/renamed imageset measures as `.zero`, which
    /// reliably trips the precondition rather than coincidentally matching.
    var measuredPixelSize: CGSize {
        let measured = SpriteSheet.measuredPixelSize(forImageNamed: imageID)
        precondition(
            measured == declaredPixelSize,
            "\(imageID) measures \(measured) but BuildingSprite declares \(declaredPixelSize). "
                + "Fix the BuildingSprite table to match the shipped art, or fix the art — "
                + "never silence this check."
        )
        return measured
    }

    /// This building's whole-image texture, loaded via the centralized
    /// `TextureLoading` factory (nearest-filtered, no mipmaps) — never a
    /// sliced cell, since buildings are placed whole.
    var texture: SKTexture {
        TextureLoading.texture(named: imageID)
    }
}
