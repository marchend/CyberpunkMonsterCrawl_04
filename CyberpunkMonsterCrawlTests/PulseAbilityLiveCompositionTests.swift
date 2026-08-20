import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10-t4`: the regression guard for the `pulse-ability` runtime
/// probe journey crashing (process gone) at the screenshot right after
/// entering `.gameplay` and again after pressing the pulse button.
///
/// Every existing pulse test drives the scene through one of two shortcuts
/// that this journey does not get: `PulseButtonTests`/`FloatingThumbstickNodeTests`
/// call each node's own API directly with no `GameScene` at all, and
/// `PulseSceneWiringTests`/`GameViewControllerCompositionTests` build a bare
/// `GameScene(size:)` (or `GameViewController().makeGameScene(size:)`) that
/// is **never presented in a real `SKView`** -- `didMove(to:)` never runs,
/// `view` stays `nil` for the scene's whole lifetime, and
/// `currentSafeAreaInsets` (`view?.safeAreaInsets ?? .zero`) is therefore
/// always `.zero`. `AccessibleSKViewTests` *does* present a real
/// `AccessibleSKView`, but every fixture there is off-window, where
/// `UIView.safeAreaInsets` also reads `.zero` -- so no existing test has
/// ever driven `GameScene.didMove(to:)` -> `layoutPulseButton()` /
/// `thumbstick.layout(...)` -> `assertSceneInvariants()` (or a later
/// `.gameplay` entry, or a real touch dispatch) against genuinely
/// non-zero, live safe-area insets. That is exactly the "real SKView, real
/// safe-area insets" surface this file exercises for the first time.
///
/// `FixedInsetsSKView` below overrides the `open` `UIView.safeAreaInsets`
/// getter -- the standard technique for exercising safe-area-dependent
/// layout without a real window/device -- so these tests can drive
/// `GameScene` (built through the real composition root,
/// `GameViewController.makeGameScene`) with a real, presented `SKView` and
/// a realistic notched-iPhone safe area throughout, then dispatch real
/// touches through `GameScene`'s own dispatcher exactly as
/// `GameViewControllerCompositionTests`/`PulseSceneWiringTests` already do.
///
/// This is a plain `SKView`, not `AccessibleSKView` (that class is `final`
/// and cannot be subclassed to override `safeAreaInsets`): the accessibility
/// mirror/container machinery is already covered end-to-end by
/// `AccessibleSKViewTests`, and nothing in `GameScene`'s own safe-area
/// layout or invariant logic cares which `SKView` subclass hosts it -- only
/// that `view != nil` and `view.safeAreaInsets` reports something real.
final class PulseAbilityLiveCompositionTests: XCTestCase {

    private let sceneSize = CGSize(width: 400, height: 800)

    /// A realistic notched-iPhone portrait safe area -- top ~59pt
    /// (status bar / Dynamic Island), bottom ~34pt (home indicator) --
    /// the same order of magnitude the plan for this task names and the
    /// landscape figures `ScreensTests` already uses elsewhere in this
    /// suite (`UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)`).
    private let liveInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    /// Retained for the lifetime of the test: `SKScene.view` is a
    /// back-reference into whatever presented it, and a view built and
    /// discarded inside a helper method (with nothing else holding it)
    /// would leave that reference dangling the moment the helper returns --
    /// `AccessibleSKViewTests.hostView`/`.containerView` follow the same
    /// "retain the presented view as an instance property" discipline for
    /// the same reason.
    private var hostView: UIView!
    private var presentedView: FixedInsetsSKView!

    override func tearDown() {
        presentedView = nil
        hostView?.subviews.forEach { $0.removeFromSuperview() }
        hostView = nil
        super.tearDown()
    }

    private func makeComposedScene() -> GameScene {
        GameViewController().makeGameScene(size: sceneSize)
    }

    /// Hosts `scene` in a real, presented `SKView` that reports `insets`
    /// for `safeAreaInsets` instead of the `.zero` every off-window fixture
    /// elsewhere in this suite reports.
    ///
    /// `didMove(to:)` fires synchronously (or at least deterministically,
    /// before this method returns) from `presentScene(_:)` even off-window
    /// -- `AccessibleSKViewTests.test_presentedScene_keepsTheCameraOnTheSceneCentre`
    /// already proves this by asserting `centreCameraOnScene()` ran, and
    /// that method is only ever called from `didMove(to:)`/`didChangeSize(_:)`
    /// -- so this is enough to exercise `GameScene.didMove(to:)` against
    /// real, non-zero safe-area insets for the first time in this suite.
    @discardableResult
    private func makeLiveView(_ scene: GameScene, insets: UIEdgeInsets) -> FixedInsetsSKView {
        let bounds = CGRect(origin: .zero, size: sceneSize)
        let host = UIView(frame: bounds)
        let view = FixedInsetsSKView(frame: bounds)
        view.injectedSafeAreaInsets = insets
        host.addSubview(view)

        // Paused on both sides of presentation, the same reordering
        // `AccessibleSKViewTests.makePresentedView` documents and pins:
        // `presentScene(_:)` clears a pause set *before* it, so only the
        // second assignment is load-bearing, but the first narrows the
        // window in which SpriteKit's own scheduling could tick
        // concurrently with this method's synchronous work.
        view.isPaused = true
        view.presentScene(scene)
        view.isPaused = true

        hostView = host
        presentedView = view
        return view
    }

    // MARK: - layoutPulseButton()/reservedPulseButtonSlot honour real insets

    /// The exact "untested input" the plan for this task names:
    /// `layoutPulseButton()`/`FloatingThumbstickNode
    /// .reservedPulseButtonSlot(forSize:safeAreaInsets:)` driven by
    /// `didMove(to:)` with real, non-zero safe-area insets rather than the
    /// `.zero` every prior test supplied.
    func test_didMove_withRealSafeAreaInsets_positionsThumbstickAndPulseButton_fromTheLiveInsets() {
        let scene = makeComposedScene()
        makeLiveView(scene, insets: liveInsets)

        let expectedSlot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: scene.size,
            safeAreaInsets: liveInsets
        )
        XCTAssertEqual(scene.pulseButton.position.x, expectedSlot.midX, accuracy: 1e-6)
        XCTAssertEqual(scene.pulseButton.position.y, expectedSlot.midY, accuracy: 1e-6)

        let expectedRest = FloatingThumbstickNode.restingPosition(forSize: scene.size, safeAreaInsets: liveInsets)
        XCTAssertEqual(scene.thumbstick.restPosition.x, expectedRest.x, accuracy: 1e-6)
        XCTAssertEqual(scene.thumbstick.restPosition.y, expectedRest.y, accuracy: 1e-6)
    }

    // MARK: - Entering .gameplay must not run on stale, pre-settle insets

    /// The startup-timing race this regression guards against: on a real
    /// cold launch, `didMove(to:)` can fire before the hosting view's
    /// first real layout pass has settled its true safe area (the view
    /// reports `.zero` until then), and -- before this task's fix --
    /// nothing but a genuine *size* change ever re-laid the thumbstick or
    /// the pulse button out afterward. A safe-area value that only
    /// settles *after* `didMove(to:)`, but *before* the player taps PLAY,
    /// therefore never reached either control: a run starting fine on the
    /// simulator (whose safe area is stable well before launch) could
    /// still ship a HUD control positioned for a `.zero` safe area on a
    /// real notched device where that settling races the first render.
    ///
    /// Entering `.gameplay` -- the one moment both controls become
    /// visible/interactive -- must therefore re-derive their layout from
    /// whatever the hosting view reports *at that moment*, not from
    /// whichever insets `didMove(to:)` happened to see first.
    func test_enteringGameplay_afterInsetsSettleAfterDidMove_usesTheLiveInsets_notTheStaleOnes() {
        let scene = makeComposedScene()
        let view = makeLiveView(scene, insets: .zero)

        // The window's real safe area "arrives" after didMove(to:) already
        // ran with .zero -- nothing about this transition resizes the
        // scene, so no didChangeSize(_:) fires to pick it up on its own.
        view.injectedSafeAreaInsets = liveInsets

        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let expectedSlot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: scene.size,
            safeAreaInsets: liveInsets
        )
        XCTAssertEqual(
            scene.pulseButton.position.x, expectedSlot.midX, accuracy: 1e-6,
            "the pulse button must be laid out from the live safe-area insets the moment a run starts, "
                + "not from whatever didMove(to:) saw before the view's safe area had settled"
        )
        XCTAssertEqual(scene.pulseButton.position.y, expectedSlot.midY, accuracy: 1e-6)

        let expectedRest = FloatingThumbstickNode.restingPosition(forSize: scene.size, safeAreaInsets: liveInsets)
        XCTAssertEqual(
            scene.thumbstick.restPosition.x, expectedRest.x, accuracy: 1e-6,
            "the thumbstick must be laid out from the live safe-area insets the moment a run starts"
        )
        XCTAssertEqual(scene.thumbstick.restPosition.y, expectedRest.y, accuracy: 1e-6)
    }

    // MARK: - The whole journey, end to end, with a real SKView + real insets

    /// Reproduces the `pulse-ability` journey itself as closely as an
    /// off-device XCTest can: the composition root, a real presented
    /// `SKView`, a real touch dispatch onto PLAY, real elapsed `.gameplay`
    /// frames (not a bare handful of synthetic advances -- a live `SKView`
    /// really does drive `update(_:)` continuously), and a real touch
    /// dispatch onto the pulse button at its *live*, insets-aware
    /// position -- asserting the two structural invariants
    /// (`assertSceneInvariants()`'s own checks) hold throughout, and that
    /// the scene is still alive and responsive after each step.
    func test_pulseAbilityJourney_liveCompositionRoot_realInsets_survivesEntryAndAPress_withInvariantsIntact() throws {
        let scene = makeComposedScene()
        let view = makeLiveView(scene, insets: liveInsets)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        // Journey step 3: tap PLAY through the real dispatch path, at the
        // scene-space point a real device tap actually lands on.
        //
        // Presenting the scene (unlike every other pulse test, which never
        // attaches a view) makes `didMove(to:)` really call
        // `centreCameraOnScene()`, moving `cameraNode` off the scene's
        // origin -- so `menu.playButton.position` (uiLayer-*local* space)
        // is no longer the correct `atScenePoint` argument on its own;
        // `accessibilityFrameInScene(for:)` (the same conversion
        // `AccessibleSKView` itself uses to target a real accessibility-
        // driven tap) is what turns it into the genuine scene-space point.
        let playFrame = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))
        scene.dispatchTouch(atScenePoint: CGPoint(x: playFrame.midX, y: playFrame.midY))
        XCTAssertEqual(scene.stateMachine.currentState, .gameplay)

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "node(s) escaped their layer band right after entering .gameplay on a live view: "
                + scene.layerBandViolationReport().joined(separator: "; ")
        )
        XCTAssertTrue(
            scene.nodesBypassingSceneTouchDispatch().isEmpty,
            "a node bypassed the scene's touch dispatch right after entering .gameplay on a live view"
        )

        // Journey steps 4/5: let the run advance real frames the way the
        // probe's `wait 2s` does.
        var now: TimeInterval = 1
        let frameDelta: TimeInterval = 1.0 / 60.0
        while now < 1 + 2.0 {
            now += frameDelta
            scene.update(now)
        }

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "node(s) escaped their layer band after ~2s of real .gameplay frames: "
                + scene.layerBandViolationReport().joined(separator: "; ")
        )
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
        XCTAssertNotNil(view.scene, "the scene must still be presented after ~2s of real frames")

        // Journey steps 6/7: press the pulse button through the real
        // dispatch path, at its live, insets-aware scene-space position --
        // the same `accessibilityFrameInScene(for:)` conversion as above,
        // now exercised for `pulseButton` (a node that becomes accessible
        // only once `.gameplay` is entered, so this is the first time this
        // suite resolves *its* frame rather than only a menu button's).
        XCTAssertFalse(scene.pulseAbility.isOnCooldown, "precondition: a fresh ability is ready")
        let pulseFrame = try XCTUnwrap(scene.accessibilityFrameInScene(for: scene.pulseButton))
        let responder = scene.dispatchTouch(atScenePoint: CGPoint(x: pulseFrame.midX, y: pulseFrame.midY))

        XCTAssertTrue(responder === scene.pulseButton, "the live press must resolve to the pulse button")
        XCTAssertTrue(scene.pulseAbility.isOnCooldown, "the live press must actually fire the ability")
        XCTAssertFalse(scene.pulseRing.isHidden, "a fired pulse must play the ring")

        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "node(s) escaped their layer band after the live pulse-button press: "
                + scene.layerBandViolationReport().joined(separator: "; ")
        )
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)

        // Journey step 9: the app must still be foregrounded/responsive --
        // the crash this file guards against tears down exactly this.
        XCTAssertNotNil(view.scene, "the scene must still be presented after the pulse-button press")
        XCTAssertEqual(
            scene.stateMachine.currentState, .gameplay,
            "the live press must not have knocked the app out of the run"
        )
    }

    // MARK: - Rotation mid-run still tracks live insets

    /// The other untested-input combination the plan names: a size *and*
    /// insets change (a rotation) after a run has already started, which
    /// must still re-lay the pulse button out from the new geometry via
    /// `didChangeSize(_:)` -- unlike the startup race above, this path was
    /// already wired before this task, so this pins it rather than fixing
    /// it.
    func test_rotationDuringAGameplayRun_reLaysOutThePulseButton_fromTheNewLiveInsets() {
        let scene = makeComposedScene()
        let view = makeLiveView(scene, insets: liveInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let landscapeSize = CGSize(width: 800, height: 400)
        let landscapeInsets = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)

        let oldSize = scene.size
        scene.size = landscapeSize
        view.injectedSafeAreaInsets = landscapeInsets
        scene.didChangeSize(oldSize)

        let expectedSlot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: landscapeSize,
            safeAreaInsets: landscapeInsets
        )
        XCTAssertEqual(scene.pulseButton.position.x, expectedSlot.midX, accuracy: 1e-6)
        XCTAssertEqual(scene.pulseButton.position.y, expectedSlot.midY, accuracy: 1e-6)

        XCTAssertTrue(scene.nodesEscapingTheirLayerBand().isEmpty)
        XCTAssertTrue(scene.nodesBypassingSceneTouchDispatch().isEmpty)
    }
}

// MARK: -

/// A trivial `SKView` subclass that reports a fixed, caller-set
/// `safeAreaInsets` regardless of window attachment.
///
/// `UIView.safeAreaInsets` is `open`, and overriding it is the standard,
/// deterministic technique for exercising safe-area-dependent layout
/// without a real window or device -- every other fixture in this suite
/// (`AccessibleSKViewTests`, `GameViewControllerCompositionTests`) is
/// off-window, where the real property always reads `.zero`, which is
/// exactly the gap `PulseAbilityLiveCompositionTests` exists to close.
/// A plain `SKView` (not `AccessibleSKView`, which is `final`) is enough:
/// nothing under test here depends on the accessibility mirror/container
/// machinery, only on `GameScene.currentSafeAreaInsets`
/// (`view?.safeAreaInsets ?? .zero`) seeing a real, non-zero value.
private final class FixedInsetsSKView: SKView {
    var injectedSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets { injectedSafeAreaInsets }
}
