import CoreGraphics

/// Shared pixel-decoding helper for the test target.
///
/// Lifted out of `RadarGeometryTests` and `RadarMapNodeTests`, which each
/// carried a verbatim `private func rgbaBytes(of:)` copy (PR #80 review:
/// "lifting it into a shared test helper would be cheaper than the third
/// copy when it arrives"). An `enum` namespace rather than a free function,
/// matching the app module's own convention for stateless helpers
/// (`RadarBackdropRenderer`, `PixelCrispness`, `IsometricProjection`).
enum CGImagePixels {

    /// `image`'s pixels as top-down RGBA8 rows, by redrawing it into a
    /// bitmap context of known layout.
    ///
    /// A `CGImage`'s own backing store is not directly addressable, and an
    /// `SKTexture`'s needs a live renderer -- which is why
    /// `RadarBackdropRenderer.makeBackdropImage` is split out of
    /// `makeBackdropTexture` at all. Returns `nil` if the bitmap context
    /// could not be created, so a caller can `XCTUnwrap` it rather than
    /// silently comparing an all-zero buffer.
    static func rgbaBytes(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return drew ? bytes : nil
    }
}
