import CoreGraphics
import SpriteKit
import UIKit

/// The measured-geometry contract for one imported atlas-sheet image.
///
/// `docs/bootstrap.md` §2 requires every sheet's pixel dimensions and cell
/// grid to be measured programmatically, never inferred from a filename or
/// copied from the design brief without checking. `SpriteSheet.init` enforces
/// that: it compares the declared `pixelSize` against
/// `measuredPixelSize(forImageNamed:)` and treats any mismatch as a hard
/// failure (`precondition`), not a silent pass or a logged warning. Every
/// sheet family is declared exactly once, in `AtlasSheet`, and every
/// texture-cropping call site goes through `texture(col:row:)` /
/// `texture(forPixelRect:)` here rather than constructing its own crop rect
/// (`AtlasContractConventionTests` enforces that).
struct SpriteSheet {
    /// Imageset name in `Assets.xcassets/Atlas/`.
    let imageID: String

    /// Declared full-sheet pixel size, checked against the measured image at
    /// init time.
    let pixelSize: CGSize

    /// Declared cell size in pixels for this family's uniform grid, or `nil`
    /// for a sheet that packs non-uniform sub-rects instead of a regular
    /// grid (currently only `tileset_ground` — see `AtlasSheet.swift`).
    let cellSize: CGSize?

    /// Column count, derived from the measured `pixelSize` and the declared
    /// `cellSize` — never a separately-declared number that could drift from
    /// either.
    var columns: Int {
        guard let cellSize = cellSize, cellSize.width > 0 else { return 0 }
        return Int(pixelSize.width / cellSize.width)
    }

    /// Row count, derived the same way.
    var rows: Int {
        guard let cellSize = cellSize, cellSize.height > 0 else { return 0 }
        return Int(pixelSize.height / cellSize.height)
    }

    init(imageID: String, pixelSize: CGSize, cellSize: CGSize?) {
        self.imageID = imageID
        self.pixelSize = pixelSize
        self.cellSize = cellSize

        let measured = Self.measuredPixelSize(forImageNamed: imageID)
        precondition(
            measured == pixelSize,
            "\(imageID) measures \(measured) but the atlas contract declares \(pixelSize). "
                + "Fix the AtlasSheet declaration to match the shipped art, or fix the art — "
                + "never silence this check."
        )
    }

    /// Cuts a `(col, row)` cell out of the sheet as a nearest-filtered,
    /// mipmap-free `SKTexture`.
    ///
    /// `col`/`row` are read the way the design table lists them: `row == 0`
    /// is the sheet's *top* image row. SpriteKit textures are normalized in
    /// a bottom-left-origin coordinate space, so that row maps to the
    /// *highest* `y` in `textureRect`'s (0...1) space, not the lowest —
    /// `normalizedRect(forPixelRect:sheetPixelSize:)` below does that flip in
    /// one place so no consumer has to reason about it per call site.
    func texture(col: Int, row: Int) -> SKTexture {
        guard let cellSize = cellSize else {
            preconditionFailure("\(imageID) has no uniform cell size; use texture(forPixelRect:) instead.")
        }
        let topLeftPixelRect = CGRect(
            x: CGFloat(col) * cellSize.width,
            y: CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
        return texture(forPixelRect: topLeftPixelRect)
    }

    /// Cuts an explicit pixel rect — top-left origin, exactly as it would be
    /// read off the image in an editor — out of the sheet. Used for
    /// non-uniform sub-rects such as `tileset_ground`'s six diamonds.
    func texture(forPixelRect pixelRect: CGRect) -> SKTexture {
        let sheetTexture = TextureLoading.texture(named: imageID)
        let textureRect = Self.normalizedRect(forPixelRect: pixelRect, sheetPixelSize: pixelSize)
        return SKTexture(rect: textureRect, in: sheetTexture)
    }

    /// Converts a top-left-origin pixel rect into the bottom-left-origin,
    /// `0...1`-normalized rect `SKTexture(rect:in:)` expects.
    private static func normalizedRect(forPixelRect pixelRect: CGRect, sheetPixelSize: CGSize) -> CGRect {
        guard sheetPixelSize.width > 0, sheetPixelSize.height > 0 else { return .zero }
        let flippedY = sheetPixelSize.height - pixelRect.origin.y - pixelRect.height
        return CGRect(
            x: pixelRect.origin.x / sheetPixelSize.width,
            y: flippedY / sheetPixelSize.height,
            width: pixelRect.width / sheetPixelSize.width,
            height: pixelRect.height / sheetPixelSize.height
        )
    }

    /// Measures an imported catalog image's real pixel size by decoding it —
    /// never by trusting a filename or a declared constant. An image that
    /// fails to resolve (missing/renamed imageset) measures as `.zero`, which
    /// reliably fails the `precondition` above rather than coincidentally
    /// matching a non-zero declared size.
    ///
    /// Exposed (not private) so tests can call the exact measurement the
    /// production init path uses, rather than a second copy that could drift
    /// from it — `AtlasDimensionsTests` relies on this.
    static func measuredPixelSize(forImageNamed name: String) -> CGSize {
        guard let image = UIImage(named: name, in: .appModule, compatibleWith: nil),
              let cgImage = image.cgImage
        else {
            return .zero
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
}

extension Bundle {
    private final class BundleToken {}

    /// The bundle holding the app module's asset catalog — correct both when
    /// the app runs and when the unit-test bundle is hosted inside it.
    static var appModule: Bundle { Bundle(for: BundleToken.self) }
}
