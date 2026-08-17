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

    // MARK: - The focus point always converts to screen centre

    func test_update_keepsAMovingFocusPoint_convertingToScreenCentre_inPortrait() {
        assertFocusConvertsToScreenCentre(viewportSize: portraitViewport)
    }

    func test_update_keepsAMovingFocusPoint_convertingToScreenCentre_inLandscape() {
        assertFocusConvertsToScreenCentre(viewportSize: landscapeViewport)
    }

    private func assertFocusConvertsToScreenCentre(
        viewportSize: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let parent = SKNode()
        let container = SKNode()
        parent.addChild(container)

        let controller = CameraController(container: container, streamingUpdate: { _ in })
        let expectedCentre = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)

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
                convertedCentre.x, expectedCentre.x, accuracy: 1e-3,
                "focus \(focus)", file: file, line: line
            )
            XCTAssertEqual(
                convertedCentre.y, expectedCentre.y, accuracy: 1e-3,
                "focus \(focus)", file: file, line: line
            )
        }
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

        controller.update(focus: focus, viewportSize: portraitViewport)
        let portraitCentre = container.convert(focusScreenPoint, to: parent)
        XCTAssertEqual(portraitCentre.x, portraitViewport.width / 2, accuracy: 1e-3)
        XCTAssertEqual(portraitCentre.y, portraitViewport.height / 2, accuracy: 1e-3)

        controller.update(focus: focus, viewportSize: landscapeViewport)
        let landscapeCentre = container.convert(focusScreenPoint, to: parent)
        XCTAssertEqual(landscapeCentre.x, landscapeViewport.width / 2, accuracy: 1e-3)
        XCTAssertEqual(landscapeCentre.y, landscapeViewport.height / 2, accuracy: 1e-3)
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
