import CoreGraphics
import SpriteKit
import UIKit

/// Backdrop classification + rendering for the minimap radar
/// (`CYBERPUN-17-23`). Two independent jobs:
///
/// - `isTileBlocked(tileX:tileY:seed:buildingRecords:)` decides whether a
///   single world tile should read as "blocked" on the radar -- the same
///   two sources `CollisionResolver`/`GroundPlaneStreamer
///   .residentObstructions` already treat as solid for movement collision
///   (a seeded lattice `.buildingFootprint`, OR a chunk's own generated
///   `BuildingPlacementRecord` footprint -- `CityLatticeGenerator.classify`
///   alone cannot see a chunk's *placed* buildings, since those are a
///   `ChunkGenerator`-level decision layered on top of the lattice, not one
///   of `classify`'s own three inputs).
/// - `makeBackdropTexture(playerTile:seed:buildingRecords:scale:)`
///   rasterizes that predicate into a small `SKTexture` sized to
///   `RadarGeometry`'s 110x110 content square.
///
/// **Scope of this PR (`CYBERPUN-17-23-t1`):** the pure classification plus
/// the texture builder only -- no SpriteKit *node* mounts this texture yet
/// (that is a later PR, the same "logic first, rendering/mounting is a
/// later PR" split `ChunkStreamingManager`/`GroundPlaneStreamer` and
/// `RaccoonSpawnDirector`/`RaccoonNode` already follow in this codebase).
enum RadarBackdropRenderer {
    /// Pixel dimensions of the rendered backdrop image -- matches
    /// `RadarGeometry.contentSquareSize` 1:1, so the resulting texture can
    /// be drawn centred on the radar's own centre with no further scaling.
    static let contentSquarePixelSize = Int(RadarGeometry.contentSquareSize)

    /// Whether world tile `(tileX, tileY)` reads as blocked on the radar.
    static func isTileBlocked(
        tileX: Int,
        tileY: Int,
        seed: WorldSeed,
        buildingRecords: [BuildingPlacementRecord]
    ) -> Bool {
        let lattice = CityLatticeGenerator.classify(tileX: tileX, tileY: tileY, seed: seed)
        if lattice.kind == .buildingFootprint {
            return true
        }
        let tile = TileCoordinate(tileX: tileX, tileY: tileY)
        return BuildingObstruction.isObstructed(tile, byAnyOf: buildingRecords)
    }

    /// Rasterizes the blocked/open classification of every tile the radar's
    /// 110x110 content square can show (at `scale`, centred on
    /// `playerTile`) into a small bitmap: `PixelGritPalette.background` for
    /// open ground, `.plate` for a blocked tile -- the same two-tone "dark
    /// base, lighter plate" read every other piece of chrome in this
    /// palette already uses.
    ///
    /// Walks **output pixels**, not tile offsets. `RadarGeometry
    /// .radarScale(for:)` is tuned so the radar shows a field of view many
    /// multiples of the screen's own size -- i.e. a wide swath of world
    /// tiles compressed into a 110pt dial -- so iterating tile offsets out
    /// to the content square's edge would mean scanning a number of tiles
    /// that grows with `1 / scale`. Inverting `RadarGeometry.radarPoint(
    /// forTileOffset:scale:)`'s forward transform once per output pixel
    /// instead keeps this exactly `contentSquarePixelSize\u00b2` tile lookups,
    /// independent of how far `scale` lets the radar see.
    ///
    /// The inversion itself: `radarPoint` computes `x = (dx - dy) * scale`,
    /// `y = (dx + dy) * (scale / 2)`, so for a given radar-space point
    /// `(x, y)`, `dx - dy = x / scale` and `dx + dy = 2y / scale`, giving
    /// `dx = (x + 2y) / (2 * scale)` and `dy = (2y - x) / (2 * scale)`.
    /// Rounded to the nearest tile, since a pixel generally lands between
    /// two tile centers.
    static func makeBackdropTexture(
        playerTile: TileCoordinate,
        seed: WorldSeed,
        buildingRecords: [BuildingPlacementRecord],
        scale: CGFloat
    ) -> SKTexture {
        let size = contentSquarePixelSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SKTexture()
        }

        context.setFillColor(PixelGritPalette.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // A degenerate (zero or negative) scale has no meaningful inverse --
        // leave the backdrop as the plain background rather than dividing
        // by zero. Not reachable in production (`RadarGeometry.radarScale(
        // for:)` only returns 0 for a zero-area scene, which never mounts a
        // view), but keeps this function total for a direct test call.
        guard scale > 0 else {
            guard let image = context.makeImage() else { return SKTexture() }
            return SKTexture(cgImage: image)
        }

        context.setFillColor(PixelGritPalette.plate.cgColor)
        let half = CGFloat(size) / 2

        for pixelY in 0..<size {
            // `py`/`px` below are expressed in the same "centred on the
            // radar's own origin, up is positive" convention
            // `RadarGeometry.radarPoint(forTileOffset:scale:)`'s forward
            // transform uses, so this inversion matches it exactly.
            let py = CGFloat(pixelY) - half
            for pixelX in 0..<size {
                let px = CGFloat(pixelX) - half

                let dx = Int(((px + 2 * py) / (2 * scale)).rounded())
                let dy = Int(((2 * py - px) / (2 * scale)).rounded())

                let tileX = playerTile.tileX + dx
                let tileY = playerTile.tileY + dy
                if isTileBlocked(tileX: tileX, tileY: tileY, seed: seed, buildingRecords: buildingRecords) {
                    context.fill(CGRect(x: pixelX, y: pixelY, width: 1, height: 1))
                }
            }
        }

        guard let image = context.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }
}
