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
/// - `makeBackdropTexture(playerTile:seed:buildingRecords:scale:
///   deviceScale:)` rasterizes that predicate into a small `SKTexture`
///   sized to `RadarGeometry`'s 110x110 content square, at the device's
///   own pixel density.
///
/// **Scope of this PR (`CYBERPUN-17-23-t1`):** the pure classification plus
/// the texture builder only -- no SpriteKit *node* mounts this texture yet
/// (that is a later PR, the same "logic first, rendering/mounting is a
/// later PR" split `ChunkStreamingManager`/`GroundPlaneStreamer` and
/// `RaccoonSpawnDirector`/`RaccoonNode` already follow in this codebase).
enum RadarBackdropRenderer {
    /// Pixel dimensions of the rendered backdrop image at `deviceScale`.
    ///
    /// The dial is `RadarGeometry.contentSquareSize` **points** across, so
    /// the bitmap is that many *device pixels*: 110 at `@1x`, 220 at
    /// `@2x`, 330 at `@3x`. Rasterizing at a fixed 110 px for a 110 pt
    /// dial would hand the compositor a texture it has to upscale 2-3x on
    /// every shipping device -- exactly the blur `PixelCrispness` and this
    /// codebase's pixel-crispness evidence gate exist to prevent -- so the
    /// mounting PR sizes the sprite back down to 110 pt and the texture
    /// lands 1:1 on the device's own pixel grid.
    ///
    /// `deviceScale` is floored at `1`, the same headless (view-less)
    /// fallback `PixelCrispness.snappedPosition(for:scale:)`'s callers
    /// already use, so a degenerate scale can never ask for a zero-sized
    /// bitmap.
    static func contentSquarePixelSize(forDeviceScale deviceScale: CGFloat) -> Int {
        Int((RadarGeometry.contentSquareSize * max(deviceScale, 1)).rounded())
    }

    /// Inverts `RadarGeometry.radarPoint(forTileOffset:scale:)`: the tile
    /// offset whose radar-space point is nearest `point`.
    ///
    /// `radarPoint` computes `x = (dx - dy) * scale`,
    /// `y = (dx + dy) * (scale / 2)`, so for a given radar-space point
    /// `(x, y)`, `dx - dy = x / scale` and `dx + dy = 2y / scale`, giving
    /// `dx = (x + 2y) / (2 * scale)` and `dy = (2y - x) / (2 * scale)`.
    /// Rounded to the nearest tile, since a pixel generally lands between
    /// two tile centres.
    ///
    /// Lifted out of the rasterizer's inner loop (rather than left inline)
    /// so `RadarGeometryTests` can pin the round-trip --
    /// `radarPoint(forTileOffset:) -> tileOffset(forRadarPoint:)` returns
    /// the offset it started from -- directly, which is what stops this
    /// algebra drifting if `radarPoint`'s formula ever changes. A
    /// degenerate `scale <= 0` has no inverse and reports the centre tile.
    static func tileOffset(forRadarPoint point: CGPoint, scale: CGFloat) -> (x: Int, y: Int) {
        guard scale > 0 else { return (x: 0, y: 0) }
        let dx = Int(((point.x + 2 * point.y) / (2 * scale)).rounded())
        let dy = Int(((2 * point.y - point.x) / (2 * scale)).rounded())
        return (x: dx, y: dy)
    }

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
    /// Walks **output pixels**, not tile offsets, inverting
    /// `RadarGeometry.radarPoint(forTileOffset:scale:)` once per pixel via
    /// `tileOffset(forRadarPoint:scale:)`. Iterating tile offsets out to
    /// the content square's edge would instead scan a tile count that
    /// grows with `1 / scale`; walking pixels keeps this bounded by the
    /// bitmap, independent of how far `scale` lets the radar see.
    ///
    /// **Cost, and the rebuild cadence this implies.** The pixel walk is
    /// `contentSquarePixelSize(forDeviceScale:)^2` iterations -- 12,100 at
    /// `@1x`, 108,900 at `@3x` -- and each *distinct tile* costs a
    /// `CityLatticeGenerator.classify` hash plus a linear
    /// `BuildingObstruction.isObstructed` scan of every resident record.
    /// Neighbouring pixels overwhelmingly resolve to the same tile (a tile
    /// is ~2.5pt across at a phone's scale), so the classification is
    /// memoized per tile offset below and only the `context.fill` runs per
    /// pixel. Even so this is **not a per-frame operation**: the intended
    /// cadence for the mounting PR is a rebuild when the player's tile
    /// changes (or when the resident chunk window does), not once per
    /// `update(_:)`.
    ///
    /// `deviceScale` is the view's `contentScaleFactor` (`1` headless) --
    /// see `contentSquarePixelSize(forDeviceScale:)` for why the bitmap is
    /// sized in device pixels rather than points.
    static func makeBackdropTexture(
        playerTile: TileCoordinate,
        seed: WorldSeed,
        buildingRecords: [BuildingPlacementRecord],
        scale: CGFloat,
        deviceScale: CGFloat
    ) -> SKTexture {
        makeBackdropTexture(playerTile: playerTile, scale: scale, deviceScale: deviceScale) { tileX, tileY in
            isTileBlocked(tileX: tileX, tileY: tileY, seed: seed, buildingRecords: buildingRecords)
        }
    }

    /// The same rasterizer as above, generalized over an injected
    /// `isTileBlocked` predicate rather than a concrete `seed`/
    /// `buildingRecords` pair (`CYBERPUN-17-23-t2`).
    ///
    /// `RadarMapNode` -- the first and, today, only caller -- stays
    /// decoupled from `WorldSeed`/`BuildingPlacementRecord` this way, the
    /// same "take a plain predicate/value, not my internals" shape
    /// `TargetSelection.Candidate` already uses to keep that file decoupled
    /// from `RaccoonSpawnDirector`. The `seed`/`buildingRecords` overload
    /// above is kept as a thin convenience over this one (rather than
    /// removed) so `RadarGeometryTests`' existing calls keep compiling
    /// unchanged.
    static func makeBackdropTexture(
        playerTile: TileCoordinate,
        scale: CGFloat,
        deviceScale: CGFloat,
        isTileBlocked: (_ tileX: Int, _ tileY: Int) -> Bool
    ) -> SKTexture {
        guard let image = makeBackdropImage(
            playerTile: playerTile,
            scale: scale,
            deviceScale: deviceScale,
            isTileBlocked: isTileBlocked
        ) else {
            return SKTexture()
        }
        return SKTexture(cgImage: image)
    }

    /// The rasterization itself, stopping one step short of
    /// `makeBackdropTexture`'s `SKTexture` wrap.
    ///
    /// Split out because a `CGImage`'s pixels are directly readable in a
    /// headless unit test while an `SKTexture`'s are not (reading those
    /// back needs a live renderer), so `RadarGeometryTests` can pin the
    /// two things the rasterizer can get wrong -- the vertical orientation
    /// (a y-flip here would mirror the radar north/south and break AC9's
    /// "up means up" promise just as surely as a sign error in
    /// `radarPoint`) and the per-pixel tile inversion.
    static func makeBackdropImage(
        playerTile: TileCoordinate,
        seed: WorldSeed,
        buildingRecords: [BuildingPlacementRecord],
        scale: CGFloat,
        deviceScale: CGFloat
    ) -> CGImage? {
        makeBackdropImage(playerTile: playerTile, scale: scale, deviceScale: deviceScale) { tileX, tileY in
            isTileBlocked(tileX: tileX, tileY: tileY, seed: seed, buildingRecords: buildingRecords)
        }
    }

    /// The closure-based generalization of the rasterizer above -- see the
    /// closure-based `makeBackdropTexture(playerTile:scale:deviceScale:
    /// isTileBlocked:)` overload's own doc comment for why this exists
    /// alongside (rather than instead of) the `seed`/`buildingRecords`
    /// overload.
    static func makeBackdropImage(
        playerTile: TileCoordinate,
        scale: CGFloat,
        deviceScale: CGFloat,
        isTileBlocked: (_ tileX: Int, _ tileY: Int) -> Bool
    ) -> CGImage? {
        let pixelScale = max(deviceScale, 1)
        let size = contentSquarePixelSize(forDeviceScale: pixelScale)
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
            return nil
        }

        context.setFillColor(PixelGritPalette.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // A degenerate (zero or negative) scale has no meaningful inverse --
        // leave the backdrop as the plain background rather than dividing
        // by zero. Not reachable in production (`RadarGeometry.radarScale(
        // for:)` only returns 0 for a zero-area scene, which never mounts a
        // view), but keeps this function total for a direct test call.
        guard scale > 0 else {
            return context.makeImage()
        }

        context.setFillColor(PixelGritPalette.plate.cgColor)
        let half = CGFloat(size) / 2
        var blockedByTile: [TileCoordinate: Bool] = [:]

        for pixelY in 0..<size {
            // `py`/`px` below are in radar *points* (hence the divide by
            // `pixelScale`), expressed in the same "centred on the radar's
            // own origin, up is positive" convention `RadarGeometry
            // .radarPoint(forTileOffset:scale:)`'s forward transform uses.
            // `CGContext` is y-up too, so filling at `pixelY` keeps up
            // meaning up; `SKTexture(cgImage:)` preserves that orientation
            // (pinned by `RadarGeometryTests`, not assumed).
            let py = (CGFloat(pixelY) - half) / pixelScale
            for pixelX in 0..<size {
                let px = (CGFloat(pixelX) - half) / pixelScale

                let offset = tileOffset(forRadarPoint: CGPoint(x: px, y: py), scale: scale)
                let tile = TileCoordinate(
                    tileX: playerTile.tileX + offset.x,
                    tileY: playerTile.tileY + offset.y
                )

                let blocked: Bool
                if let memoized = blockedByTile[tile] {
                    blocked = memoized
                } else {
                    blocked = isTileBlocked(tile.tileX, tile.tileY)
                    blockedByTile[tile] = blocked
                }

                if blocked {
                    context.fill(CGRect(x: pixelX, y: pixelY, width: 1, height: 1))
                }
            }
        }

        return context.makeImage()
    }
}
