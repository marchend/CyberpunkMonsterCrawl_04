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
final class HUDLayerCompositionTests: XCTestCase {

    private let portraitSize = CGSize(width: 390, height: 844)
    private let portraitInsets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    private let landscapeSize = CGSize(width: 844, height: 390)
    private let landscapeInsets = UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)

    /// A node's real, on-screen frame: every HUD element is anchored at its
    /// slot frame's centre (`HUDLayer.position(_:at:sceneSize:safeAreaInsets:)`),
    /// so its mounted `.position` plus its own fixed drawn size recovers the
    /// same rect `HUDLayout.frame(for:...)` computed for that slot.
    private func mountedFrame(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func test_appliedLayout_mountsRadarMapStrictlyBelowKillCount_inPortrait_withAPositiveGap() {
        let hud = HUDLayer()
        hud.applyLayout(for: portraitSize, safeAreaInsets: portraitInsets, orientation: .portrait)

        let killCountFrame = mountedFrame(center: hud.killCount.position, size: HUDLayout.killCountSize)
        let radarMapFrame = mountedFrame(center: hud.radarMap.position, size: RadarMapNode.outerSize)

        XCTAssertLessThan(
            radarMapFrame.maxY, killCountFrame.minY,
            "the mounted radar's top edge must sit strictly below the mounted kill count's bottom edge, "
                + "not merely avoid dead centre overlap -- radar \(radarMapFrame), kill count \(killCountFrame)"
        )
        XCTAssertGreaterThan(
            killCountFrame.minY - radarMapFrame.maxY, 0,
            "there must be a real, positive gap between the two mounted nodes"
        )
    }

    func test_appliedLayout_mountsRadarMapStrictlyBelowKillCount_inLandscape_withAPositiveGap() {
        let hud = HUDLayer()
        hud.applyLayout(for: landscapeSize, safeAreaInsets: landscapeInsets, orientation: .landscape)

        let killCountFrame = mountedFrame(center: hud.killCount.position, size: HUDLayout.killCountSize)
        let radarMapFrame = mountedFrame(center: hud.radarMap.position, size: RadarMapNode.outerSize)

        XCTAssertLessThan(
            radarMapFrame.maxY, killCountFrame.minY,
            "radar \(radarMapFrame) must sit strictly below kill count \(killCountFrame) in landscape too"
        )
        XCTAssertGreaterThan(killCountFrame.minY - radarMapFrame.maxY, 0)
    }

    /// A rebind/relayout mid-run (a rotation, or a second `applyLayout(...)`
    /// call with the same geometry) must not leave the two nodes' relative
    /// placement any different -- the mounted frames are recomputed from
    /// scratch each call, with nothing cached from a previous pass that
    /// could drift.
    func test_reapplyingTheSameLayout_leavesTheGapUnchanged() {
        let hud = HUDLayer()
        hud.applyLayout(for: portraitSize, safeAreaInsets: portraitInsets, orientation: .portrait)
        let firstGap = mountedFrame(center: hud.killCount.position, size: HUDLayout.killCountSize).minY
            - mountedFrame(center: hud.radarMap.position, size: RadarMapNode.outerSize).maxY

        hud.applyLayout(for: portraitSize, safeAreaInsets: portraitInsets, orientation: .portrait)
        let secondGap = mountedFrame(center: hud.killCount.position, size: HUDLayout.killCountSize).minY
            - mountedFrame(center: hud.radarMap.position, size: RadarMapNode.outerSize).maxY

        XCTAssertEqual(firstGap, secondGap, accuracy: 1e-6)
        XCTAssertGreaterThan(secondGap, 0)
    }
}
