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

    /// The **tightest supported** landscape geometry, and the reason it is
    /// in this table rather than left to the roomier 844x390 pair above:
    /// a 375pt-tall landscape carrying the same 21pt home-indicator inset
    /// (iPhone X/XS/11 Pro and 12/13 mini -- 812x375, all shipping iOS 17,
    /// this project's deployment target). The top stack's landscape
    /// constraint is `H >= 364 + top + bottom`, i.e. 385pt here, so this
    /// device class is 10pt short: `CYBERPUN-17-12` PR 2's first cut hung
    /// the swarm banner ~10pt inside `thumbstickReservedRegion` on it while
    /// every gate below stayed green, purely because both orientations in
    /// this suite were hardcoded to 844x390. Every invariant in this file
    /// is now exercised at this geometry too.
    private let compactLandscapeSize = CGSize(width: 812, height: 375)
    private let compactLandscapeInsets = UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)

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

    func test_allSixSlots_stayInsideTheSafeArea_inTheTightestSupportedLandscape() {
        assertAllSlotsInsideSafeArea(sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets)
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

    func test_pulseButtonSlot_isBottomRight_inTheTightestSupportedLandscape() {
        assertPulseButtonIsBottomRight(sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets)
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

    /// The invariant the hand-tuned banner height broke: at 812x375 the
    /// top stack does not fit above the stick's region, so the banner has
    /// to be *lifted* clear of it (see `HUDLayout.frame(for:sceneSize:
    /// safeAreaInsets:)`'s `.swarmBanner` case) rather than trusting a
    /// height that only fits one device's insets.
    func test_noSlot_overlapsTheThumbstickRegion_inTheTightestSupportedLandscape() {
        assertNoSlotOverlapsTheThumbstickRegion(
            sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets
        )
    }

    /// ... and the lift is not free: it moves the banner *towards* the two
    /// top columns, so the geometry that triggers it is exactly the one
    /// where "clear of the stick" and "disjoint from every sibling" have to
    /// hold at the same time. Pinned as its own case so a future retune of
    /// any element's size cannot quietly consume the gap the lift needs.
    func test_theLiftedBanner_staysClearOfBothTheStickAndTheColumns_inTheTightestSupportedLandscape() {
        let banner = HUDLayout.frame(
            for: .swarmBanner, sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets
        )
        let reserved = HUDLayout.thumbstickReservedRegion(
            sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets
        )
        let levelXPBar = HUDLayout.frame(
            for: .levelXPBar, sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets
        )

        XCTAssertGreaterThanOrEqual(
            banner.minY, reserved.maxY,
            "the banner \(banner) must sit at or above the stick's region \(reserved) on this geometry"
        )
        XCTAssertLessThanOrEqual(
            banner.maxY, levelXPBar.minY,
            "lifting the banner \(banner) must not push it into the left column \(levelXPBar)"
        )
    }

    // MARK: - No two slots overlap each other

    /// `CYBERPUN-17-12` PR 2 found this the hard way: PR 1's slots each sat
    /// inside the safe area and clear of the thumbstick, but three of them
    /// sat on top of *each other* in portrait -- a 220pt HP bar anchored at
    /// the left safe edge of a 390pt screen reaches +41, straight through a
    /// centred 120pt run timer (-60...60), which in turn overlapped the
    /// right-anchored kill count by a point, and the centred swarm banner
    /// ran through the level/XP bar. Every existing gate stayed green,
    /// because each only ever compared one slot against a *fixed* rect.
    /// This compares the slots against one another.
    private func assertNoTwoSlotsOverlap(
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let slots = HUDSlot.allCases
        for outer in slots.indices {
            for inner in slots.indices where inner > outer {
                let first = HUDLayout.frame(for: slots[outer], sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
                let second = HUDLayout.frame(for: slots[inner], sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
                XCTAssertFalse(
                    first.intersects(second),
                    "\(slots[outer]) frame \(first) overlaps \(slots[inner]) frame \(second)",
                    file: file,
                    line: line
                )
            }
        }
    }

    func test_noTwoSlots_overlapEachOther_inPortrait() {
        assertNoTwoSlotsOverlap(sceneSize: portraitSize, safeAreaInsets: portraitInsets)
    }

    func test_noTwoSlots_overlapEachOther_inLandscape() {
        assertNoTwoSlotsOverlap(sceneSize: landscapeSize, safeAreaInsets: landscapeInsets)
    }

    func test_noTwoSlots_overlapEachOther_inTheTightestSupportedLandscape() {
        assertNoTwoSlotsOverlap(sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets)
    }

    // MARK: - Stacking: HP sits directly above the level/XP bar

    func test_levelXPBar_sitsDirectlyBelowTheHPBar_withNoOverlap() {
        let hp = HUDLayout.frame(for: .hpBar, sceneSize: portraitSize, safeAreaInsets: portraitInsets)
        let xp = HUDLayout.frame(for: .levelXPBar, sceneSize: portraitSize, safeAreaInsets: portraitInsets)

        XCTAssertTrue(xp.maxY <= hp.minY + 1e-6, "\(xp) must sit at or below \(hp)")
        XCTAssertFalse(hp.intersects(xp))
    }
}
