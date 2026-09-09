import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 2: starting a run and rotating portrait -> landscape
/// -> portrait keeps every one of the six mounted `HUDLayer` elements fully
/// inside the safe content area, with nothing clipped, in both
/// orientations -- exercised against the *mounted, composed* layer (via a
/// real `GameScene`), not `HUDLayout`'s own pure geometry alone (which
/// `HUDLayoutTests` already pins for PR 1).
///
/// This lives in the unit-test target rather than in
/// `CyberpunkMonsterCrawlUITests` deliberately: the runtime probe's own step
/// vocabulary has no rotate verb (see `.mothership/journeys` and the
/// `CYBERPUN-17-13` note in AGENT.md), and an XCUITest rotation asserts only
/// what is visible through the accessibility tree -- neither can see a HUD
/// element's *frame* against the safe content rect, which is the actual
/// acceptance criterion here. Hosting the scene in a real `SKView` that
/// reports fixed, non-zero safe-area insets exercises the same production
/// code path (`didChangeSize(_:)` ->
/// `layoutSafeAreaDependentContent()` -> `HUDLayer.applyLayout(...)`) with
/// the geometry actually checkable.
final class HUDRotationUITests: XCTestCase {

    private let portraitSize = CGSize(width: 390, height: 844)
    private let portraitInsets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    private let landscapeSize = CGSize(width: 844, height: 390)
    private let landscapeInsets = UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)

    /// The tightest supported landscape geometry (812x375, 21pt home
    /// indicator -- iPhone X/XS/11 Pro, 12/13 mini). See
    /// `HUDLayoutTests.compactLandscapeSize`: rotating into *this* one is
    /// what exercises the banner's derived placement, and hardcoding only
    /// 844x390 in this suite is part of why PR 2's first cut looked green.
    private let compactLandscapeSize = CGSize(width: 812, height: 375)
    private let compactLandscapeInsets = UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)

    /// Retained for the lifetime of the test: `SKScene.view` is a
    /// back-reference into whatever presented it, and a view built and
    /// discarded inside a helper method (with nothing else holding it)
    /// would leave that reference dangling before the test body runs --
    /// the same "retain the presented view as an instance property"
    /// discipline `PulseAbilityLiveCompositionTests.hostView`/
    /// `.presentedView` already follow, for the same reason.
    private var hostView: UIView!
    private var presentedView: FixedInsetsHUDTestView!

    override func tearDown() {
        presentedView?.isPaused = true
        presentedView = nil
        hostView?.subviews.forEach { $0.removeFromSuperview() }
        hostView = nil
        super.tearDown()
    }

    /// Hosts `scene` in a real, presented `SKView` that reports `insets`
    /// for `safeAreaInsets` -- the same technique
    /// `PulseAbilityLiveCompositionTests.FixedInsetsSKView` uses (that type
    /// is `private` to its own file, so this is a small local restatement
    /// rather than a shared dependency) -- so `GameScene
    /// .currentSafeAreaInsets` sees a real, non-zero value instead of the
    /// `.zero` a headless (view-less) scene always reports.
    private func makeLiveScene(size: CGSize, insets: UIEdgeInsets) -> GameScene {
        let scene = GameScene(size: size)
        let bounds = CGRect(origin: .zero, size: size)
        let host = UIView(frame: bounds)
        let view = FixedInsetsHUDTestView(frame: bounds)
        view.injectedSafeAreaInsets = insets
        host.addSubview(view)

        view.isPaused = true
        view.presentScene(scene)
        view.isPaused = true

        hostView = host
        presentedView = view
        return scene
    }

    private func elementFrame(_ node: SKNode, size: CGSize) -> CGRect {
        CGRect(
            x: node.position.x - size.width / 2,
            y: node.position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func assertEveryElementInsideTheSafeArea(
        _ hud: HUDLayer,
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let safeRect = HUDLayout.safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        let elements: [(String, SKNode, CGSize)] = [
            ("hpBar", hud.hpBar, HUDLayout.hpBarSize),
            ("levelXPBar", hud.levelXPBar, HUDLayout.levelXPBarSize),
            ("runTimer", hud.runTimer, HUDLayout.runTimerSize),
            ("killCount", hud.killCount, HUDLayout.killCountSize),
            ("pulseButton", hud.pulseButton, HUDLayout.pulseButtonSize),
            ("swarmBanner", hud.swarmBanner, HUDLayout.swarmBannerSize),
        ]

        for (name, node, size) in elements {
            let frame = elementFrame(node, size: size)
            XCTAssertTrue(
                safeRect.contains(frame),
                "\(name) frame \(frame) escapes the safe content rect \(safeRect) at scene size \(sceneSize)",
                file: file, line: line
            )
        }
    }

    func test_startingARun_thenRotatingPortraitToLandscapeAndBack_keepsEveryHUDElementInsideTheSafeArea() throws {
        let scene = makeLiveScene(size: portraitSize, insets: portraitInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount HUDLayer")
        XCTAssertFalse(hud.isHidden, "the HUD must be visible for the whole of a run")
        XCTAssertEqual(hud.currentOrientation, .portrait)
        assertEveryElementInsideTheSafeArea(hud, sceneSize: portraitSize, safeAreaInsets: portraitInsets)

        // MARK: Rotate to landscape.

        let sizeBeforeLandscape = scene.size
        scene.size = landscapeSize
        presentedView.injectedSafeAreaInsets = landscapeInsets
        scene.didChangeSize(sizeBeforeLandscape)

        XCTAssertFalse(hud.isHidden, "the HUD must stay visible across a rotation mid-run")
        XCTAssertEqual(hud.currentOrientation, .landscape, "the rotation must reach HUDLayer.applyLayout(...)")
        assertEveryElementInsideTheSafeArea(hud, sceneSize: landscapeSize, safeAreaInsets: landscapeInsets)

        // MARK: Rotate back to portrait.

        let sizeBeforePortraitAgain = scene.size
        scene.size = portraitSize
        presentedView.injectedSafeAreaInsets = portraitInsets
        scene.didChangeSize(sizeBeforePortraitAgain)

        XCTAssertFalse(hud.isHidden)
        XCTAssertEqual(hud.currentOrientation, .portrait)
        assertEveryElementInsideTheSafeArea(hud, sceneSize: portraitSize, safeAreaInsets: portraitInsets)

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "node(s) escaped their layer band after rotating with the HUD mounted: "
                + scene.layerBandViolationReport().joined(separator: "; ")
        )
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
    }

    /// The same two invariants after a rotation into the *tightest*
    /// supported landscape, against the mounted layer: every element inside
    /// the safe area, and no element overlapping the region the stick
    /// occupies or a sibling slot. This is the geometry the banner's
    /// budget-derived placement exists for -- the top stack does not fit
    /// above the stick's region here, so the banner is lifted clear of it.
    func test_rotatingIntoTheTightestSupportedLandscape_keepsEveryElementInsideTheSafeAreaAndDisjoint() throws {
        let scene = makeLiveScene(size: portraitSize, insets: portraitInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount HUDLayer")

        let sizeBeforeLandscape = scene.size
        scene.size = compactLandscapeSize
        presentedView.injectedSafeAreaInsets = compactLandscapeInsets
        scene.didChangeSize(sizeBeforeLandscape)

        XCTAssertEqual(hud.currentOrientation, .landscape, "the rotation must reach HUDLayer.applyLayout(...)")
        assertEveryElementInsideTheSafeArea(
            hud, sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets
        )
        assertNoTwoElementsOverlap(hud, sceneSize: compactLandscapeSize)

        let occupied = HUDLayout.thumbstickReservedRegion(
            sceneSize: compactLandscapeSize, safeAreaInsets: compactLandscapeInsets
        )
        let banner = elementFrame(hud.swarmBanner, size: HUDLayout.swarmBannerSize)
        XCTAssertFalse(
            banner.intersects(occupied),
            "the mounted swarm banner \(banner) must stay clear of the stick's region \(occupied) "
                + "on the tightest supported landscape geometry"
        )
    }

    /// Nothing may be clipped by a *sibling* HUD element either: the six
    /// slots must stay mutually disjoint in both orientations, so a
    /// rotation can never stack the run clock on top of the kill counter.
    func test_theMountedHUDElements_neverOverlapEachOther_inEitherOrientation() throws {
        let scene = makeLiveScene(size: portraitSize, insets: portraitInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let hud = try XCTUnwrap(scene.hudLayer)

        assertNoTwoElementsOverlap(hud, sceneSize: portraitSize)

        let sizeBeforeLandscape = scene.size
        scene.size = landscapeSize
        presentedView.injectedSafeAreaInsets = landscapeInsets
        scene.didChangeSize(sizeBeforeLandscape)

        assertNoTwoElementsOverlap(hud, sceneSize: landscapeSize)
    }

    private func assertNoTwoElementsOverlap(
        _ hud: HUDLayer,
        sceneSize: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let elements: [(String, SKNode, CGSize)] = [
            ("hpBar", hud.hpBar, HUDLayout.hpBarSize),
            ("levelXPBar", hud.levelXPBar, HUDLayout.levelXPBarSize),
            ("runTimer", hud.runTimer, HUDLayout.runTimerSize),
            ("killCount", hud.killCount, HUDLayout.killCountSize),
            ("pulseButton", hud.pulseButton, HUDLayout.pulseButtonSize),
            ("swarmBanner", hud.swarmBanner, HUDLayout.swarmBannerSize),
        ]

        for outer in elements.indices {
            for inner in elements.indices where inner > outer {
                let first = elementFrame(elements[outer].1, size: elements[outer].2)
                let second = elementFrame(elements[inner].1, size: elements[inner].2)
                XCTAssertFalse(
                    first.intersects(second),
                    "\(elements[outer].0) \(first) overlaps \(elements[inner].0) \(second) "
                        + "at scene size \(sceneSize)",
                    file: file, line: line
                )
            }
        }
    }

    /// The HUD must hide again once the run ends, the same convention the
    /// thumbstick/older pulse button already follow, so it does not sit
    /// over the death/high-scores/menu screens behind it.
    func test_theHUD_hidesAgain_onceTheRunEnds() throws {
        let scene = makeLiveScene(size: portraitSize, insets: portraitInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let hud = try XCTUnwrap(scene.hudLayer)
        XCTAssertFalse(hud.isHidden)

        XCTAssertTrue(scene.stateMachine.transition(to: .death))

        XCTAssertTrue(hud.isHidden, "the HUD must hide once the run has ended")
    }

    /// ... and a RUN AGAIN reuses that same instance rather than mounting a
    /// second HUD over the first -- the "mount once, reuse across restarts"
    /// convention `player`/`playerCombat` already follow.
    func test_aSecondRun_reusesTheSameHUDInstance_ratherThanMountingASecondOne() throws {
        let scene = makeLiveScene(size: portraitSize, insets: portraitInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        let firstHUD = try XCTUnwrap(scene.hudLayer)

        XCTAssertTrue(scene.stateMachine.transition(to: .death))
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let secondHUD = try XCTUnwrap(scene.hudLayer)
        XCTAssertTrue(firstHUD === secondHUD, "a restart must reuse the mounted HUD, not build a second one")
        XCTAssertFalse(secondHUD.isHidden, "the reused HUD must be visible again for the new run")
        XCTAssertEqual(
            scene.uiLayer.children.filter { $0 is HUDLayer }.count, 1,
            "exactly one HUDLayer may ever be mounted in uiLayer"
        )
    }
}

/// A trivial `SKView` subclass that reports a fixed, caller-set
/// `safeAreaInsets` regardless of window attachment -- see
/// `HUDRotationUITests.makeLiveScene(size:insets:)`'s own doc comment for
/// why this is a small local restatement of
/// `PulseAbilityLiveCompositionTests.FixedInsetsSKView` rather than a
/// shared dependency (that type is `private` to its own file).
private final class FixedInsetsHUDTestView: SKView {
    var injectedSafeAreaInsets: UIEdgeInsets = .zero
    override var safeAreaInsets: UIEdgeInsets { injectedSafeAreaInsets }
}
