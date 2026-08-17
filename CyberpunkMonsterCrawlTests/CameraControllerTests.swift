import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-7` PR 2's camera/streaming half: `CameraController` keeps a
/// moving focus point centred on screen and drives chunk streaming with the
/// same focus point every call \u2014 pure geometry over a plain `SKNode`
/// container, never an `SKCameraNode` of its own (see the type's doc
/// comment for AGENT.md's camera-lock rationale).
final class CameraControllerTests: XCTestCase {

    private let portraitViewport = CGSize(width: 393, height: 852)
    private let landscapeViewport = CGSize(width: 852, height: 393)

    /// SpriteKit stores a node's `position` as a 32-bit float, so anything
    /// read back off `SKNode` carries that storage rounding: at the ~4,000
    /// point magnitudes this file's focus sweeps reach, consecutive
    /// representable floats are ~5e-4 apart. Added to the snap tolerances
    /// below so they measure the resolver's geometry rather than SpriteKit's
    /// storage -- the same distinction `FloatingThumbstickNodeTests` draws
    /// when it declines to assert exact values off a live node.
    private let spriteKitStorageEpsilon: CGFloat = 1e-3

    /// The honest centring contract now that the container offset is
    /// snapped to the device pixel grid (`PixelCrispness.snappedPosition(
    /// for:scale:)`): the focus lands *within half a device pixel* of the
    /// viewport centre, not exactly on it. A bare `1e-3` would have been a
    /// claim the snapped implementation cannot make -- and would have
    /// failed the moment snapping landed, which is the point.
    private func centringTolerance(deviceScale: CGFloat) -> CGFloat {
        0.5 / deviceScale + spriteKitStorageEpsilon
    }

    // MARK: - The focus point always converts to (within half a pixel of) screen centre

    func test_update_keepsAMovingFocusPoint_convertingToScreenCentre_inPortrait() {
        assertFocusConvertsToScreenCentre(viewportSize: portraitViewport)
    }

    func test_update_keepsAMovingFocusPoint_convertingToScreenCentre_inLandscape() {
        assertFocusConvertsToScreenCentre(viewportSize: landscapeViewport)
    }

    /// Real devices composite at `@2x`/`@3x`, where half a device pixel is
    /// a quarter or a sixth of a point -- so the centring is *tighter* on a
    /// real device than in the headless default, and the sweep proves it at
    /// each scale rather than only at the `1` fallback.
    func test_update_centresTheFocus_atEveryDeviceScale() {
        for deviceScale in [CGFloat(1), 2, 3] {
            assertFocusConvertsToScreenCentre(viewportSize: portraitViewport, deviceScale: deviceScale)
            assertFocusConvertsToScreenCentre(viewportSize: landscapeViewport, deviceScale: deviceScale)
        }
    }

    private func assertFocusConvertsToScreenCentre(
        viewportSize: CGSize,
        deviceScale: CGFloat = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let parent = SKNode()
        let container = SKNode()
        parent.addChild(container)

        let controller = CameraController(
            container: container,
            deviceScale: { deviceScale },
            streamingUpdate: { _ in }
        )
        let expectedCentre = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let tolerance = centringTolerance(deviceScale: deviceScale)

        let focusSweep = stride(from: -40.0, through: 40.0, by: 7.3).map { TilePoint(x: $0, y: -$0 * 0.5) }
        for focus in focusSweep {
            controller.update(focus: focus, viewportSize: viewportSize)

            // World content in this codebase is always parented at its own
            // raw `tileToScreen` position (unshifted) \u2014 the same
            // convention `GroundTileRenderer`/`TileFieldRenderer` follow \u2014
            // so a hypothetical child sitting exactly at the focus's own
            // projected point is what has to land at screen centre once
            // `container` carries the offset `update` just computed.
            let focusScreenPoint = IsometricProjection.tileToScreen(focus)
            let convertedCentre = container.convert(focusScreenPoint, to: parent)

            XCTAssertEqual(
                convertedCentre.x, expectedCentre.x, accuracy: tolerance,
                "focus \(focus) at @\(deviceScale)x", file: file, line: line
            )
            XCTAssertEqual(
                convertedCentre.y, expectedCentre.y, accuracy: tolerance,
                "focus \(focus) at @\(deviceScale)x", file: file, line: line
            )
        }
    }

    // MARK: - The container offset itself lands on the device pixel grid

    /// The reason the centring tolerance exists at all: this is the one line
    /// in the codebase that moves a world container every frame, so a
    /// fractional offset here re-blurs every world-space child
    /// (`docs/bootstrap.md` section 1's "hard, un-resampled pixel edges";
    /// AGENT.md assigns the camera snap to `CYBERPUN-17-7`). Asserted on the
    /// container's own position, at each device scale, for a focus sweep
    /// whose raw projected offsets are emphatically not whole pixels.
    func test_update_snapsTheContainerOffset_ontoTheDevicePixelGrid() {
        for deviceScale in [CGFloat(1), 2, 3] {
            let container = SKNode()
            let controller = CameraController(
                container: container,
                deviceScale: { deviceScale },
                streamingUpdate: { _ in }
            )

            for focus in stride(from: -13.0, through: 13.0, by: 1.7).map({ TilePoint(x: $0, y: $0 * 0.37) }) {
                controller.update(focus: focus, viewportSize: portraitViewport)

                // Compared with `spriteKitStorageEpsilon` slack, not
                // exactly: the value read back has been through SKNode's
                // 32-bit float storage. Still far tighter than the
                // fractional offsets an unsnapped assignment produces
                // (those miss the grid by up to half a device pixel).
                let devicePixelsX = container.position.x * deviceScale
                let devicePixelsY = container.position.y * deviceScale
                XCTAssertEqual(
                    devicePixelsX, devicePixelsX.rounded(), accuracy: spriteKitStorageEpsilon,
                    "focus \(focus) at @\(deviceScale)x: container.position.x is off the device pixel grid"
                )
                XCTAssertEqual(
                    devicePixelsY, devicePixelsY.rounded(), accuracy: spriteKitStorageEpsilon,
                    "focus \(focus) at @\(deviceScale)x: container.position.y is off the device pixel grid"
                )
            }
        }
    }

    /// The default `deviceScale` a headless (view-less) scene or a test
    /// gets is `1`, which snaps to a whole *point* -- coarser than a real
    /// device's grid, still on it. Pinned so the fallback cannot silently
    /// become "unsnapped".
    func test_update_withTheHeadlessDefaultScale_snapsToAWholePoint() {
        let container = SKNode()
        let controller = CameraController(container: container, streamingUpdate: { _ in })

        controller.update(focus: TilePoint(x: 3.31, y: -7.77), viewportSize: portraitViewport)

        XCTAssertEqual(container.position.x, container.position.x.rounded(), accuracy: 1e-9)
        XCTAssertEqual(container.position.y, container.position.y.rounded(), accuracy: 1e-9)
    }

    // MARK: - The streaming trigger is driven with the live focus point

    func test_update_forwardsTheLiveFocusPoint_toTheStreamingTrigger() {
        let container = SKNode()
        var receivedFocusPoints: [TilePoint] = []

        let controller = CameraController(container: container) { focus in
            receivedFocusPoints.append(focus)
        }

        let focusOne = TilePoint(x: 3, y: -2)
        let focusTwo = TilePoint(x: 10, y: 4)
        controller.update(focus: focusOne, viewportSize: portraitViewport)
        controller.update(focus: focusTwo, viewportSize: portraitViewport)

        XCTAssertEqual(receivedFocusPoints, [focusOne, focusTwo])
    }

    // MARK: - Streaming is (re)triggered as focus crosses chunk boundaries

    /// Wires the controller straight to a real `ChunkStreamingManager` \u2014
    /// the same "existing chunk-streaming trigger" `GroundPlaneStreamer`
    /// drives in production \u2014 and proves `update` is what actually calls
    /// it, not merely something that could be called: the origin chunk
    /// streams out and a distant destination chunk streams in only because
    /// each `update` call forwarded that call's own live focus point.
    func test_update_reTriggersChunkStreaming_asFocusCrossesChunkBoundaries() {
        let container = SKNode()
        let manager = ChunkStreamingManager(seed: WorldSeed(rawValue: 4_040))
        let controller = CameraController(container: container) { focus in
            manager.updateCamera(worldPosition: focus)
        }

        let origin = TilePoint(x: 0, y: 0)
        controller.update(focus: origin, viewportSize: portraitViewport)
        let originChunk = ChunkStreamingManager.chunkCoordinate(containing: origin)
        XCTAssertTrue(manager.residentChunks.keys.contains(originChunk), "precondition: origin chunk resident")

        // Many chunk-widths away (`ChunkStreamingManager.residentRadius` is
        // 3, i.e. an 8-tile-per-chunk window), so the origin chunk must have
        // streamed out and the destination chunk must have streamed in.
        let farFocus = TilePoint(x: 400, y: 0)
        controller.update(focus: farFocus, viewportSize: portraitViewport)
        let farChunk = ChunkStreamingManager.chunkCoordinate(containing: farFocus)

        XCTAssertTrue(manager.residentChunks.keys.contains(farChunk), "the destination chunk must stream in")
        XCTAssertFalse(manager.residentChunks.keys.contains(originChunk), "the origin chunk must stream out")
    }

    // MARK: - A rotation mid-run is honoured on the very next call

    func test_update_reflectsANewViewportSize_onTheVeryNextCall() {
        let parent = SKNode()
        let container = SKNode()
        parent.addChild(container)
        let controller = CameraController(container: container, streamingUpdate: { _ in })
        let focus = TilePoint(x: 5, y: -3)
        let focusScreenPoint = IsometricProjection.tileToScreen(focus)

        let tolerance = centringTolerance(deviceScale: 1)

        controller.update(focus: focus, viewportSize: portraitViewport)
        let portraitCentre = container.convert(focusScreenPoint, to: parent)
        XCTAssertEqual(portraitCentre.x, portraitViewport.width / 2, accuracy: tolerance)
        XCTAssertEqual(portraitCentre.y, portraitViewport.height / 2, accuracy: tolerance)

        controller.update(focus: focus, viewportSize: landscapeViewport)
        let landscapeCentre = container.convert(focusScreenPoint, to: parent)
        XCTAssertEqual(landscapeCentre.x, landscapeViewport.width / 2, accuracy: tolerance)
        XCTAssertEqual(landscapeCentre.y, landscapeViewport.height / 2, accuracy: tolerance)
    }

    // MARK: - A deallocated container is handled gracefully

    /// `container` is held weakly (the scene, not this controller, owns
    /// node lifetime), so a torn-down container must never crash `update` \u2014
    /// and the streaming trigger, which owes nothing to the container's
    /// lifetime, must still fire.
    func test_update_withADeallocatedContainer_doesNotCrash_andStillDrivesStreaming() {
        var receivedFocusPoints: [TilePoint] = []
        var container: SKNode? = SKNode()
        let controller = CameraController(container: container!) { focus in
            receivedFocusPoints.append(focus)
        }
        container = nil

        controller.update(focus: TilePoint(x: 1, y: 1), viewportSize: portraitViewport)

        XCTAssertEqual(receivedFocusPoints, [TilePoint(x: 1, y: 1)])
    }
}
