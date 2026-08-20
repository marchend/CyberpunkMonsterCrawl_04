import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10-t4`: the regression guard for HUD controls being laid
/// out from **stale safe-area insets** on the `pulse-ability` runtime probe
/// journey -- the mis-placement bug found while investigating that
/// journey's crash (process gone) at the screenshot right after entering
/// `.gameplay` and again after pressing the pulse button.
///
/// **What this file does not prove.** These tests assert *placement* and
/// the scene invariants; they are not a crash reproduction, and none of
/// them would have crashed before the fix -- `test_enteringGameplay_...`
/// failed as a placement bug. No reachable assert/precondition on the
/// laid-out path is position-dependent (`assertSceneInvariants()` checks
/// zPosition bands + `isUserInteractionEnabled`; `FloatingThumbstickNode`'s
/// `currentSize != .zero` is satisfied by `commonInit()`;
/// `layoutPulseButton()`/`reservedPulseButtonSlot(...)` are pure
/// arithmetic), so **the crash cause remains unidentified**. A green run
/// here -- or a green probe journey, which may simply be the probe's tap
/// finally landing on a correctly placed button -- must not be recorded as
/// "crash fixed"; that needs a symbolicated crash log naming the frame.
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

    /// Only populated by `test_livePulseAnimation_...` below, which is the
    /// one test in this file that actually presents its view inside a real
    /// `UIWindow` -- every other test here (matching the rest of this
    /// suite) stays off-window on purpose. Retained the same "instance
    /// property, not a local" way `hostView`/`presentedView` are, for the
    /// same dangling-reference reason.
    private var window: UIWindow!

    override func tearDown() {
        // Pausing before tearing the hierarchy down matters only for the
        // one real-rendering test below: an unpaused `SKView` still
        // servicing a live display link while its scene/window are torn
        // out from under it is exactly the kind of teardown race this
        // property exists to avoid, even though every other test here
        // never flips `isPaused` off in the first place.
        presentedView?.isPaused = true
        presentedView = nil
        hostView?.subviews.forEach { $0.removeFromSuperview() }
        hostView = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
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

    // MARK: - The cause-level fix: insets settling with no state change

    /// The staleness is a property of the whole scene, not of the two
    /// gameplay controls, so the fix lives where UIKit says the value moved
    /// (`GameViewController.viewSafeAreaInsetsDidChange()`/
    /// `viewDidLayoutSubviews()` -> `GameScene
    /// .refreshLayoutForCurrentSafeArea()`), not at one state transition.
    ///
    /// `.menu` is the case a `.gameplay`-only fix misses entirely: it is
    /// registered from `GameViewController.viewDidLoad()` *before*
    /// `presentScene(_:)`, so `transitionScreens(to:)` first lays it out
    /// with `view == nil` -> `.zero` insets, and without this hook it keeps
    /// that layout for the whole session -- no state change, no size
    /// change, nothing else to refresh it.
    func test_safeAreaSettlingWithNoStateChange_reLaysOutTheMenuScreenAndThumbstick() throws {
        let scene = makeComposedScene()
        let view = makeLiveView(scene, insets: .zero)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        XCTAssertEqual(menu.playButton.position.y, 0, accuracy: 1e-6, "precondition: laid out for .zero insets")

        // The safe area settles while the app is still sitting on the menu.
        view.injectedSafeAreaInsets = liveInsets
        scene.refreshLayoutForCurrentSafeArea()

        let expectedShift = (liveInsets.bottom - liveInsets.top) / 2
        XCTAssertEqual(
            menu.playButton.position.y, expectedShift, accuracy: 1e-6,
            "the menu screen must follow a safe area that settles after didMove(to:), like every other consumer"
        )

        let expectedRest = FloatingThumbstickNode.restingPosition(forSize: scene.size, safeAreaInsets: liveInsets)
        XCTAssertEqual(scene.thumbstick.restPosition.x, expectedRest.x, accuracy: 1e-6)
        XCTAssertEqual(scene.thumbstick.restPosition.y, expectedRest.y, accuracy: 1e-6)

        let expectedSlot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: scene.size,
            safeAreaInsets: liveInsets
        )
        XCTAssertEqual(scene.pulseButton.position.x, expectedSlot.midX, accuracy: 1e-6)
        XCTAssertEqual(scene.pulseButton.position.y, expectedSlot.midY, accuracy: 1e-6)
    }

    /// The no-move guard that makes the refresh safe to call from a
    /// per-layout-pass hook (`viewDidLayoutSubviews()`): with the insets
    /// unchanged it must not disturb anything -- notably not re-centre a
    /// thumbstick the player has dragged off its rest position.
    func test_refreshLayoutForCurrentSafeArea_withUnchangedInsets_isANoOp() {
        let scene = makeComposedScene()
        makeLiveView(scene, insets: liveInsets)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))

        let positionBefore = scene.pulseButton.position
        scene.refreshLayoutForCurrentSafeArea()

        XCTAssertEqual(scene.pulseButton.position.x, positionBefore.x, accuracy: 1e-6)
        XCTAssertEqual(scene.pulseButton.position.y, positionBefore.y, accuracy: 1e-6)
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

        // Journey step 9: the app must still be foregrounded/responsive.
        // This is a liveness check on the journey, not a crash repro -- see
        // this file's header: nothing here reproduces the recorded
        // "process gone", whose cause is still unidentified.
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

    // MARK: - Real (unpaused, in-window) rendering: the one condition no test above exercises

    /// `CYBERPUN-17-10-t5`: every test above -- and every pre-`-t4` pulse
    /// test -- keeps its `SKView` `isPaused = true` and never attaches it to
    /// a real `UIWindow`. SpriteKit's own render loop is driven by a
    /// `CADisplayLink` that only fires for a view that is both unpaused
    /// *and* actually installed in an on-screen window; nothing above ever
    /// satisfies both, so nothing above has ever made SpriteKit actually
    /// upload `sprite_pulse`'s texture data to the GPU and draw a real frame
    /// of the mounted `PulseRingNode` -- exactly the moment the runtime
    /// probe's journey lost the process at (step 5, first `.gameplay`
    /// entry) and again at (step 8, right after the pulse-button press).
    ///
    /// This test closes that specific, previously-unexercised gap: a real
    /// window, a real unpaused `SKView`, a real `PLAY` tap, a real pulse-
    /// button tap, and enough real run-loop time for SpriteKit to actually
    /// render past the ring's full 8-frame play-through
    /// (`8 * PulseRingNode.frameDuration` = 0.24s) -- all against the
    /// production `PulseRingNode`/`AtlasSheet.pulse` path, never a stub.
    ///
    /// **What a green run here does and does not establish.** Exactly like
    /// every other test in this file (see this file's own header note): a
    /// crash-free run here is not proof this *was* the journey's crash
    /// cause, since that cause remains genuinely unidentified (this task's
    /// own audit ruled out the leading `sprite_pulse` dimension hypothesis
    /// -- see `AtlasSheet.pulse`'s own doc comment -- and found no other
    /// reachable defect). What it *does* establish, for the first time in
    /// this suite, is that a real SpriteKit render pass over the exact
    /// mounted node/texture/animation this journey exercises does not, on
    /// its own, tear the process down in this test environment.
    func test_livePulseAnimation_realWindowUnpausedRendering_survivesAFullRingPlaythrough() throws {
        let scene = makeComposedScene()
        let view = makeLiveView(scene, insets: liveInsets)
        let menu = try XCTUnwrap(scene.activeScreen as? MenuScreenNode)

        let hostedWindow = UIWindow(frame: CGRect(origin: .zero, size: sceneSize))
        let rootViewController = UIViewController()
        rootViewController.view.addSubview(hostView)
        hostedWindow.rootViewController = rootViewController
        hostedWindow.makeKeyAndVisible()
        window = hostedWindow

        // Real rendering from here on: SpriteKit's own display-link loop,
        // not this test manually stepping `scene.update(_:)` the way the
        // paused-view journey test above does.
        view.isPaused = false

        let playFrame = try XCTUnwrap(scene.accessibilityFrameInScene(for: menu.playButton))
        scene.dispatchTouch(atScenePoint: CGPoint(x: playFrame.midX, y: playFrame.midY))
        XCTAssertEqual(scene.stateMachine.currentState, .gameplay)

        // Let real frames actually render before pressing the button.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNotNil(view.window, "the view must still be presented after real rendering has started")

        let pulseFrame = try XCTUnwrap(scene.accessibilityFrameInScene(for: scene.pulseButton))
        let responder = scene.dispatchTouch(atScenePoint: CGPoint(x: pulseFrame.midX, y: pulseFrame.midY))
        XCTAssertTrue(responder === scene.pulseButton, "the live press must resolve to the pulse button")
        XCTAssertTrue(scene.pulseAbility.isOnCooldown, "the live press must actually fire the ability")

        // The ring's own full play-through is 8 * PulseRingNode.frameDuration
        // (0.03s) = 0.24s; give real rendering comfortable headroom past
        // that before asserting on the app's state.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        XCTAssertNotNil(view.window, "the view must still be presented in a window after real rendering")
        XCTAssertEqual(
            scene.stateMachine.currentState, .gameplay,
            "a real, unpaused render pass over the mounted PulseRingNode must not have torn the app down"
        )
        XCTAssertTrue(
            scene.nodesEscapingTheirLayerBand().isEmpty,
            "node(s) escaped their layer band after a real, unpaused render pass: "
                + scene.layerBandViolationReport().joined(separator: "; ")
        )
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
