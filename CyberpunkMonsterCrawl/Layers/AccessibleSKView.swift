import SpriteKit
import UIKit

/// The `SKView` subclass the app hosts `GameScene` in, and the source of the
/// **camera-aware, screen-space geometry** every accessible UI node needs
/// before an out-of-process accessibility client (XCUITest, VoiceOver, the
/// scripted runtime probe) can drive it.
///
/// ## The bug this exists to fix
///
/// `ButtonNode` already sets `isAccessibilityElement`, `accessibilityLabel`
/// and `.button` traits on the `SKNode` itself, and a *finger* tap on a
/// button's visible pixels has always worked: UIKit hands the touch to
/// `GameScene.touchesBegan(_:with:)`, which routes it UI-first through
/// `routeTouch(at:)` and delivers it to the button's `TouchResponder`.
///
/// What did **not** work is a tap driven by *accessibility element* - the way
/// XCUITest and the scripted runtime probe drive one. Such a driver resolves
/// an element's hittable point from its `accessibilityFrame`, and nothing in
/// this codebase computed one: SpriteKit's implicit `SKNode` accessibility
/// support has to derive a screen-space frame on its own, and it does not
/// resolve one correctly for a node sitting under a camera transform - which
/// every button does, because `GameScene.uiLayer` is parented to `cameraNode`
/// precisely so the UI stays camera-locked.
///
/// ## The fix, part 1: geometry the scene agrees with
///
/// This class computes each accessible node's rect through the *same*
/// coordinate path `routeTouch(at:)` trusts for real touches:
///
/// 1. `GameScene.accessibilityFrameInScene(for:)` - the node's accumulated
///    frame converted up to scene space, which is the algebraic inverse of
///    the `uiLayer.convert(_:from: self)` + `atPoint(_:)` walk the scene
///    hit-tests with.
/// 2. `viewRect(forSceneRect:in:)` - scene space to *view* space, the inverse
///    of the conversion SpriteKit uses to give `UITouch.location(in:)` its
///    value (and camera-aware, which is the step SpriteKit's implicit support
///    gets wrong).
///
/// Because the rect is derived from the inverse of the hit test, an
/// element-driven tap and the scene's own routing cannot disagree.
/// `AccessibleSKViewTests` pins that agreement directly.
///
/// ## The fix, part 2: mirror the nodes with *real views*, not synthesized
/// elements
///
/// Publishing the right numbers is only the **query** half of the
/// accessibility contract - "what elements are there, and where?". There is a
/// second, independent half: "*which element is at this point?*". XCUITest's
/// `isHittable` is defined in terms of that second question: it resolves an
/// element's hit point from the frame the app publishes, asks the app which
/// accessibility element sits there, and requires the **same** element back.
/// That is a uniquely nasty failure mode when it goes wrong, because the
/// element is still *found* (`app.descendants(matching: .any)["PLAY"]`
/// resolves) and only the hittability predicate fails - which is exactly how
/// `CyberpunkMonsterCrawlUITests` failed, one line after finding PLAY.
///
/// Two earlier attempts tried to answer that second question ourselves, from
/// hand-vended `UIAccessibilityElement`s: first by overriding
/// `accessibilityHitTest(_:event:)` on this `SKView` subclass (SpriteKit's own
/// implementation keeps answering for an `SKView`, so ours was never
/// consulted), then by moving those synthesized elements onto a plain
/// `UIView` sibling with `accessibilityFrameInContainerSpace` and a custom
/// hit test there. The elements were found and their frames measured the
/// button - and `isHittable` was still `false`. A synthesized
/// `UIAccessibilityElement` only participates in the accessibility server's
/// point lookup as far as whoever vends it re-implements that lookup, and
/// every part of that re-implementation (element lifetime, which coordinate
/// space the hit-test point arrives in, which overload the server actually
/// calls) is ours to get wrong.
///
/// So stop synthesizing elements. `SceneAccessibilityContainerView` now
/// mirrors each accessible node with a **real, invisible `UIView` subview**
/// whose `frame` is the node's camera-aware rect in container space. A real
/// view in a real hierarchy is natively point-resolvable: UIKit derives its
/// `accessibilityFrame` from its own geometry (correct in *every* interface
/// orientation, which is what `AppLaunchAndRotationUITests` exercises when it
/// rotates to `.landscapeLeft`), and the accessibility server resolves a
/// point to it exactly as it does for the `UILabel`s and `UIButton`s of any
/// ordinary app - no element cache, no `accessibilityFrameInContainerSpace`,
/// no custom `accessibilityHitTest`. Overlap is settled by the one mechanism
/// UIKit already defines for sibling views: **z-order**, topmost wins.
///
/// ## The fix, part 3: be point-resolvable *without* stealing the touch
///
/// A real view answers the point lookup only while it actually takes part in
/// hit-testing, and that is where the first version of this overlay went
/// wrong: it set `isUserInteractionEnabled = false` on the container and on
/// every mirror, reasoning that a non-interactive view cannot steal a finger.
/// It cannot - but `UIView.hitTest(_:with:)` returns `nil` outright for such
/// a view and never descends into its subviews, and `accessibilityHitTest(_:)`
/// (the lookup XCUITest's `isHittable` is defined in terms of) is built on
/// exactly that walk. So the lookup at PLAY's activation point skipped the
/// whole overlay subtree and resolved to the `SKView` underneath, whose own
/// accessibility tree is deliberately silenced here - nothing was returned at
/// PLAY's own point, and `isHittable` stayed `false` one line after PLAY was
/// found.
///
/// The overlay is therefore *interactive* (`isUserInteractionEnabled = true`
/// on the container and on every mirror) so UIKit walks into it.
///
/// The first version of that overlay then tried to have it both ways, by
/// **discriminating on the event** in
/// `SceneAccessibilityContainerView.hitTest(_:with:)`: answer the mirror for
/// an event-less hit test (accessibility is asking) and `nil` for one
/// carrying a `UIEvent` (a finger is arriving), so the touch fell through
/// to the `SKView` by transparency. It is a tidy story and it is wrong:
/// hittability cannot be made to depend on telling an accessibility hit test
/// apart from a touch hit test. `isHittable` is *defined* as the point-lookup
/// half of the accessibility contract, and in a live simulator that lookup
/// does not reliably arrive down the `event == nil` branch an off-window unit
/// test can pin - so the point over PLAY kept resolving to the (now
/// AX-silenced) `SKView`, leaving PLAY findable, tappable *and*
/// `isHittable == false`, which is exactly how
/// `CyberpunkMonsterCrawlUITests` failed.
///
/// So the overlay answers **every** hit test the same way - the mirror
/// covering the point, whatever the event - and gives the touch back
/// *explicitly* instead of by transparency:
///
/// * a **point lookup** (accessibility, `isHittable`) resolves to the mirror,
///   which is the answer hittability requires and now cannot disagree with
///   the frame the same view published;
/// * a **real touch** does resolve to the mirror too, so UIKit delivers it
///   there - and `SceneAccessibilityMirrorView` forwards it, converted into
///   scene space, straight into `GameScene.dispatchTouch(atScenePoint:)`.
///   The scene stays the sole touch dispatcher, and a finger on PLAY starts a
///   run exactly as it did before this class existed. A point no mirror
///   covers still resolves to `nil` and falls through to the `SKView`
///   untouched, which is every pixel of the game world.
///
/// ## The fix, part 4: never rebuild the tree *during* the lookup
///
/// Answering the point lookup is not enough on its own: the answer has to be
/// stable. The first interactive version of the overlay called
/// `refreshAccessibilityMirrors()` from both
/// `SceneAccessibilityContainerView.hitTest(_:with:)` and its
/// `accessibilityElements` getter, so that the mirrors were always in step
/// with the live scene graph. That refresh adds, removes and reorders
/// subviews and rewrites frames - i.e. it mutates the hierarchy while the
/// accessibility server is walking it. `isHittable` is a *comparison* between
/// the two halves of the contract (the element resolved from the published
/// frame, and the element answered at that frame's point), so a rebuild in
/// between let the halves be answered from two different trees: PLAY stayed
/// findable, a synthesized tap at its point still worked (which is why
/// `AppLaunchAndRotationUITests` passed), and `isHittable` was `false`.
///
/// So the lookup is pure. Mirrors are reconciled only at explicit lifecycle
/// points - `presentScene(_:)`, `layoutSubviews()` on either view,
/// `SceneAccessibilityContainerView.didMoveToWindow()`,
/// `GameViewController.viewDidLayoutSubviews()`, and
/// `refreshSceneAccessibility()` called from
/// `GameScene.transitionScreens(to:)` so a screen swap still retires stale
/// mirrors - every one of which happens *between* accessibility snapshots
/// rather than inside one.
///
/// SpriteKit's competing (camera-unaware) tree is silenced with
/// `accessibilityElementsHidden` on this view (see
/// `attachAccessibilityContainer(_:)`), which is also why the container has
/// to be a *sibling*: that flag hides a view's whole accessibility subtree,
/// so a container nested inside the `SKView` would be hidden along with it.
final class AccessibleSKView: SKView {

    /// Everything the container needs to build (or update) one mirror view:
    /// the accessibility properties copied off an `SKNode`, plus the rect the
    /// node occupies in **this view's** coordinate space.
    ///
    /// A value type deliberately: the previous design's hardest bug was
    /// object *lifetime* (unretained `UIAccessibilityElement`s vanishing
    /// between two messages of one accessibility snapshot). Descriptors own
    /// nothing and are consumed immediately, and the objects UIKit sees are
    /// plain retained subviews.
    struct NodeAccessibilityDescriptor: Equatable {
        /// The stable identity the mirror is reused under across refreshes.
        let key: String
        let identifier: String?
        let label: String?
        let traits: UIAccessibilityTraits
        /// The node's rect in `AccessibleSKView`'s own coordinate space,
        /// already made safe to hand to UIKit (never empty, never NaN).
        let viewRect: CGRect
        /// `true` when the node has no visual content of its own and
        /// `viewRect` is a synthesised 1pt rect - a marker such as
        /// `MenuScreenNode`'s `menu.container`. A marker exists to be
        /// *findable*, never to be tapped, so its mirror is kept at the
        /// bottom of the z-order where a real button always beats it.
        let isMarker: Bool
    }

    /// The plain `UIView` the mirrors live in (see the class comment, part 2).
    /// Weak: the container is owned by the view hierarchy, and the reference
    /// here exists only so scene changes can ask it to refresh.
    private weak var containerView: SceneAccessibilityContainerView?

    // MARK: - Container wiring

    /// Hands accessibility for this view's scene over to `container`.
    ///
    /// Called from `SceneAccessibilityContainerView.init(sceneView:)`, so the
    /// two directions of the relationship cannot be wired up by halves.
    ///
    /// `accessibilityElementsHidden` is the load-bearing line: `SKView`'s own
    /// accessibility implementation would otherwise keep answering for this
    /// view with its camera-unaware elements, and it - not our mirrors - is
    /// what the accessibility server consults for an `SKView`. Hiding it
    /// leaves exactly one tree in play, the container's.
    fileprivate func attachAccessibilityContainer(_ container: SceneAccessibilityContainerView) {
        containerView = container
        accessibilityElementsHidden = true
        container.refreshAccessibilityMirrors()
    }

    // MARK: - Scene presentation

    /// A new scene means a new set of mirrors; rebuild them at once rather
    /// than waiting for the next accessibility query, and tell accessibility
    /// clients the tree they may already have read is out of date.
    override func presentScene(_ scene: SKScene?) {
        super.presentScene(scene)
        containerView?.refreshAccessibilityMirrors()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    /// A resize (rotation, most obviously) moves every camera-locked node on
    /// screen, so the mirrors have to follow. The container refreshes on its
    /// own `layoutSubviews()` too; this covers the ordering where SpriteKit
    /// relays out the scene *after* that pass.
    override func layoutSubviews() {
        super.layoutSubviews()
        containerView?.refreshAccessibilityMirrors()
    }

    /// Rebuilds the mirrors now, and tells accessibility clients that the
    /// tree they may already have read is out of date.
    ///
    /// The seam for the scene to announce a change accessibility cannot infer
    /// from a layout pass - today that is `GameScene.transitionScreens(to:)`,
    /// where a whole screen's nodes are swapped without the view resizing.
    /// It exists because the mirrors are no longer rebuilt lazily from an
    /// accessibility query: doing that mutated the hierarchy a driver was
    /// mid-way through resolving an element in, which is what made a
    /// correctly-framed PLAY button report `isHittable == false` (see
    /// `SceneAccessibilityContainerView.hitTest(_:with:)`). Refreshing has to
    /// happen at explicit points *between* snapshots, and this is one of them.
    func refreshSceneAccessibility() {
        guard let containerView else { return }
        containerView.refreshAccessibilityMirrors()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: - Descriptors

    /// One descriptor per accessible node in the presented `GameScene`'s
    /// `uiLayer`, in scene-graph order.
    ///
    /// Side-effect free: it reads the live scene graph and returns values, so
    /// there is nothing for an accessibility snapshot to catch half-written.
    ///
    /// Internal (not private) so `AccessibleSKViewTests` can assert on the
    /// identifiers, labels, traits and geometry without a window or a live
    /// accessibility client.
    func accessibilityDescriptors() -> [NodeAccessibilityDescriptor] {
        guard let gameScene = scene as? GameScene, gameScene.view === self else { return [] }

        var descriptors: [NodeAccessibilityDescriptor] = []

        for node in gameScene.accessibleUINodes() {
            guard let sceneFrame = gameScene.accessibilityFrameInScene(for: node) else { continue }

            let rawRect = viewRect(forSceneRect: sceneFrame, in: gameScene)
            descriptors.append(
                NodeAccessibilityDescriptor(
                    key: cacheKey(for: node),
                    identifier: node.accessibilityIdentifier,
                    label: node.accessibilityLabel,
                    traits: node.accessibilityTraits,
                    viewRect: publishableRect(rawRect),
                    isMarker: isDegenerate(rawRect)
                )
            )
        }

        return descriptors
    }

    /// The stable identity a mirror is reused under. Identifier first (that
    /// is what a driver matches on), then label, then the node's own object
    /// identity so an unlabelled accessible node still gets a stable slot
    /// instead of colliding with every other one.
    private func cacheKey(for node: SKNode) -> String {
        if let identifier = node.accessibilityIdentifier, !identifier.isEmpty {
            return "id:\(identifier)"
        }
        if let label = node.accessibilityLabel, !label.isEmpty {
            return "label:\(label)"
        }
        return "node:\(UInt(bitPattern: ObjectIdentifier(node).hashValue))"
    }

    /// Whether `rect` is one `publishableRect(_:)` has to synthesise a size
    /// for - a marker node's empty (or non-finite) frame.
    private func isDegenerate(_ rect: CGRect) -> Bool {
        guard
            rect.origin.x.isFinite, rect.origin.y.isFinite,
            rect.size.width.isFinite, rect.size.height.isFinite
        else {
            return true
        }
        return rect.size.width <= 0 || rect.size.height <= 0
    }

    /// `rect` made safe to hand to UIKit as a view frame.
    ///
    /// A non-finite rect (SpriteKit can report a null accumulated frame,
    /// whose corners subtract into NaN) is replaced outright - a NaN frame
    /// would corrupt the whole container's layout - and a zero-sized one is
    /// grown to 1pt, because a zero-sized view is dropped from an
    /// accessibility snapshot and a marker such as `menu.container` must
    /// still be findable by identifier. Anything with a real size is returned
    /// untouched, so a button's mirror keeps measuring the button.
    private func publishableRect(_ rect: CGRect) -> CGRect {
        guard
            rect.origin.x.isFinite, rect.origin.y.isFinite,
            rect.size.width.isFinite, rect.size.height.isFinite
        else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        guard rect.size.width <= 0 || rect.size.height <= 0 else { return rect }
        return CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: max(rect.size.width, 1),
            height: max(rect.size.height, 1)
        )
    }

    /// `sceneRect` (scene coordinates, y-up, origin bottom-left) expressed in
    /// this view's own coordinate space (y-down, origin top-left), still
    /// camera-aware.
    ///
    /// This is the rect a mirror view's frame is derived from: the container
    /// converts it into its own space, and UIKit takes it the rest of the way
    /// to screen coordinates itself - which is the only form that stays
    /// correct once the interface rotates.
    func viewRect(forSceneRect sceneRect: CGRect, in scene: SKScene) -> CGRect {
        // Two opposite corners rather than origin + size, because the
        // scene-to-view step flips the y axis: taking min/abs afterwards
        // rebuilds a well-formed rect whichever way round they land.
        let first = convert(CGPoint(x: sceneRect.minX, y: sceneRect.minY), from: scene)
        let second = convert(CGPoint(x: sceneRect.maxX, y: sceneRect.maxY), from: scene)
        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }
}

// MARK: -

/// The invisible `UIView` that stands in for one accessible `SKNode`.
///
/// It draws nothing, and exists so the accessibility server has a **real
/// view** to resolve a point to (see `AccessibleSKView`, parts 2 and 3). It
/// does take part in hit-testing - hittability cannot depend on telling an
/// accessibility lookup apart from a touch - so a real touch that lands on it
/// is *forwarded*, converted into scene space, into
/// `GameScene.dispatchTouch(atScenePoint:)`: the scene remains the sole
/// dispatcher. Everything a driver matches on -
/// identifier, label, traits - is copied off the node it mirrors; the frame
/// is the node's camera-aware rect, so UIKit derives a correct
/// `accessibilityFrame` in any orientation without being told one.
final class SceneAccessibilityMirrorView: UIView {

    /// The `SKNode` identity this mirror is reused for across refreshes
    /// (`AccessibleSKView.NodeAccessibilityDescriptor.key`).
    private(set) var nodeKey: String = ""

    /// `true` while this mirror stands in for a size-less marker node, whose
    /// synthesised 1pt frame must never beat a real button in the z-order.
    private(set) var isMarker: Bool = false

    init() {
        super.init(frame: .zero)
        configureAsMirror()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAsMirror()
    }

    private func configureAsMirror() {
        // Invisible, but *present*: UIKit skips hidden and fully transparent
        // (`alpha == 0`) views when it walks the accessibility hierarchy, so
        // the view stays opaque-to-accessibility while drawing nothing.
        backgroundColor = .clear
        isOpaque = false
        // Take part in hit-testing - `UIView.hitTest(_:with:)` answers `nil`
        // for a non-interactive view and never descends into it, which hides
        // the mirror from the accessibility point lookup `isHittable` is
        // built on. A real touch does then land here, and is forwarded into
        // `GameScene.dispatchTouch(atScenePoint:)` below, so the scene stays
        // the sole dispatcher (see `AccessibleSKView`, part 3).
        isUserInteractionEnabled = true
        // A leaf, not a container: this is the element a driver resolves.
        isAccessibilityElement = true
    }

    /// Brings this mirror in step with `descriptor`, whose `viewRect` is in
    /// `sceneView`'s coordinate space.
    ///
    /// Every write is guarded by an equality check: a refresh runs on every
    /// layout pass, and re-setting an unchanged `frame` would churn
    /// layout (and, worse, invite UIKit to notify accessibility of a change
    /// that never happened) on every one of them.
    func apply(
        _ descriptor: AccessibleSKView.NodeAccessibilityDescriptor,
        from sceneView: UIView
    ) {
        nodeKey = descriptor.key
        isMarker = descriptor.isMarker

        if accessibilityIdentifier != descriptor.identifier {
            accessibilityIdentifier = descriptor.identifier
        }
        if accessibilityLabel != descriptor.label {
            accessibilityLabel = descriptor.label
        }
        if accessibilityTraits != descriptor.traits {
            accessibilityTraits = descriptor.traits
        }

        let target = superview?.convert(descriptor.viewRect, from: sceneView) ?? descriptor.viewRect
        if frame != target {
            frame = target
        }
    }

    // MARK: - Touch forwarding

    /// A mirror is the view UIKit resolves a touch to (it has to be: the same
    /// resolution is what `isHittable` asks about), so it hands the touch back
    /// to the scene explicitly rather than pretending not to be there.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardToScene(touches, phase: .began) else {
            super.touchesBegan(touches, with: event)
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardToScene(touches, phase: .moved) else {
            super.touchesMoved(touches, with: event)
            return
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardToScene(touches, phase: .ended) else {
            super.touchesEnded(touches, with: event)
            return
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard forwardToScene(touches, phase: .cancelled) else {
            super.touchesCancelled(touches, with: event)
            return
        }
    }

    /// `false` when there is nothing to forward to (no container, no touch),
    /// in which case the caller lets the responder chain have the message.
    private func forwardToScene(
        _ touches: Set<UITouch>,
        phase: SceneAccessibilityContainerView.TouchForwardingPhase
    ) -> Bool {
        guard
            let container = superview as? SceneAccessibilityContainerView,
            let touch = touches.first
        else {
            return false
        }
        return container.forwardTouch(atContainerPoint: touch.location(in: container), phase: phase)
    }
}

// MARK: -

/// The plain `UIView` that presents `GameScene`'s UI to UIAccessibility, as a
/// hierarchy of real `SceneAccessibilityMirrorView` subviews.
///
/// This class is the whole point of "part 2" in `AccessibleSKView`'s comment,
/// and it is deliberately as boring as possible: a `UIView` that is not
/// itself an accessibility element and whose accessible children are ordinary
/// subviews. UIKit's *default* behaviour then answers **both** halves of the
/// accessibility contract with no help from us:
///
/// * "what elements are there, and where?" - the query half, which drives
///   `app.descendants(matching: .any)["PLAY"]` resolving at all;
/// * "which element is at this point?" - the hit-test half, which is what
///   XCUITest's `isHittable` actually asks, and the half that stayed broken
///   for as long as we vended synthesized `UIAccessibilityElement`s and
///   re-implemented the point lookup ourselves.
///
/// Installed by `GameViewController` as a *sibling* directly above the
/// `SKView` - not as a child of it, because
/// `AccessibleSKView.attachAccessibilityContainer(_:)` sets
/// `accessibilityElementsHidden` on the `SKView` to silence SpriteKit's
/// competing tree and that flag would hide a nested container too.
final class SceneAccessibilityContainerView: UIView {

    /// The view whose scene this container describes. Weak so the container
    /// cannot keep the render view alive; a `nil` here simply means there is
    /// nothing to mirror.
    private weak var sceneView: AccessibleSKView?

    /// The live mirrors, in subview order: markers first (bottom of the
    /// z-order), then real-sized elements, so an overlap is always resolved
    /// in favour of something tappable.
    private(set) var mirrorViews: [SceneAccessibilityMirrorView] = []

    /// Guards against re-entering a refresh: adding or removing a subview
    /// marks this view as needing layout, and `layoutSubviews()` refreshes.
    private var isRefreshing = false

    /// - Parameter sceneView: the render view whose `GameScene` this
    ///   container mirrors. The back-reference on `sceneView` is wired up
    ///   here too, so the relationship cannot be established by halves.
    init(sceneView: AccessibleSKView) {
        super.init(frame: sceneView.frame)
        self.sceneView = sceneView

        backgroundColor = .clear
        isOpaque = false

        // Interactive on purpose, so UIKit's hit-test walk descends into the
        // mirrors and the accessibility point lookup can resolve one. The
        // touch itself is given back to the scene explicitly, by forwarding
        // it into `GameScene.dispatchTouch(atScenePoint:)` (see
        // `forwardTouch(atContainerPoint:phase:)`) - so the scene still routes
        // every finger exactly as it did before this class existed.
        isUserInteractionEnabled = true

        // A container, never a leaf: a view that reports itself as an
        // accessibility element collapses everything underneath it.
        isAccessibilityElement = false
        accessibilityElementsHidden = false

        sceneView.attachAccessibilityContainer(self)
    }

    /// Not used by the app (the container is only ever created in code), but
    /// required of a `UIView` subclass with its own designated initialiser.
    /// A container with no `sceneView` mirrors nothing rather than crashing.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = true
        isAccessibilityElement = false
    }

    // MARK: - Refresh triggers

    // The *only* places the mirrors are reconciled from inside this class.
    // Both are layout/lifecycle callbacks, i.e. they run between accessibility
    // snapshots; the point lookup and the element query deliberately do not
    // refresh (see `hitTest(_:with:)`). A change no layout pass implies - a
    // screen swap - is announced explicitly by
    // `AccessibleSKView.refreshSceneAccessibility()`.

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshAccessibilityMirrors()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshAccessibilityMirrors()
    }

    // MARK: - Hit testing

    /// Answers **every** hit test with the mirror covering `point` - the same
    /// answer whether accessibility is asking or a finger is arriving.
    ///
    /// Deliberately *not* discriminating on `event` any more, and that is the
    /// fix (see `AccessibleSKView`, part 3): an earlier version returned `nil`
    /// for every event-carrying hit test so a touch fell through to the
    /// `SKView` by transparency, which made hittability depend on telling an
    /// accessibility hit test apart from a touch hit test. It is not
    /// dependable - XCUITest's `isHittable` *is* the point-lookup half of the
    /// accessibility contract, and in a live simulator that lookup does not
    /// reliably arrive down the `event == nil` branch - so PLAY stayed
    /// findable and un-hittable. Answering uniformly makes the point lookup
    /// agree with the frame this same view published, which is all
    /// `isHittable` requires.
    ///
    /// The touch is not stolen by that: a mirror forwards it into
    /// `GameScene.dispatchTouch(atScenePoint:)` (see
    /// `forwardTouch(atContainerPoint:phase:)`), so the scene stays the sole
    /// dispatcher.
    ///
    /// A point no mirror covers resolves to `nil` rather than to the container
    /// itself: a container claiming every point is as wrong as one claiming
    /// none, and letting the empty point fall through to the `SKView` keeps
    /// both the answer and the game world's own touch handling honest.
    /// **The point lookup never rebuilds the tree it is resolving in**, and
    /// that is the fix for the last way this overlay managed to leave PLAY
    /// findable and un-hittable. An earlier version called
    /// `refreshAccessibilityMirrors()` here (and from the
    /// `accessibilityElements` getter), which adds, removes and reorders
    /// subviews and rewrites their frames. `isHittable` compares the element
    /// the *query* half resolved with the element the *point lookup* half
    /// answers; refreshing in the middle of that meant the two halves could
    /// be answered from two different hierarchies - a mirror the driver had
    /// just resolved could be re-inserted at another z-index (or replaced)
    /// between the frame it read and the point it asked about, so the object
    /// coming back was not the object it had asked about and hittability was
    /// `false` even though a synthesized tap at the very same point worked.
    ///
    /// So the lookup is now pure: it resolves `point` against the mirrors
    /// exactly as they stand. Refreshes happen only at explicit lifecycle
    /// points - `layoutSubviews()`, `didMoveToWindow()`,
    /// `AccessibleSKView.presentScene(_:)` / `layoutSubviews()`,
    /// `GameViewController.viewDidLayoutSubviews()` and
    /// `GameScene.transitionScreens(to:)` - all of which happen *between*
    /// accessibility snapshots rather than inside one.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }

        // Topmost sibling wins, which is UIKit's own rule and the one the
        // marker-below-buttons z-order is built on. Walked explicitly rather
        // than through `super` so the answer depends on nothing but the
        // mirrors themselves.
        for case let mirror as SceneAccessibilityMirrorView in subviews.reversed() {
            guard mirror.isUserInteractionEnabled, !mirror.isHidden, mirror.alpha > 0.01 else { continue }
            if mirror.point(inside: mirror.convert(point, from: self), with: event) {
                return mirror
            }
        }
        return nil
    }

    // MARK: - Touch forwarding

    /// Which message of a touch sequence is being handed back to the scene.
    enum TouchForwardingPhase {
        case began
        case moved
        case ended
        case cancelled
    }

    /// Hands a real touch that landed on a mirror back to the scene, in the
    /// scene's own coordinate space.
    ///
    /// `point` is in this container's coordinates; it is converted container
    /// -> render view -> scene, which is the same path (and the exact inverse
    /// of the geometry `AccessibleSKView` publishes) that a driver's
    /// element-driven tap walks. `GameScene` dispatches on the *began*
    /// message only, so that is the one delivered to
    /// `dispatchTouch(atScenePoint:)`; the later messages of the sequence are
    /// absorbed here rather than escaping up the responder chain, and this is
    /// the single seam to extend when the scene grows drag handling.
    ///
    /// Returns `false` when there is no presented `GameScene` to forward to,
    /// so the caller can fall back to the responder chain.
    @discardableResult
    func forwardTouch(atContainerPoint point: CGPoint, phase: TouchForwardingPhase) -> Bool {
        guard let sceneView, let scene = sceneView.scene as? GameScene else { return false }

        switch phase {
        case .began:
            let pointInSceneView = sceneView.convert(point, from: self)
            scene.dispatchTouch(atScenePoint: sceneView.convert(pointInSceneView, to: scene))
        case .moved, .ended, .cancelled:
            break
        }
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              forwardTouch(atContainerPoint: touch.location(in: self), phase: .began) else {
            super.touchesBegan(touches, with: event)
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              forwardTouch(atContainerPoint: touch.location(in: self), phase: .moved) else {
            super.touchesMoved(touches, with: event)
            return
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              forwardTouch(atContainerPoint: touch.location(in: self), phase: .ended) else {
            super.touchesEnded(touches, with: event)
            return
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              forwardTouch(atContainerPoint: touch.location(in: self), phase: .cancelled) else {
            super.touchesCancelled(touches, with: event)
            return
        }
    }

    // MARK: - Mirroring

    // `accessibilityElements` is deliberately **not** overridden.
    //
    // An earlier version overrode its getter to call
    // `refreshAccessibilityMirrors()`, on the reasoning that UIKit reads it
    // once per accessibility snapshot and that is the cheapest place to keep
    // the mirrors current. It is also the worst: the getter is read *during*
    // the very snapshot whose elements are being resolved, so rebuilding
    // there mutated the hierarchy an out-of-process driver was mid-way
    // through reading - and `isHittable`, which compares the element resolved
    // from a frame with the element answered at that frame's point, went
    // `false` for a PLAY button whose pixels were in exactly the right place.
    //
    // The accessible children *are* the subviews, so leaving this property
    // alone lets UIKit walk them natively (query half) and resolve a point to
    // one of them by z-order (hit-test half) with no help from us. Refreshes
    // are driven from lifecycle points between snapshots instead - see
    // `hitTest(_:with:)` for the list.

    /// Reconciles the mirror subviews with the presented scene's accessible
    /// nodes: reusing a mirror per node identity, updating its properties and
    /// frame, dropping any mirror whose node is gone, and keeping markers
    /// below real elements in the z-order.
    ///
    /// Idempotent, and deliberately mutation-free when nothing has changed:
    /// it runs on every layout pass, and a refresh that reshuffled subviews
    /// each time would keep invalidating the snapshot an accessibility client
    /// is reading.
    ///
    /// Called only from lifecycle points that sit *between* accessibility
    /// snapshots (see `hitTest(_:with:)`), never from the point lookup or an
    /// element query - rebuilding the hierarchy while it is being resolved is
    /// precisely what made a correctly-framed PLAY button un-hittable.
    func refreshAccessibilityMirrors() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let sceneView else {
            removeAllMirrors()
            return
        }

        let descriptors = sceneView.accessibilityDescriptors()

        // Markers first, so a real-sized element is always *above* a
        // size-less marker's synthesised 1pt rect and wins the point lookup:
        // `menu.container` sits inside the menu, and answering the marker
        // where PLAY is would make PLAY unhittable just as surely as
        // answering nothing at all.
        let ordered = descriptors.filter(\.isMarker) + descriptors.filter { !$0.isMarker }

        var existing: [String: SceneAccessibilityMirrorView] = [:]
        for mirror in mirrorViews { existing[mirror.nodeKey] = mirror }

        var live: [SceneAccessibilityMirrorView] = []
        var claimed: Set<String> = []
        for descriptor in ordered {
            // One mirror per node identity. Two nodes sharing an identifier
            // would otherwise claim the same mirror twice and land in the
            // subview list twice, which no z-order can then describe.
            guard claimed.insert(descriptor.key).inserted else { continue }
            let mirror = existing[descriptor.key] ?? SceneAccessibilityMirrorView()
            if mirror.superview !== self { addSubview(mirror) }
            mirror.apply(descriptor, from: sceneView)
            live.append(mirror)
        }

        let liveKeys = Set(live.map(\.nodeKey))
        for mirror in mirrorViews where !liveKeys.contains(mirror.nodeKey) {
            mirror.removeFromSuperview()
        }

        // Only touch the z-order when it is actually wrong: reordering
        // subviews is a hierarchy mutation, and this method runs on every
        // layout pass.
        if mirrorSubviewOrder() != live.map(ObjectIdentifier.init) {
            for (index, mirror) in live.enumerated() {
                insertSubview(mirror, at: index)
            }
        }

        mirrorViews = live
    }

    private func mirrorSubviewOrder() -> [ObjectIdentifier] {
        subviews.compactMap { $0 as? SceneAccessibilityMirrorView }.map(ObjectIdentifier.init)
    }

    private func removeAllMirrors() {
        for mirror in mirrorViews { mirror.removeFromSuperview() }
        mirrorViews = []
    }
}
