import CoreGraphics
import UIKit
@testable import CyberpunkMonsterCrawl

/// Decodes an imported catalog image down to its raw RGBA bytes so the asset
/// gates can assert *measured* pixel facts (where the art actually sits, what
/// its alpha channel holds, whether two sheets ship identical or mirrored
/// pixels) instead of restating numbers from a doc comment.
///
/// Lives in the test target only: nothing in the render path decodes bytes by
/// hand, and `AtlasContractConventionTests` scans the production tree, not
/// this file.
enum ImagePixelSampling {

    /// `CGImageAlphaInfo` values that mean "this decoded image actually
    /// carries an alpha channel". Anything else (`.none`, `.noneSkipFirst`,
    /// `.noneSkipLast`) is an opaque image — the usual cause is a re-export
    /// that flattened transparency, whose first symptom at render time is a
    /// black box behind every sprite.
    ///
    /// Declared once here so the atlas gate (`AtlasCatalogTests`) and the
    /// building gate (`BuildingCatalogTests`) measure the *same* rule rather
    /// than keeping two copies that could drift apart.
    static let alphaCarryingInfos: [CGImageAlphaInfo] = [
        .first,
        .last,
        .premultipliedFirst,
        .premultipliedLast,
        .alphaOnly,
    ]

    /// The alpha info the named imageset's **source** image decodes with, or
    /// `nil` when the imageset is missing from the catalog — callers turn
    /// that into an explicit failure rather than a quiet skip.
    ///
    /// Read off the original `CGImage` on purpose: `pixels(ofImageNamed:)`
    /// redraws into a `premultipliedLast` context, so its buffer always
    /// *has* an alpha channel even when the imported art is flat. Container
    /// alpha and actual transparent pixels are therefore two separate
    /// measurements, and both matter.
    static func sourceAlphaInfo(ofImageNamed name: String) -> CGImageAlphaInfo? {
        guard let image = UIImage(named: name, in: .appModule, compatibleWith: nil),
              let cgImage = image.cgImage
        else {
            return nil
        }
        return cgImage.alphaInfo
    }

    /// One decoded image, addressed in the same top-left-origin pixel space
    /// `AtlasGroundDiamond.pixelRect` uses.
    struct Pixels {
        let width: Int
        let height: Int

        /// 8-bit RGBA, row-major, **top row first** — a `CGBitmapContext`
        /// lays its memory out top-down even though its drawing coordinate
        /// space is bottom-up, so `rgba[(y * width + x) * 4 + 3]` is the
        /// alpha of the pixel at top-left-origin `(x, y)`.
        let rgba: [UInt8]

        func alpha(x: Int, y: Int) -> UInt8 {
            guard x >= 0, x < width, y >= 0, y < height else { return 0 }
            return rgba[(y * width + x) * 4 + 3]
        }

        func isOpaque(x: Int, y: Int) -> Bool {
            alpha(x: x, y: y) > 0
        }

        /// Number of fully transparent (alpha == 0) pixels in the image.
        ///
        /// Zero means the art fills its whole bounding box opaquely, which
        /// for a sprite placed whole on the lattice is the flattened-export
        /// failure: it draws as a solid rectangle over the ground tiles.
        var fullyTransparentPixelCount: Int {
            var total = 0
            for y in 0..<height {
                for x in 0..<width where alpha(x: x, y: y) == 0 {
                    total += 1
                }
            }
            return total
        }

        /// Number of rows carrying any opaque pixel in column `x`.
        func columnCoverage(_ x: Int) -> Int {
            (0..<height).reduce(into: 0) { total, y in
                if isOpaque(x: x, y: y) { total += 1 }
            }
        }

        /// Half-open bounding box of the opaque pixels found in `columns`, or
        /// `nil` when that column range holds no opaque pixel at all (which
        /// the callers treat as a hard failure rather than a pass).
        func contentBounds(inColumns columns: Range<Int>) -> (x: Range<Int>, y: Range<Int>)? {
            var minX = Int.max
            var maxX = Int.min
            var minY = Int.max
            var maxY = Int.min

            for x in columns.clamped(to: 0..<width) {
                for y in 0..<height where isOpaque(x: x, y: y) {
                    minX = Swift.min(minX, x)
                    maxX = Swift.max(maxX, x)
                    minY = Swift.min(minY, y)
                    maxY = Swift.max(maxY, y)
                }
            }

            guard minX <= maxX, minY <= maxY else { return nil }
            return (x: minX..<(maxX + 1), y: minY..<(maxY + 1))
        }

        /// The same image with every row reversed — used to catch "12 distinct
        /// buildings" that are really six pieces of art plus six horizontal
        /// flips.
        func horizontallyMirroredRGBA() -> [UInt8] {
            var mirrored = [UInt8](repeating: 0, count: rgba.count)
            for y in 0..<height {
                for x in 0..<width {
                    let source = (y * width + x) * 4
                    let destination = (y * width + (width - 1 - x)) * 4
                    for component in 0..<4 {
                        mirrored[destination + component] = rgba[source + component]
                    }
                }
            }
            return mirrored
        }

        /// Content fingerprint of the decoded pixels, dimensions included so
        /// two differently-sized images can never collide.
        var fingerprint: UInt64 {
            ImagePixelSampling.fingerprint(width: width, height: height, bytes: rgba)
        }

        var mirroredFingerprint: UInt64 {
            ImagePixelSampling.fingerprint(width: width, height: height, bytes: horizontallyMirroredRGBA())
        }
    }

    /// FNV-1a over the decoded bytes. Not a cryptographic hash — it only has
    /// to make "these two imagesets are the same art" cheap to state.
    static func fingerprint(width: Int, height: Int, bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for seed in [UInt64(width), UInt64(height)] {
            for shift in stride(from: 0, through: 56, by: 8) {
                hash ^= (seed >> UInt64(shift)) & 0xff
                hash = hash &* 0x100_0000_01b3
            }
        }
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

    /// Decodes the named imageset, or returns `nil` if it is missing from the
    /// catalog or cannot be drawn — callers turn that into an explicit
    /// failure rather than a quiet skip.
    static func pixels(ofImageNamed name: String) -> Pixels? {
        guard let image = UIImage(named: name, in: .appModule, compatibleWith: nil),
              let cgImage = image.cgImage
        else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

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
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        )

        var rgba = [UInt8](repeating: 0, count: byteCount)
        for index in 0..<byteCount {
            rgba[index] = buffer[index]
        }

        return Pixels(width: width, height: height, rgba: rgba)
    }
}
