import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 1: per-element `update(...)` behavior for every
/// passive HUD node (`HPSegmentBar`, `LevelXPBar`, `RunTimerLabel`,
/// `KillCountLabel`), `HUDPulseButton`'s cooldown *rendering* (its
/// press-suppression + hit-test coordinate agreement live in
/// `PulseButtonHitTestTests`), and `SwarmBanner`'s show/dismiss/auto-dismiss
/// contract.
///
/// SpriteKit-backed `CGFloat`/`CGSize` quantities (`SKSpriteNode.size`,
/// `SKShapeNode.path` geometry, `alpha`) are compared with `accuracy:`,
/// sized to magnitude, per this project's float-comparison convention
/// (see `PixelCrispnessTests`) -- never with exact equality.
final class HUDElementUpdateTests: XCTestCase {

    // MARK: - HPSegmentBar

    private func segment(_ index: Int, of bar: HPSegmentBar) throws -> SKSpriteNode {
        try XCTUnwrap(
            bar.childNode(withName: "hpSegmentBar.segment.\(index)") as? SKSpriteNode,
            "segment \(index) is missing"
        )
    }

    func test_hpSegmentBar_fullHP_lightsEverySegment() {
        let bar = HPSegmentBar()

        bar.update(currentHP: 100, maxHP: 100)

        XCTAssertEqual(bar.filledSegments, HPSegmentBar.segmentCount)
    }

    func test_hpSegmentBar_zeroHP_lightsNoSegment() {
        let bar = HPSegmentBar()

        bar.update(currentHP: 0, maxHP: 100)

        XCTAssertEqual(bar.filledSegments, 0)
    }

    func test_hpSegmentBar_partialHP_lightsTheProportionalSegmentCount() {
        let bar = HPSegmentBar()

        bar.update(currentHP: 3, maxHP: 10)

        XCTAssertEqual(bar.filledSegments, 3)
    }

    func test_hpSegmentBar_clampsNegativeHP_toZero() {
        let bar = HPSegmentBar()

        bar.update(currentHP: -5, maxHP: 100)

        XCTAssertEqual(bar.currentHP, 0)
        XCTAssertEqual(bar.filledSegments, 0)
    }

    func test_hpSegmentBar_clampsHPAboveMax_toMax() {
        let bar = HPSegmentBar()

        bar.update(currentHP: 150, maxHP: 100)

        XCTAssertEqual(bar.currentHP, 100)
        XCTAssertEqual(bar.filledSegments, HPSegmentBar.segmentCount)
    }

    func test_hpSegmentBar_clampsNonPositiveMaxHP_toOne() {
        let bar = HPSegmentBar()

        bar.update(currentHP: 5, maxHP: 0)

        XCTAssertEqual(bar.maxHP, 1)
        XCTAssertEqual(bar.currentHP, 1)
        XCTAssertEqual(bar.filledSegments, HPSegmentBar.segmentCount)
    }

    /// Colors are compared component-wise (never via `XCTAssertEqual` on the
    /// `UIColor`s themselves, which can fail across representationally-equal
    /// but differently-tagged color spaces -- see this project's
    /// float-comparison convention).
    private func assertColorsMatch(
        _ a: UIColor,
        _ b: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var rA: CGFloat = 0, gA: CGFloat = 0, bA: CGFloat = 0, aA: CGFloat = 0
        var rB: CGFloat = 0, gB: CGFloat = 0, bB: CGFloat = 0, aB: CGFloat = 0
        a.getRed(&rA, green: &gA, blue: &bA, alpha: &aA)
        b.getRed(&rB, green: &gB, blue: &bB, alpha: &aB)
        XCTAssertEqual(rA, rB, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(gA, gB, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(bA, bB, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(aA, aB, accuracy: 1e-3, file: file, line: line)
    }

    func test_hpSegmentBar_segmentColors_reflectFilledCount() throws {
        let bar = HPSegmentBar()

        bar.update(currentHP: 3, maxHP: 10)

        for index in 0..<HPSegmentBar.segmentCount {
            let seg = try segment(index, of: bar)
            let expected = index < 3 ? PixelGritPalette.neonAccent : HPSegmentBar.emptySegmentColor
            assertColorsMatch(seg.color, expected)
        }
    }

    // MARK: - LevelXPBar

    private func fillNode(of bar: LevelXPBar) throws -> SKSpriteNode {
        try XCTUnwrap(bar.childNode(withName: "levelXPBar.fill") as? SKSpriteNode)
    }

    func test_levelXPBar_zeroXP_producesAnEmptyFill() throws {
        let bar = LevelXPBar()

        bar.update(level: 1, currentXP: 0, xpForNextLevel: 100)

        XCTAssertEqual(bar.xpFraction, 0, accuracy: 1e-6)
        let fill = try fillNode(of: bar)
        XCTAssertEqual(fill.size.width, 0, accuracy: 1e-3)
    }

    func test_levelXPBar_halfXP_producesAHalfWidthFill() throws {
        let bar = LevelXPBar()

        bar.update(level: 1, currentXP: 50, xpForNextLevel: 100)

        XCTAssertEqual(bar.xpFraction, 0.5, accuracy: 1e-6)
        let fill = try fillNode(of: bar)
        XCTAssertEqual(fill.size.width, LevelXPBar.barSize.width * 0.5, accuracy: 1e-3)
    }

    func test_levelXPBar_levelUp_resetsTheFillBackToEmpty() throws {
        let bar = LevelXPBar()
        bar.update(level: 1, currentXP: 90, xpForNextLevel: 100)

        bar.update(level: 2, currentXP: 0, xpForNextLevel: 150)

        XCTAssertEqual(bar.level, 2)
        XCTAssertEqual(bar.xpFraction, 0, accuracy: 1e-6)
        let fill = try fillNode(of: bar)
        XCTAssertEqual(fill.size.width, 0, accuracy: 1e-3)
    }

    func test_levelXPBar_clampsCurrentXPAboveTarget_toFull() {
        let bar = LevelXPBar()

        bar.update(level: 1, currentXP: 999, xpForNextLevel: 100)

        XCTAssertEqual(bar.currentXP, 100)
        XCTAssertEqual(bar.xpFraction, 1.0, accuracy: 1e-6)
    }

    func test_levelXPBar_clampsNegativeCurrentXP_toZero() {
        let bar = LevelXPBar()

        bar.update(level: 1, currentXP: -10, xpForNextLevel: 100)

        XCTAssertEqual(bar.currentXP, 0)
        XCTAssertEqual(bar.xpFraction, 0, accuracy: 1e-6)
    }

    func test_levelXPBar_clampsNonPositiveTarget_toOne() {
        let bar = LevelXPBar()

        bar.update(level: 1, currentXP: 5, xpForNextLevel: 0)

        XCTAssertEqual(bar.xpForNextLevel, 1)
        XCTAssertEqual(bar.currentXP, 1)
        XCTAssertEqual(bar.xpFraction, 1.0, accuracy: 1e-6)
    }

    // MARK: - RunTimerLabel

    func test_runTimerLabel_formatsZeroSeconds() {
        XCTAssertEqual(RunTimerLabel.formattedText(forElapsedSeconds: 0), "00:00")
    }

    func test_runTimerLabel_formatsMinutesAndSeconds() {
        XCTAssertEqual(RunTimerLabel.formattedText(forElapsedSeconds: 65), "01:05")
    }

    func test_runTimerLabel_doesNotCapMinutesAtFiftyNine() {
        XCTAssertEqual(RunTimerLabel.formattedText(forElapsedSeconds: 3661), "61:01")
    }

    func test_runTimerLabel_flooresFractionalSeconds() {
        let label = RunTimerLabel()

        label.update(elapsedSeconds: 65.9)

        XCTAssertEqual(label.formattedText, "01:05")
    }

    func test_runTimerLabel_clampsNegativeElapsedSeconds_toZero() {
        let label = RunTimerLabel()

        label.update(elapsedSeconds: -5)

        XCTAssertEqual(label.elapsedSeconds, 0, accuracy: 1e-6)
        XCTAssertEqual(label.formattedText, "00:00")
    }

    // MARK: - KillCountLabel

    func test_killCountLabel_startsAtZero() {
        let label = KillCountLabel()

        XCTAssertEqual(label.kills, 0)
        XCTAssertEqual(label.formattedText, "KILLS 0")
    }

    func test_killCountLabel_incrementsAcrossSuccessiveUpdates() {
        let label = KillCountLabel()

        label.update(kills: 5)
        XCTAssertEqual(label.formattedText, "KILLS 5")

        label.update(kills: 6)
        XCTAssertEqual(label.kills, 6)
        XCTAssertEqual(label.formattedText, "KILLS 6")
    }

    func test_killCountLabel_clampsNegativeKills_toZero() {
        let label = KillCountLabel()

        label.update(kills: -3)

        XCTAssertEqual(label.kills, 0)
        XCTAssertEqual(label.formattedText, "KILLS 0")
    }

    // MARK: - HUDPulseButton cooldown rendering

    private func cooldownOverlay(of button: HUDPulseButton) throws -> SKShapeNode {
        try XCTUnwrap(button.childNode(withName: "hudPulseButton.cooldownOverlay") as? SKShapeNode)
    }

    func test_hudPulseButton_freshButton_startsReadyWithNoOverlay() throws {
        let button = HUDPulseButton(onPress: {})

        XCTAssertTrue(button.isReady)
        XCTAssertEqual(button.cooldownFraction, 1.0, accuracy: 1e-6)
        XCTAssertEqual(button.alpha, HUDPulseButton.readyAlpha, accuracy: 1e-6)

        let overlay = try cooldownOverlay(of: button)
        XCTAssertTrue(overlay.isHidden)
    }

    func test_hudPulseButton_justTriggered_coversTheWholeCircleAndDimsAlpha() throws {
        let button = HUDPulseButton(onPress: {})

        button.update(cooldownFraction: 0, isReady: false)

        XCTAssertEqual(button.alpha, HUDPulseButton.cooldownAlpha, accuracy: 1e-6)
        let overlay = try cooldownOverlay(of: button)
        XCTAssertFalse(overlay.isHidden)
        let path = try XCTUnwrap(overlay.path)
        let box = path.boundingBox
        XCTAssertEqual(box.width, HUDPulseButton.size.width, accuracy: 1e-3)
        XCTAssertEqual(box.height, HUDPulseButton.size.height, accuracy: 1e-3)
    }

    func test_hudPulseButton_wedgeShrinks_asCooldownFractionRises() throws {
        let button = HUDPulseButton(onPress: {})

        button.update(cooldownFraction: 0.25, isReady: false)
        let earlyBox = try XCTUnwrap(cooldownOverlay(of: button).path).boundingBox

        button.update(cooldownFraction: 0.75, isReady: false)
        let lateBox = try XCTUnwrap(cooldownOverlay(of: button).path).boundingBox

        XCTAssertLessThan(
            lateBox.width * lateBox.height,
            earlyBox.width * earlyBox.height,
            "the remaining wedge must shrink as cooldownFraction rises"
        )
    }

    func test_hudPulseButton_readyAtFullFraction_hidesTheOverlayAndRestoresAlpha() throws {
        let button = HUDPulseButton(onPress: {})
        button.update(cooldownFraction: 0, isReady: false)

        button.update(cooldownFraction: 1.0, isReady: true)

        XCTAssertEqual(button.alpha, HUDPulseButton.readyAlpha, accuracy: 1e-6)
        let overlay = try cooldownOverlay(of: button)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertNil(overlay.path)
    }

    func test_hudPulseButton_clampsOutOfRangeCooldownFraction() {
        let button = HUDPulseButton(onPress: {})

        button.update(cooldownFraction: -0.5, isReady: false)
        XCTAssertEqual(button.cooldownFraction, 0, accuracy: 1e-6)

        button.update(cooldownFraction: 1.5, isReady: true)
        XCTAssertEqual(button.cooldownFraction, 1.0, accuracy: 1e-6)
    }

    // MARK: - SwarmBanner

    func test_swarmBanner_startsHiddenAndNotShowing() {
        let banner = SwarmBanner()

        XCTAssertFalse(banner.isShowing)
        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(banner.alpha, 0, accuracy: 1e-6)
        XCTAssertNil(banner.currentMessage)
    }

    /// Never intercepts touches -- a stated invariant of this node (see its
    /// own doc comment), checked in both the hidden and the visible state.
    func test_swarmBanner_neverInterceptsTouches() {
        let banner = SwarmBanner()
        XCTAssertFalse(banner.isUserInteractionEnabled)

        banner.show(message: "SWARM INCOMING", duration: 5)
        XCTAssertFalse(banner.isUserInteractionEnabled)
    }

    func test_swarmBanner_show_displaysTheMessageAndSchedulesAutoDismiss() {
        let banner = SwarmBanner()

        banner.show(message: "SWARM INCOMING", duration: 3)

        XCTAssertTrue(banner.isShowing)
        XCTAssertFalse(banner.isHidden)
        XCTAssertEqual(banner.alpha, 1, accuracy: 1e-6)
        XCTAssertEqual(banner.currentMessage, "SWARM INCOMING")

        let scheduled = banner.pendingAutoDismissAction
        XCTAssertNotNil(scheduled, "show(...) must schedule an auto-dismiss action")
        XCTAssertEqual(scheduled?.duration ?? -1, 3, accuracy: 1e-6)
    }

    func test_swarmBanner_dismiss_hidesTheBannerAndCancelsTheScheduledAutoDismiss() {
        let banner = SwarmBanner()
        banner.show(message: "SWARM INCOMING", duration: 5)

        banner.dismiss()

        XCTAssertFalse(banner.isShowing)
        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(banner.alpha, 0, accuracy: 1e-6)
        XCTAssertNil(banner.currentMessage)
        XCTAssertNil(banner.pendingAutoDismissAction, "dismiss() must cancel any pending auto-dismiss")
    }

    /// A second `show(...)` call must replace (never stack with) an
    /// already-pending dismissal -- otherwise an earlier, shorter-duration
    /// dismissal could still fire and hide a banner that was just re-shown
    /// with a longer duration.
    func test_swarmBanner_show_calledAgainWhilePending_replacesThePreviousSchedule() {
        let banner = SwarmBanner()
        banner.show(message: "FIRST", duration: 1)

        banner.show(message: "SECOND", duration: 10)

        XCTAssertEqual(banner.currentMessage, "SECOND")
        XCTAssertEqual(banner.pendingAutoDismissAction?.duration ?? -1, 10, accuracy: 1e-6)
    }
}
