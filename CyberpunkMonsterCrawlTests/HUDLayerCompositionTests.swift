import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-23-t3`: defensive regression coverage for finding 1 in that
/// task's plan (the reported "radar overlapping the timer/kill-count row").
///
/// `HUDLayoutTests` already pins `HUDLayout.frame(for: .radarMap, ...)`
/// sitting strictly below `HUDLayout.frame(for: .killCount, ...)` as a pure
/// function of `(sceneSize, safeAreaInsets)` -- and that pure function could
/// not be made to reproduce an overlap by re-reading it, so this is *not* a
/// bug fix. What every existing HUD layout test leaves untested is whether
/// the **mounted** `HUDLayer` nodes actually land where that pure function
/// says: `HUDLayer.applyLayout(...)` is a separate piece of code
/// (`position(_:at:sceneSize:safeAreaInsets:)`) that could, in principle,
/// drift out of step with `HUDLayout` itself (a transient/ordering bug, a
/// stale cached frame, a future refactor that reads the wrong slot) with
/// nothing here to catch it. This file mounts the real `HUDLayer`, calls
/// `applyLayout(...)`, and checks the two *mounted* nodes' own real frames
/// against each other -- closing exactly that gap.
///
/// **Measured, not re-derived** (PR #80 review). An earlier version of this
/// file rebuilt each frame as `mounted .position` +/- half the same size
/// constant `HUDLayout.frame(for:)` already uses, which could only ever pin
/// "did `applyLayout` put the node at the right slot's midpoint" -- it was
/// blind to the drift class the paragraph above names, a node whose *drawn*
/// extent differs from its declared size constant. Two such cases are live
/// here: `RadarMapNode.border` is an `SKShapeNode` stroked on a 112x112
/// rect with `lineWidth: 1`, and SpriteKit centres a stroke on its path, so
/// the real extent is ~113x113 -- half a point past `outerSize` on each
/// edge; and `KillCountLabel`'s real text extent is a glyph box, not
/// `HUDLayout.killCountSize`. `calculateAccumulatedFrame()` measures what
/// is actually drawn, and both nodes are direct children of `HUDLayer`, so
/// the two rects it returns are already in the same (parent) space and are
/// directly comparable. Neither case is a live overlap today -- the 8pt
/// `HUDLayout.verticalSpacing` absorbs both -- so this is about the file
/// asserting what its header claims: "the pixels don't touch", not merely
/// "the slot math was applied".
final class HUDLayerCompositionTests: XCTestCase {

    private let portraitSize = CGSize(width: 390, height: 844)
    private let portraitInsets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    private let landscapeSize = CGSize(width: 844, height: 390)
    private let landscapeInsets = UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)

    /// A mounted node's real drawn extent, in its parent `HUDLayer`'s own
    /// coordinate space -- `SKNode.calculateAccumulatedFrame()` covers the
    /// node and every descendant (the radar's stroked border, the kill
    /// count's `SKLabelNode` glyphs) and reports it in parent space, which
    /// is the space both of these nodes are positioned in.
    private func drawnFrame(of node: SKNode) -> CGRect {
        node.calculateAccumulatedFrame()
    }

    /// Guards against this file passing vacuously: an empty or null rect
    /// would satisfy every ordering assertion below without measuring
    /// anything.
    private func assertHasRealExtent(_ frame: CGRect, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(frame.isNull, "\(label) must have a real measured frame", file: file, line: line)
        XCTAssertGreaterThan(frame.width, 0, "\(label) must have a non-empty drawn width", file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, "\(label) must have a non-empty drawn height", file: file, line: line)
    }

    func test_appliedLayout_mountsRadarMapStrictlyBelowKillCount_inPortrait_withAPositiveGap() {
        let hud = HUDLayer()
        hud.applyLayout(for: portraitSize, safeAreaInsets: portraitInsets, orientation: .portrait)

        let killCountFrame = drawnFrame(of: hud.killCount)
        let radarMapFrame = drawnFrame(of: hud.radarMap)
        assertHasRealExtent(killCountFrame, "the mounted kill count")
        assertHasRealExtent(radarMapFrame, "the mounted radar")

        XCTAssertLessThan(
            radarMapFrame.maxY, killCountFrame.minY,
            "the mounted radar's drawn top edge must sit strictly below the mounted kill count's drawn "
                + "bottom edge, not merely avoid dead centre overlap -- radar \(radarMapFrame), "
                + "kill count \(killCountFrame)"
        )
        XCTAssertFalse(
            radarMapFrame.intersects(killCountFrame),
            "the two mounted nodes' drawn extents must not overlap at all"
        )
        XCTAssertGreaterThan(
            killCountFrame.minY - radarMapFrame.maxY, 0,
            "there must be a real, positive gap between the two mounted nodes' drawn extents"
        )
    }

    func test_appliedLayout_mountsRadarMapStrictlyBelowKillCount_inLandscape_withAPositiveGap() {
        let hud = HUDLayer()
        hud.applyLayout(for: landscapeSize, safeAreaInsets: landscapeInsets, orientation: .landscape)

        let killCountFrame = drawnFrame(of: hud.killCount)
        let radarMapFrame = drawnFrame(of: hud.radarMap)
        assertHasRealExtent(killCountFrame, "the mounted kill count")
        assertHasRealExtent(radarMapFrame, "the mounted radar")

        XCTAssertLessThan(
            radarMapFrame.maxY, killCountFrame.minY,
            "radar \(radarMapFrame) must sit strictly below kill count \(killCountFrame) in landscape too"
        )
        XCTAssertFalse(radarMapFrame.intersects(killCountFrame))
        XCTAssertGreaterThan(killCountFrame.minY - radarMapFrame.maxY, 0)
    }

    /// A **rotation round trip** -- portrait, then landscape, then back to
    /// portrait -- must land the two nodes exactly where the first portrait
    /// pass did.
    ///
    /// Deliberately not a second `applyLayout(...)` call with the *same*
    /// geometry (PR #80 review: that version was close to tautological,
    /// since `applyLayout` is a pure recompute with nothing cached, so only
    /// a mutation bug no other assertion here models could have failed it).
    /// Going through a *different* layout in between is the real scenario
    /// the file's header names -- a rotation leaving stale state behind --
    /// and it also exercises `applyLayout`'s own non-position side effect,
    /// `radarMap.radarScale`, which genuinely does change with `sceneSize`
    /// and must come back to its portrait value.
    func test_rotatingAwayAndBack_restoresTheSameMountedGeometry() {
        let hud = HUDLayer()

        hud.applyLayout(for: portraitSize, safeAreaInsets: portraitInsets, orientation: .portrait)
        let firstRadar = drawnFrame(of: hud.radarMap)
        let firstKillCount = drawnFrame(of: hud.killCount)
        let firstScale = hud.radarMap.radarScale
        let firstGap = firstKillCount.minY - firstRadar.maxY
        assertHasRealExtent(firstRadar, "the mounted radar")
        assertHasRealExtent(firstKillCount, "the mounted kill count")
        XCTAssertGreaterThan(firstGap, 0)

        hud.applyLayout(for: landscapeSize, safeAreaInsets: landscapeInsets, orientation: .landscape)
        XCTAssertGreaterThan(
            drawnFrame(of: hud.killCount).minY - drawnFrame(of: hud.radarMap).maxY, 0,
            "the gap must stay positive in the intermediate landscape pass too"
        )

        hud.applyLayout(for: portraitSize, safeAreaInsets: portraitInsets, orientation: .portrait)
        let secondRadar = drawnFrame(of: hud.radarMap)
        let secondKillCount = drawnFrame(of: hud.killCount)

        XCTAssertEqual(secondRadar.midX, firstRadar.midX, accuracy: 1e-6)
        XCTAssertEqual(secondRadar.midY, firstRadar.midY, accuracy: 1e-6)
        XCTAssertEqual(secondKillCount.midX, firstKillCount.midX, accuracy: 1e-6)
        XCTAssertEqual(secondKillCount.midY, firstKillCount.midY, accuracy: 1e-6)
        XCTAssertEqual(
            hud.radarMap.radarScale, firstScale, accuracy: 1e-6,
            "the radar's points-per-tile scale must come back to its portrait value after a rotation round trip"
        )

        let secondGap = secondKillCount.minY - secondRadar.maxY
        XCTAssertEqual(secondGap, firstGap, accuracy: 1e-6)
        XCTAssertGreaterThan(secondGap, 0)
    }
}
