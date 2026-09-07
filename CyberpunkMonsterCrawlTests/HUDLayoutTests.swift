import CoreGraphics
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 1: `HUDLayout` is a pure `(sceneSize,
/// safeAreaInsets) -> [HUDSlot: CGRect]` function -- these tests drive it
/// directly with representative safe-area insets (notch + home indicator)
/// in both a representative portrait and a representative landscape input,
/// with no `SKNode`/scene/view involved.
final class HUDLayoutTests: XCTestCase {

    /// iPhone-class notch + home-indicator portrait insets.
    private let portraitSize = CGSize(width: 390, height: 844)
    private let portraitInsets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    /// The same device rotated: the notch becomes a side inset, the home
    /// indicator inset stays at the bottom.
    private let landscapeSize = CGSize(width: 844, height: 390)
    private let landscapeInsets = UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)

    // MARK: - Every slot stays inside the safe area

    private func assertAllSlotsInsideSafeArea(
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let safeRect = HUDLayout.safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        for slot in HUDSlot.allCases {
            let frame = HUDLayout.frame(for: slot, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
            XCTAssertTrue(
                safeRect.contains(frame),
                "\(slot) frame \(frame) escapes the safe content rect \(safeRect)",
                file: file,
                line: line
            )
        }
    }

    func test_allSixSlots_stayInsideTheSafeArea_inPortrait() {
        assertAllSlotsInsideSafeArea(sceneSize: portraitSize, safeAreaInsets: portraitInsets)
    }

    func test_allSixSlots_stayInsideTheSafeArea_inLandscape() {
        assertAllSlotsInsideSafeArea(sceneSize: landscapeSize, safeAreaInsets: landscapeInsets)
    }

    // MARK: - Exactly six slots

    func test_allFrames_producesExactlySixSlots() {
        let frames = HUDLayout.allFrames(sceneSize: portraitSize, safeAreaInsets: portraitInsets)
        XCTAssertEqual(frames.count, 6)
        XCTAssertEqual(Set(frames.keys), Set(HUDSlot.allCases))
    }

    // MARK: - Pulse-button slot is bottom-right in both orientations

    private func assertPulseButtonIsBottomRight(
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let safeRect = HUDLayout.safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        let pulse = HUDLayout.frame(for: .pulseButton, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)

        // "Bottom": sits in the lower half of the safe area.
        XCTAssertLessThan(pulse.midY, safeRect.midY, file: file, line: line)
        // "Right": sits in the right half of the safe area.
        XCTAssertGreaterThan(pulse.midX, safeRect.midX, file: file, line: line)
    }

    func test_pulseButtonSlot_isBottomRight_inPortrait() {
        assertPulseButtonIsBottomRight(sceneSize: portraitSize, safeAreaInsets: portraitInsets)
    }

    func test_pulseButtonSlot_isBottomRight_inLandscape() {
        assertPulseButtonIsBottomRight(sceneSize: landscapeSize, safeAreaInsets: landscapeInsets)
    }

    // MARK: - No slot overlaps the thumbstick's reserved bottom-left region

    private func assertNoSlotOverlapsTheThumbstickRegion(
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let reserved = HUDLayout.thumbstickReservedRegion(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        for slot in HUDSlot.allCases {
            let frame = HUDLayout.frame(for: slot, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
            XCTAssertFalse(
                frame.intersects(reserved),
                "\(slot) frame \(frame) overlaps the thumbstick's reserved region \(reserved)",
                file: file,
                line: line
            )
        }
    }

    func test_noSlot_overlapsTheThumbstickRegion_inPortrait() {
        assertNoSlotOverlapsTheThumbstickRegion(sceneSize: portraitSize, safeAreaInsets: portraitInsets)
    }

    func test_noSlot_overlapsTheThumbstickRegion_inLandscape() {
        assertNoSlotOverlapsTheThumbstickRegion(sceneSize: landscapeSize, safeAreaInsets: landscapeInsets)
    }

    // MARK: - Stacking: HP sits directly above the level/XP bar

    func test_levelXPBar_sitsDirectlyBelowTheHPBar_withNoOverlap() {
        let hp = HUDLayout.frame(for: .hpBar, sceneSize: portraitSize, safeAreaInsets: portraitInsets)
        let xp = HUDLayout.frame(for: .levelXPBar, sceneSize: portraitSize, safeAreaInsets: portraitInsets)

        XCTAssertTrue(xp.maxY <= hp.minY + 1e-6, "\(xp) must sit at or below \(hp)")
        XCTAssertFalse(hp.intersects(xp))
    }
}
