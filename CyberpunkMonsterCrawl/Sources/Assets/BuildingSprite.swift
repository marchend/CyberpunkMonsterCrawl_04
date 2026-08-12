import Foundation

/// The 12 building sprites the city lattice places whole (`building_00` …
/// `building_11`), declared here as the single owning manifest.
///
/// The art itself is **not imported yet** — that import is
/// CYBERPUN-17-1-t4. The manifest exists anyway, deliberately: the v1 failure
/// class this rebuild exists to prevent is "empty catalog, green suite", and
/// the only thing that keeps a missing asset family visible is a reference in
/// code that a test can fail on. `BuildingCatalogTests` asserts every id below
/// resolves in `Assets.xcassets` and that the 12 are distinct art (not
/// duplicates or horizontal mirrors of each other), both currently wrapped in
/// a *strict* `XCTExpectFailure` tagged `SCAFFOLDING(CYBERPUN-17-1-t4)` — so
/// the gate flips to "expected failure not recorded" the moment the art
/// lands, and cannot be left muting a real regression.
///
/// Buildings are loaded whole via `TextureLoading.texture(named:)` and never
/// sliced, which is why they are not a `SpriteSheet`: there is no cell grid to
/// measure. Their per-sprite measured pixel size / footprint / height class
/// lands with the art in t4, measured from the imported image the same way
/// `SpriteSheet` measures the atlas sheets — never declared from a filename.
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

    /// Imageset name backing this case: `building_00` … `building_11`.
    var imageID: String {
        String(format: "building_%02d", rawValue)
    }
}
