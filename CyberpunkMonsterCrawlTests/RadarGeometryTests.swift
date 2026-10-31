import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-23-t1`: pure tile<->radar mapping/scale/classification math,
/// provable entirely from unit tests with no scene construction (AC9/AC12).
final class RadarGeometryTests: XCTestCase {

    private let angleAccuracy = 1e-9

    // MARK: - (a) Direction-matching (AC9)

    /// For a sample of tile offsets, `RadarGeometry.radarPoint(
    /// forTileOffset:scale:)` and `IsometricProjection.tileToScreen` must
    /// agree on direction: the same sign on both axes, and the identical
    /// angle (`atan2`) within tolerance. `radarPoint` is built as a uniform
    /// positive rescaling of `tileToScreen`'s own output, so this is exact,
    /// not merely "close" -- but the test is written against
    /// `IsometricProjection` directly (per the implementation plan) rather
    /// than re-deriving the expectation, so a future change to either
    /// formula's sign convention is caught here.
    func test_radarPoint_matchesIsometricProjectionDirection_forASampleOfTileOffsets() {
        let scale: CGFloat = 10
        let offsets: [(x: Int, y: Int)] = [
            (3, -5), (-3, 5), (7, 7), (-7, -7), (1, 0), (0, 1), (-1, 0), (0, -1), (12, 4), (-4, 12),
        ]

        for offset in offsets {
            let radarPoint = RadarGeometry.radarPoint(forTileOffset: offset, scale: scale)
            let worldPoint = IsometricProjection.tileToScreen(tileX: Double(offset.x), tileY: Double(offset.y))

            XCTAssertEqual(
                radarPoint.x.sign, CGFloat(worldPoint.x).sign,
                "x-axis sign mismatch for offset \(offset)"
            )
            XCTAssertEqual(
                radarPoint.y.sign, CGFloat(worldPoint.y).sign,
                "y-axis sign mismatch for offset \(offset)"
            )

            let radarAngle = atan2(Double(radarPoint.y), Double(radarPoint.x))
            let worldAngle = atan2(Double(worldPoint.y), Double(worldPoint.x))
            XCTAssertEqual(
                radarAngle, worldAngle, accuracy: angleAccuracy,
                "angle mismatch for offset \(offset)"
            )
        }
    }

    // MARK: - (b) Scale invariance across orientation (AC12)

    /// A device rotating between portrait and landscape must not change how
    /// much world the radar shows: `radarScale(for:)` is keyed off
    /// `max(width, height)`, which is symmetric under the portrait/
    /// landscape transpose.
    func test_radarScale_isIdentical_forPortraitAndLandscapeOfTheSameDevice() {
        let portraitSize = CGSize(width: 390, height: 844)
        let landscapeSize = CGSize(width: 844, height: 390)

        XCTAssertEqual(
            RadarGeometry.radarScale(for: portraitSize),
            RadarGeometry.radarScale(for: landscapeSize)
        )
    }

    /// Pins the formula itself (`tileHalfWidth * 110 / (2.5 * max(w, h))`),
    /// not just the portrait/landscape symmetry above.
    func test_radarScale_matchesDocumentedFormula() {
        let sceneSize = CGSize(width: 400, height: 200)
        let expected = CGFloat(IsometricProjection.tileHalfWidth) * 110 / (2.5 * 400)

        XCTAssertEqual(RadarGeometry.radarScale(for: sceneSize), expected, accuracy: 1e-12)
    }

    // MARK: - (b2) radarScale composed with radarPoint (field of view)

    /// Raised on PR #78 review: every other test here pins one function
    /// against its own formula -- `radarScale` against its formula,
    /// `radarPoint` against a hard-coded `scale: 10` -- so a *unit*
    /// mismatch between the two (radar points per world *screen* point vs
    /// per *tile*, which differ by exactly `tileHalfWidth`) was invisible
    /// to the whole suite. This test feeds `radarScale(for:)`'s own output
    /// into `radarPoint` and asserts a plausible neighbourhood fits inside
    /// the dial, which is the property that actually has to hold once PR 2
    /// mounts this.
    func test_radarScale_composedWithRadarPoint_keepsTheNearNeighbourhoodInsideTheDial() {
        let scale = RadarGeometry.radarScale(for: CGSize(width: 390, height: 844))

        // ~20 tiles out is the "immediate neighbourhood" the ticket asks
        // the dial to show: still inside the content square.
        let nearOffsets: [(x: Int, y: Int)] = [(20, 0), (-20, 0), (0, 20), (0, -20), (14, 14), (-14, -14)]
        for offset in nearOffsets {
            let point = RadarGeometry.radarPoint(forTileOffset: offset, scale: scale)
            XCTAssertTrue(
                RadarGeometry.isWithinContentSquare(point),
                "expected offset \(offset) -> \(point) to fall inside the dial at scale \(scale)"
            )
        }

        // ~200 tiles out is far outside the documented field of view: a
        // scale off by `tileHalfWidth` would wrongly draw these inside.
        let farOffsets: [(x: Int, y: Int)] = [(200, 0), (-200, 0), (0, 200), (0, -200), (140, 140)]
        for offset in farOffsets {
            let point = RadarGeometry.radarPoint(forTileOffset: offset, scale: scale)
            XCTAssertFalse(
                RadarGeometry.isWithinContentSquare(point),
                "expected offset \(offset) -> \(point) to fall outside the dial at scale \(scale)"
            )
        }
    }

    /// The other half of the composition: the dial's half-extent, measured
    /// back out into *world screen points*, is exactly the documented
    /// "2.5x the device's longer screen dimension" (AC12's premise).
    func test_radarScale_fieldOfView_isTwoAndAHalfTimesTheLongerScreenDimension() {
        let longerDimension: CGFloat = 844
        let scale = RadarGeometry.radarScale(for: CGSize(width: 390, height: longerDimension))

        // `radarPoint` sets `x = (dx - dy) * scale`, so the content
        // square's 55pt half-extent is this many tiles of `(dx - dy)` ...
        let halfExtentInTiles = RadarGeometry.halfContentSquareSize / scale
        // ... which `IsometricProjection.tileToScreen` places this many
        // world screen points from the centre.
        let halfExtentInWorldPoints = halfExtentInTiles * CGFloat(IsometricProjection.tileHalfWidth)

        XCTAssertEqual(2 * halfExtentInWorldPoints, 2.5 * longerDimension, accuracy: 1e-9)
    }

    // MARK: - (c) Content-square window-inclusion boundary cases

    func test_isWithinContentSquare_trueAtOrigin() {
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(.zero))
    }

    func test_isWithinContentSquare_trueExactlyOnTheBoundary() {
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: 55, y: 55)))
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: -55, y: -55)))
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: 55, y: 0)))
        XCTAssertTrue(RadarGeometry.isWithinContentSquare(CGPoint(x: 0, y: -55)))
    }

    func test_isWithinContentSquare_falseJustOutsideTheBoundary() {
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 55.0001, y: 0)))
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 0, y: 55.0001)))
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: -55.0001, y: 0)))
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 0, y: -55.0001)))
    }

    func test_isWithinContentSquare_falseFarOutside() {
        XCTAssertFalse(RadarGeometry.isWithinContentSquare(CGPoint(x: 1000, y: 1000)))
    }

    // MARK: - (d) RadarBackdropRenderer.isTileBlocked

    /// Tile `(3, 3)` is a structural lattice-crossing tile: `xMod == 3` and
    /// `yMod == 3` both put it in the street band on *every* seed
    /// (`CityLatticeGenerator`'s own doc comment -- street-ness is never
    /// seed-driven), so `classify` never reports `.buildingFootprint` here
    /// regardless of which seed is used.
    private let guaranteedStreetTile = (tileX: 3, tileY: 3)

    func test_isTileBlocked_falseWhenNeitherLatticeNorObstructionBlocksIt() {
        let seed = WorldSeed(rawValue: 1)

        XCTAssertFalse(
            RadarBackdropRenderer.isTileBlocked(
                tileX: guaranteedStreetTile.tileX,
                tileY: guaranteedStreetTile.tileY,
                seed: seed,
                buildingRecords: []
            )
        )
    }

    func test_isTileBlocked_trueWhenTheLatticeClassifiesItAsABuildingFootprint() throws {
        // Tile (0, 0) is always a block interior (`xMod == 0`, `yMod == 0`,
        // both below `CityLatticeGenerator.blockSize`), so its kind is
        // entirely decided by block (0, 0)'s own seed-driven
        // empty-lot/building decision. Scan seeds until one lands on
        // "built" -- `CityLatticeGenerator`'s own ~1-in-4-empty ratio means
        // this converges almost immediately.
        var blockedSeed: WorldSeed?
        for candidate in UInt64(0)..<50 {
            let seed = WorldSeed(rawValue: candidate)
            let info = CityLatticeGenerator.classify(tileX: 0, tileY: 0, seed: seed)
            if info.kind == .buildingFootprint {
                blockedSeed = seed
                break
            }
        }
        let seed = try XCTUnwrap(blockedSeed, "expected at least one seed in 0..<50 to build block (0, 0)")

        XCTAssertTrue(
            RadarBackdropRenderer.isTileBlocked(tileX: 0, tileY: 0, seed: seed, buildingRecords: [])
        )
    }

    func test_isTileBlocked_trueWhenAPlacementRecordObstructsIt_evenOnAStreetTile() {
        let seed = WorldSeed(rawValue: 1)
        let tile = TileCoordinate(tileX: guaranteedStreetTile.tileX, tileY: guaranteedStreetTile.tileY)
        let record = BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entries[0],
            footprintTiles: [tile],
            farCornerTile: tile
        )

        // Precondition: the lattice itself does not call this a building --
        // the `true` result below must come from the obstruction check, not
        // from `classify`.
        XCTAssertNotEqual(
            CityLatticeGenerator.classify(
                tileX: guaranteedStreetTile.tileX, tileY: guaranteedStreetTile.tileY, seed: seed
            ).kind,
            .buildingFootprint
        )

        XCTAssertTrue(
            RadarBackdropRenderer.isTileBlocked(
                tileX: guaranteedStreetTile.tileX,
                tileY: guaranteedStreetTile.tileY,
                seed: seed,
                buildingRecords: [record]
            )
        )
    }

    // MARK: - (e) RadarBackdropRenderer rasterization (raised on PR #78)

    /// The scene size every rasterization case below renders for -- a real
    /// device's portrait size, so `scale` is the production value rather
    /// than a convenient round number.
    private static let rasterSceneSize = CGSize(width: 390, height: 844)

    /// `RadarBackdropRenderer.tileOffset(forRadarPoint:scale:)` is the
    /// inversion the rasterizer runs once per output pixel. Nothing pinned
    /// it against `radarPoint`'s forward transform, so the algebra could
    /// drift silently if either formula changed -- this round-trips a
    /// sample of offsets at the real production scale.
    func test_tileOffset_roundTripsRadarPoint_forASampleOfTileOffsets() {
        let scale = RadarGeometry.radarScale(for: Self.rasterSceneSize)
        let offsets: [(x: Int, y: Int)] = [
            (0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (3, 3), (-3, -3), (7, -5), (-5, 7), (20, 20), (-18, 4),
        ]

        for offset in offsets {
            let point = RadarGeometry.radarPoint(forTileOffset: offset, scale: scale)
            let roundTripped = RadarBackdropRenderer.tileOffset(forRadarPoint: point, scale: scale)

            XCTAssertEqual(roundTripped.x, offset.x, "dx round-trip mismatch for offset \(offset)")
            XCTAssertEqual(roundTripped.y, offset.y, "dy round-trip mismatch for offset \(offset)")
        }
    }

    func test_tileOffset_reportsTheCentreTile_forADegenerateScale() {
        let offset = RadarBackdropRenderer.tileOffset(forRadarPoint: CGPoint(x: 10, y: 10), scale: 0)

        XCTAssertEqual(offset.x, 0)
        XCTAssertEqual(offset.y, 0)
    }

    /// AC9's "up on the radar means up on the screen" has to survive the
    /// `CGContext` -> `CGImage` hand-off, not just `radarPoint`'s own
    /// formula: a y-flip there mirrors the whole dial north/south while
    /// every existing test still passes. A blocked tile whose offset
    /// projects *up* must only ever paint pixels in the bitmap's top half.
    func test_makeBackdropImage_paintsAnUpwardBlockedTile_intoTheTopHalfOfTheBitmap() throws {
        let rows = try changedPixelRows(forBlockedTileOffset: (x: 3, y: 3))
        let halfHeight = RadarBackdropRenderer.contentSquarePixelSize(forDeviceScale: 1) / 2

        XCTAssertFalse(rows.isEmpty, "expected the added placement record to paint at least one pixel")
        for row in rows {
            XCTAssertLessThan(row, halfHeight, "an upward tile painted into the bottom half (row \(row))")
        }
    }

    /// The mirror case -- without it, an image flipped *and* a tile offset
    /// flipped would cancel out above.
    func test_makeBackdropImage_paintsADownwardBlockedTile_intoTheBottomHalfOfTheBitmap() throws {
        let rows = try changedPixelRows(forBlockedTileOffset: (x: -3, y: -3))
        let halfHeight = RadarBackdropRenderer.contentSquarePixelSize(forDeviceScale: 1) / 2

        XCTAssertFalse(rows.isEmpty, "expected the added placement record to paint at least one pixel")
        for row in rows {
            XCTAssertGreaterThanOrEqual(
                row, halfHeight, "a downward tile painted into the top half (row \(row))"
            )
        }
    }

    /// The backdrop rasterizes at the device's own pixel density (the
    /// behaviour `HUDRunModel.deviceScale` is for): 110pt of dial is 110px
    /// at `@1x` but 330px at `@3x`, so the mounting PR can draw it 1:1 on
    /// the pixel grid instead of upscaling a 110px bitmap into a blur.
    func test_makeBackdropImage_rasterizesAtTheDeviceScale_notAtAFixedPointSize() throws {
        let scale = RadarGeometry.radarScale(for: Self.rasterSceneSize)

        for deviceScale in [CGFloat(1), 2, 3] {
            let image = try XCTUnwrap(RadarBackdropRenderer.makeBackdropImage(
                playerTile: TileCoordinate(tileX: 0, tileY: 0),
                seed: WorldSeed(rawValue: 1),
                buildingRecords: [],
                scale: scale,
                deviceScale: deviceScale
            ))
            let expected = Int(RadarGeometry.contentSquareSize * deviceScale)

            XCTAssertEqual(image.width, expected, "wrong pixel width at deviceScale \(deviceScale)")
            XCTAssertEqual(image.height, expected, "wrong pixel height at deviceScale \(deviceScale)")
        }
    }

    /// A headless (view-less) scene reports no usable device scale; the
    /// bitmap floors at the `@1x` size rather than collapsing to nothing.
    func test_contentSquarePixelSize_floorsADegenerateDeviceScaleAtOne() {
        XCTAssertEqual(RadarBackdropRenderer.contentSquarePixelSize(forDeviceScale: 0), 110)
        XCTAssertEqual(RadarBackdropRenderer.contentSquarePixelSize(forDeviceScale: 1), 110)
        XCTAssertEqual(RadarBackdropRenderer.contentSquarePixelSize(forDeviceScale: 3), 330)
    }

    // MARK: - (e) Measured rebuild cost at @3x

    /// Puts a **number** on one backdrop rebuild, which the mounting PR
    /// (`CYBERPUN-17-23-t2`) was asked for and did not have: the
    /// rasterization runs synchronously on the gameplay update thread
    /// (`advanceMovementAndCamera(currentTime:)` -> `hudLayer?.refresh()`)
    /// and is triggered by the player crossing a tile boundary, which at
    /// walking speed is several times a second (PR #79 review). "Not every
    /// frame" is not the same claim as "cheap enough for the frame it
    /// lands on".
    ///
    /// Deliberately the worst realistic case: `@3x` (330x330 = 108,900
    /// pixel fills) against the building records of a real, fully-streamed
    /// resident window, so each *distinct* tile pays a
    /// `CityLatticeGenerator.classify` hash plus a linear
    /// `BuildingObstruction.isObstructed` scan of the whole record set --
    /// the same work production does, not a synthetic empty-records run.
    ///
    /// **Measured: ~25 ms** for one rebuild over 498 resident records
    /// (iPhone 16 simulator, **Debug/unoptimized**, 2026-10-30). That is
    /// well past a 16.7 ms frame, so it is recorded in
    /// `RadarBackdropRenderer`'s cost note and `RadarMapNode`'s caching
    /// note as a known cost rather than left as prose. A Debug pixel loop
    /// is not the shipping figure -- `-Onone` penalizes this kind of inner
    /// loop heavily -- but it is the number this PR actually has, and it
    /// is large enough that the off-thread/oversized-window escapes the
    /// reviewer named want a Release profile on a device before anyone
    /// calls this settled.
    ///
    /// The threshold below is an order-of-magnitude regression alarm, not
    /// a frame budget: a shared CI host is far too noisy to assert the
    /// measured figure itself without flaking, so the test takes the
    /// *fastest* of several runs (the least noise-contaminated sample) and
    /// fails only if even that is wildly out -- ~20x headroom over the
    /// figure above (observed CI best-of-5 samples have landed as high as
    /// ~337 ms on noisy shared hardware, well above the original 150 ms/
    /// ~6x ceiling, with no corresponding product regression).
    func test_makeBackdropImage_oneRebuildAtThreeX_staysWithinItsRegressionBudget() throws {
        let seed = WorldSeed(rawValue: 2_024)
        let streaming = ChunkStreamingManager(seed: seed)
        streaming.updateCamera(worldPosition: TilePoint(x: 0, y: 0))
        let buildingRecords = streaming.residentChunks.values.flatMap(\.buildingPlacements)
        XCTAssertFalse(buildingRecords.isEmpty, "precondition: a real resident window places buildings")

        let scale = RadarGeometry.radarScale(for: Self.rasterSceneSize)
        let playerTile = TileCoordinate(tileX: 0, tileY: 0)

        var best = Double.greatestFiniteMagnitude
        for iteration in 0..<5 {
            let start = Date()
            let image = RadarBackdropRenderer.makeBackdropImage(
                playerTile: TileCoordinate(tileX: playerTile.tileX + iteration, tileY: playerTile.tileY),
                seed: seed,
                buildingRecords: buildingRecords,
                scale: scale,
                deviceScale: 3
            )
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertNotNil(image, "the rasterizer must produce an image to have measured anything")
            best = min(best, elapsed)
        }

        let milliseconds = best * 1_000
        print(
            "MEASURED RadarBackdropRenderer.makeBackdropImage @3x "
                + "(\(buildingRecords.count) resident records): \(String(format: "%.2f", milliseconds)) ms"
        )

        XCTAssertLessThan(
            milliseconds, 500,
            "one @3x backdrop rebuild over \(buildingRecords.count) resident records took "
                + "\(String(format: "%.2f", milliseconds)) ms -- an order-of-magnitude regression on the "
                + "~25 ms this was measured at, and it runs synchronously on the gameplay update thread"
        )
    }

    // MARK: - (e) helpers

    /// Renders the backdrop twice -- once with no placement records, once
    /// with a single record obstructing the tile at `offset` from the
    /// player -- and returns the top-down row index (row 0 == the top of
    /// the image) of every pixel that differs between the two.
    ///
    /// Diffing rather than inspecting absolute colours because the seeded
    /// lattice paints blocked tiles all over the dial under every seed;
    /// the difference between the two renders is exactly the one tile
    /// under test.
    private func changedPixelRows(forBlockedTileOffset offset: (x: Int, y: Int)) throws -> [Int] {
        let seed = WorldSeed(rawValue: 1)
        let playerTile = TileCoordinate(tileX: 0, tileY: 0)
        let scale = RadarGeometry.radarScale(for: Self.rasterSceneSize)
        let tile = TileCoordinate(
            tileX: playerTile.tileX + offset.x,
            tileY: playerTile.tileY + offset.y
        )

        // Precondition: `(+/-3, +/-3)` is street on every seed (both axes
        // land in the street band), so the lattice does not already call
        // this tile blocked and every changed pixel is the record's doing.
        XCTAssertNotEqual(
            CityLatticeGenerator.classify(tileX: tile.tileX, tileY: tile.tileY, seed: seed).kind,
            .buildingFootprint
        )

        let record = BuildingPlacementRecord(
            lotTile: tile,
            building: BuildingCatalog.entries[0],
            footprintTiles: [tile],
            farCornerTile: tile
        )

        let baseline = try XCTUnwrap(RadarBackdropRenderer.makeBackdropImage(
            playerTile: playerTile, seed: seed, buildingRecords: [], scale: scale, deviceScale: 1
        ))
        let withRecord = try XCTUnwrap(RadarBackdropRenderer.makeBackdropImage(
            playerTile: playerTile, seed: seed, buildingRecords: [record], scale: scale, deviceScale: 1
        ))

        let baselineBytes = try XCTUnwrap(rgbaBytes(of: baseline))
        let recordBytes = try XCTUnwrap(rgbaBytes(of: withRecord))
        XCTAssertEqual(baselineBytes.count, recordBytes.count)

        let width = baseline.width
        var rows: [Int] = []
        for index in stride(from: 0, to: min(baselineBytes.count, recordBytes.count), by: 4) {
            let differs = baselineBytes[index] != recordBytes[index]
                || baselineBytes[index + 1] != recordBytes[index + 1]
                || baselineBytes[index + 2] != recordBytes[index + 2]
            if differs {
                rows.append(index / 4 / width)
            }
        }
        return rows
    }

    /// `image`'s pixels as top-down RGBA8 rows, by redrawing it into a
    /// bitmap context of known layout (a `CGImage`'s own backing store is
    /// not directly addressable, and an `SKTexture`'s needs a live
    /// renderer -- which is why `makeBackdropImage` is split out of
    /// `makeBackdropTexture` at all).
    private func rgbaBytes(of image: CGImage) -> [UInt8]? {
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
