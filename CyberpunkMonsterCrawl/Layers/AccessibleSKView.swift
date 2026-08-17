import SpriteKit
import UIKit

/// The `SKView` subclass the app hosts `GameScene` in, so that every
/// accessible UI node publishes a **correct screen-space
/// `accessibilityFrame`** *and* is actually reachable by an out-of-process
/// accessibility client (XCUITest, VoiceOver, the scripted runtime probe).
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
/// precisely so the UI stays camera-locked. The synthesized touch therefore
/// landed somewhere that was not the button, `touchesBegan(_:with:)` never
/// saw it, `stateMachine.transition(to: .gameplay)` never fired, and the
/// probe reported "tapped PLAY, screen stayed on the menu".
///
/// ## The fix, part 1: publish frames the scene agrees with
///
/// Publish the elements ourselves, with frames computed through the *same*
/// coordinate path `routeTouch(at:)` trusts for real touches:
///
/// 1. `GameScene.accessibilityFrameInScene(for:)` - the node's accumulated
///    frame converted up to scene space, which is the algebraic inverse of
///    the `uiLayer.convert(_:from: self)` + `atPoint(_:)` walk the scene
///    hit-tests with.
/// 2. `SKView.convert(_:from:)` - scene space to view space, the inverse of
///    the conversion SpriteKit uses to give `UITouch.location(in:)` its
///    value (and camera-aware, which is the step SpriteKit's implicit support
///    gets wrong).
/// 3. View space to *screen* space, the space `accessibilityFrame` is
///    documented in.
///
/// Because the published frame is derived from the inverse of the hit test,
/// an element-driven tap and the scene's own routing cannot disagree.
/// `AccessibleSKViewTests` pins that agreement directly.
///
/// ## The fix, part 2: be a container whose elements survive the query
///
/// Publishing the right *numbers* is necessary but not sufficient - the
/// elements also have to still be there when the accessibility server comes
/// back to read them. Three things are load-bearing here, and each one on its
/// own is enough to make the whole tree vanish from an XCUITest snapshot
/// while every unit test in `AccessibleSKViewTests` stays green (those call
/// `publishedAccessibilityElements()` directly, in-process, inside one
/// autorelease pool - the one situation where all three defects are
/// invisible):
///
/// * **The elements must be owned.** `UIAccessibilityElement` holds its
///   `accessibilityContainer` weakly and a container does *not* retain the
///   elements it vends. Building a fresh, unretained array on every query
///   means the objects UIKit was handed can be gone before the next message
///   in the same snapshot pass arrives, so the container resolves to a node
///   with no live children. `elementCache` gives them an owner, and reusing
///   the same instance for the same node keeps element *identity* stable
///   across queries - which is what `index(ofAccessibilityElement:)`, and
///   therefore VoiceOver focus and XCUITest element resolution, are built on.
///   Freshness is preserved by rewriting every reused element's properties
///   from the live scene graph on each query and dropping any key the walk no
///   longer produces, so a screen swap (`GameScene.transitionScreens(to:)`),
///   a rotation (`didChangeSize(_:)`) or a camera move still cannot leave a
///   stale frame behind.
///
/// * **The view must stay a *container*, not a leaf.** UIKit only looks at
///   `accessibilityElements` when the view itself reports
///   `isAccessibilityElement == false`; if anything up the `SKView` chain
///   answers `true`, the whole subtree collapses into one unlabelled element
///   and nothing we publish is ever asked for. `isAccessibilityElement` is
///   overridden below to answer `false` for as long as we have something to
///   publish rather than trusting the inherited value.
///
/// * **A published frame must not be degenerate.** An accessibility snapshot
///   is entitled to drop a zero-sized element, and a marker node such as
///   `MenuScreenNode`'s `menu.container` has no visual content, so its
///   accumulated frame is legitimately empty. Such elements are published at
///   a minimum 1pt size so they remain *findable by identifier* (which is all
///   a marker is for) instead of being culled.
///
/// The frame is handed to UIKit as `accessibilityFrameInContainerSpace`
/// whenever this view is in a window. That property takes the rect in *this
/// view's* coordinate space and lets UIKit do the view -> screen step itself,
/// which is the only form that is correct in every interface orientation:
/// `AppLaunchAndRotationUITests` rotates to `.landscapeLeft` and then taps
/// `menu.playButton` by identifier, i.e. it drives exactly this element-frame
/// path in the orientation where window != screen. Off-window (unit tests, a
/// view mid-teardown) there is no screen mapping to ask for, so
/// `screenFrame(forSceneRect:in:)`'s view-space fallback is written straight
/// into `accessibilityFrame` and the element still measures the button.
///
/// ## The fix, part 3: answer the hit test, not just the query
///
/// Publishing elements only closes the *query* half of the container
/// contract - "what elements do you have, and where are they?". There is a
/// second, independent half: "which element is at this point?", asked through
/// `accessibilityHitTest(_:event:)`. XCUITest's `isHittable` is defined in
/// terms of that question: it resolves an element's activation point from the
/// frame we publish, asks the app which accessibility element sits there, and
/// requires the *same* element back. Left unoverridden, that question is
/// answered by `SKView`'s inherited SpriteKit implementation, which knows
/// nothing about the elements this class vends - it is the camera-unaware
/// path this class exists to bypass - so it can never hand one of them back
/// and `isHittable` stays `false` even though the frame is exactly right.
/// That is a uniquely nasty failure mode, because the element is *found*
/// (`app.descendants(matching: .any)["PLAY"]` resolves) and a synthesized tap
/// at those coordinates even works; only the hittability predicate fails.
/// `accessibilityHitTest(_:event:)` below therefore answers from the same
/// published rects, so the two halves cannot disagree.
final class AccessibleSKView: SKView {

    /// The elements handed out by `publishedAccessibilityElements()`, keyed
    /// by the stable identity of the node each one mirrors.
    ///
    /// This property is what makes the published elements *owned*: without a
    /// strong reference living here they are unretained temporaries (see the
    /// class comment), and an accessibility client that comes back for them a
    /// message later finds nothing.
    private var elementCache: [String: UIAccessibilityElement] = [:]

    /// One published element together with the **view-space** rect it was
    /// published with, in scene-graph order.
    ///
    /// This is the other half of the container contract (see
    /// `accessibilityHitTest(_:event:)`): publishing a frame answers "where is
    /// this element?", hit testing answers "which element is at this point?",
    /// and an out-of-process driver needs *both* answers to agree before it
    /// will call an element hittable.
    private struct PublishedElement {
        let element: UIAccessibilityElement
        /// The rect handed to UIKit, in this view's own coordinate space.
        let viewRect: CGRect
        /// `true` when the node had no size of its own and `publishableRect(_:)`
        /// synthesised a 1pt rect for it (a marker such as `menu.container`).
        /// Such a rect exists to keep the element findable, not to be tapped,
        /// so a real-sized element under the same point wins.
        let isMarker: Bool
    }

    /// The elements from the most recent publish, with the rects they were
    /// published with - the lookup table `accessibilityHitTest(_:event:)`
    /// answers from.
    private var publishedElements: [PublishedElement] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAsAccessibilityContainer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAsAccessibilityContainer()
    }

    private func configureAsAccessibilityContainer() {
        // Both are UIView defaults, but they are the two flags that silently
        // erase everything this class publishes, so they are stated rather
        // than assumed.
        isAccessibilityElement = false
        accessibilityElementsHidden = false
    }

    // MARK: - UIAccessibilityContainer

    /// A container, never a leaf, for as long as there is something of ours
    /// to publish.
    ///
    /// UIKit consults `accessibilityElements` only on a view that is *not*
    /// itself an accessibility element. Answering `true` here - from any
    /// point in the `SKView` inheritance chain - collapses the menu into a
    /// single unlabelled element and makes this entire class dead code, so
    /// the answer is computed rather than inherited.
    override var isAccessibilityElement: Bool {
        get {
            if publishedAccessibilityElements() != nil { return false }
            return super.isAccessibilityElement
        }
        set { super.isAccessibilityElement = newValue }
    }

    /// The modern container hook, and the one XCUITest's snapshotting reads.
    ///
    /// Falls back to `super` when there is nothing of ours to publish (no
    /// `GameScene` presented yet, or an empty `uiLayer`) rather than
    /// returning an empty array, so a state this class does not understand
    /// leaves SpriteKit's own accessibility behaviour intact instead of
    /// blanking the tree.
    override var accessibilityElements: [Any]? {
        get {
            if let elements = publishedAccessibilityElements() {
                return elements
            }
            return super.accessibilityElements
        }
        set { super.accessibilityElements = newValue }
    }

    /// Overridden alongside `accessibilityElements` deliberately. `SKView`
    /// ships its own container implementation, and UIKit is free to reach for
    /// either the array above or this older count/index triplet; answering
    /// both from one source removes any question of which one wins - and with
    /// it the risk that this whole class ends up dead code because UIKit took
    /// the other branch.
    override func accessibilityElementCount() -> Int {
        guard let elements = publishedAccessibilityElements() else {
            return super.accessibilityElementCount()
        }
        return elements.count
    }

    override func accessibilityElement(at index: Int) -> Any? {
        guard let elements = publishedAccessibilityElements() else {
            return super.accessibilityElement(at: index)
        }
        guard elements.indices.contains(index) else { return nil }
        return elements[index]
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        guard let elements = publishedAccessibilityElements() else {
            return super.index(ofAccessibilityElement: element)
        }
        guard let candidate = element as? UIAccessibilityElement else { return NSNotFound }

        // Identity first, then identifier/label. Identity is now the common
        // case (elements are cached and reused per node), which is what keeps
        // VoiceOver focus and XCUITest's element resolution stable; the
        // identifier/label fallback still covers an instance produced before
        // a screen swap rebuilt the cache.
        let match = elements.firstIndex { published in
            if published === candidate { return true }
            if let identifier = published.accessibilityIdentifier,
               identifier == candidate.accessibilityIdentifier {
                return true
            }
            if let label = published.accessibilityLabel, label == candidate.accessibilityLabel {
                return true
            }
            return false
        }
        return match ?? NSNotFound
    }

    // MARK: - Scene presentation

    /// A new scene means a new element set; drop the cache so nothing from
    /// the previous scene can be handed out, and tell accessibility clients
    /// the tree they may already have read is out of date.
    override func presentScene(_ scene: SKScene?) {
        super.presentScene(scene)
        elementCache.removeAll()
        publishedElements.removeAll()
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: - Element construction

    /// One `UIAccessibilityElement` per accessible node in the presented
    /// `GameScene`'s `uiLayer`, or `nil` when there is nothing to publish.
    ///
    /// Elements are reused across calls (see `elementCache`) but their
    /// properties are rewritten from the live scene graph every time, so a
    /// screen swap, a rotation or a camera move can never leave a stale frame
    /// behind - a stale frame is the original defect wearing a different hat.
    ///
    /// Internal (not private) so `AccessibleSKViewTests` can assert on the
    /// published identifiers, labels, traits and frame sizes without a
    /// window or a live accessibility client.
    func publishedAccessibilityElements() -> [UIAccessibilityElement]? {
        guard let gameScene = scene as? GameScene, gameScene.view === self else { return nil }

        var live: [String: UIAccessibilityElement] = [:]
        var ordered: [UIAccessibilityElement] = []
        var hitTargets: [PublishedElement] = []

        for node in gameScene.accessibleUINodes() {
            guard let sceneFrame = gameScene.accessibilityFrameInScene(for: node) else { continue }

            let key = cacheKey(for: node)
            let element = elementCache[key] ?? UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityContainer = self
            element.accessibilityIdentifier = node.accessibilityIdentifier
            element.accessibilityLabel = node.accessibilityLabel
            element.accessibilityTraits = node.accessibilityTraits
            let rawViewRect = viewRect(forSceneRect: sceneFrame, in: gameScene)
            let publishedRect = applyFrame(sceneRect: sceneFrame, to: element, in: gameScene)

            live[key] = element
            ordered.append(element)
            hitTargets.append(
                PublishedElement(
                    element: element,
                    viewRect: publishedRect,
                    isMarker: isDegenerate(rawViewRect)
                )
            )
        }

        // Assigning (rather than merging) drops every key the walk no longer
        // produces, so a swapped-out screen releases its elements.
        elementCache = live
        publishedElements = hitTargets

        return ordered.isEmpty ? nil : ordered
    }

    // MARK: - UIAccessibility hit testing

    /// The element at `point`, so an out-of-process driver's hittability
    /// check resolves to the *same* element whose frame it aimed at.
    ///
    /// Answered from the rects published by
    /// `publishedAccessibilityElements()` rather than from `SKView`'s
    /// inherited implementation, which knows nothing about them (see the
    /// class comment, "part 3"). Scene-graph order is walked in reverse so a
    /// node drawn later - i.e. on top - wins, and a size-less marker's
    /// synthesised 1pt rect only wins when nothing real covers the point:
    /// `menu.container` sits at the menu's centre, which is inside the PLAY
    /// button, and answering the marker there would make PLAY unhittable
    /// just as surely as answering nothing at all.
    ///
    /// Falls back to `super` when nothing of ours is under the point, so a
    /// state this class does not understand keeps SpriteKit's own behaviour.
    override func accessibilityHitTest(_ point: CGPoint, event: UIEvent?) -> Any? {
        // Republish first: the elements (and their rects) must reflect the
        // live scene graph, exactly as they do for a query.
        guard publishedAccessibilityElements() != nil else {
            return inheritedAccessibilityHitTest(point, event: event)
        }

        if let hit = publishedElement(atViewPoint: point) { return hit }

        // `accessibilityHitTest(_:event:)` takes its point in the receiver's
        // own coordinate space, like `hitTest(_:with:)`. Should a caller hand
        // over a window-space point instead, converting it costs nothing and
        // is a no-op for this app's full-bleed window.
        if window != nil {
            let converted = convert(point, from: nil)
            if converted != point, let hit = publishedElement(atViewPoint: converted) {
                return hit
            }
        }

        return inheritedAccessibilityHitTest(point, event: event)
    }

    /// `SKView`'s own answer to the hit test, for the cases where nothing of
    /// ours is under the point.
    ///
    /// The selector's only Swift spelling is `accessibilityHitTest(_:event:)`
    /// (`withEvent:` was obsoleted in Swift 3, `with:` never existed), and it
    /// carries an iOS 18 availability annotation - so while the *override*
    /// needs no gate, a `super` call does. Below iOS 18 there is no callable
    /// inherited implementation to defer to, and `nil` is the correct answer
    /// anyway: it means "no accessibility element of mine is at this point",
    /// which is exactly the state this path is reached in.
    private func inheritedAccessibilityHitTest(_ point: CGPoint, event: UIEvent?) -> Any? {
        if #available(iOS 18.0, *) {
            return super.accessibilityHitTest(point, event: event)
        }
        return nil
    }

    /// The topmost published element whose view-space rect contains `point`,
    /// preferring a real-sized element over a marker's synthesised 1pt rect.
    private func publishedElement(atViewPoint point: CGPoint) -> UIAccessibilityElement? {
        var marker: UIAccessibilityElement?

        for published in publishedElements.reversed() where published.viewRect.contains(point) {
            guard published.isMarker else { return published.element }
            if marker == nil { marker = published.element }
        }

        return marker
    }

    /// The stable identity an element is cached under. Identifier first (that
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

    /// Writes `sceneRect` onto `element` in whichever form UIKit can act on.
    ///
    /// In a window the rect is handed over as
    /// `accessibilityFrameInContainerSpace` - this view's own coordinate
    /// space - and UIKit performs the view -> screen step itself, which is
    /// the only form that stays correct once the interface rotates. Off
    /// window there is no screen mapping to ask for, so
    /// `screenFrame(forSceneRect:in:)`'s view-space fallback goes straight
    /// into `accessibilityFrame`.
    ///
    /// Returns the rect in **view space** whichever branch was taken - the
    /// number `accessibilityHitTest(_:event:)` matches a point against, so the
    /// frame published and the frame hit-tested are one value, not two.
    @discardableResult
    private func applyFrame(
        sceneRect: CGRect,
        to element: UIAccessibilityElement,
        in scene: SKScene
    ) -> CGRect {
        let rect = publishableRect(viewRect(forSceneRect: sceneRect, in: scene))
        if window != nil {
            element.accessibilityFrameInContainerSpace = rect
        } else {
            element.accessibilityFrame =
                publishableRect(screenFrame(forSceneRect: sceneRect, in: scene))
        }
        return rect
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

    /// `rect` made safe to hand to UIAccessibility.
    ///
    /// A non-finite rect (SpriteKit can report a null accumulated frame,
    /// whose corners subtract into NaN) is replaced outright, and a
    /// zero-sized one is grown to 1pt: an accessibility snapshot is entitled
    /// to cull a degenerate element, and a marker node such as
    /// `menu.container` legitimately has no size but must still be findable
    /// by identifier. Anything with a real size is returned untouched, so a
    /// button's published frame keeps measuring the button.
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

    /// Converts `sceneRect` (scene coordinates, y-up, origin bottom-left)
    /// into **screen** coordinates - `UIScreen.fixedCoordinateSpace`, y-down,
    /// portrait-up origin - which is the space `accessibilityFrame` is
    /// defined in.
    ///
    /// The view -> screen step goes through
    /// `UIAccessibility.convertToScreenCoordinates(_:in:)` rather than
    /// `convert(_:to: nil)`: the latter answers in *window* coordinates,
    /// which only coincide with screen coordinates while the interface is
    /// portrait and the window is full-bleed.
    ///
    /// Internal so the conversion can be exercised directly by tests.
    func screenFrame(forSceneRect sceneRect: CGRect, in scene: SKScene) -> CGRect {
        let rect = viewRect(forSceneRect: sceneRect, in: scene)

        // A view with no window has no screen mapping to speak of, and
        // `UIAccessibility.convertToScreenCoordinates(_:in:)` goes through
        // the window to reach the screen - so off-window it can only answer
        // a degenerate rect. Return the view-space rect instead: it is the
        // same number the windowed conversion produces for the app's single
        // full-bleed portrait window, and it keeps an off-window view (unit
        // tests, a view mid-teardown) publishing a frame that still measures
        // the button rather than an empty one.
        guard window != nil else { return rect }

        return UIAccessibility.convertToScreenCoordinates(rect, in: self)
    }

    /// The scene -> view half of `screenFrame(forSceneRect:in:)`: `sceneRect`
    /// expressed in this view's own coordinate space (y-down, origin
    /// top-left), still camera-aware.
    ///
    /// This is also the rect published as
    /// `accessibilityFrameInContainerSpace` in the windowed case, which is
    /// exactly what that property is documented to take.
    ///
    /// Split out from the screen conversion so tests can round-trip a
    /// published frame back into scene space with `convert(_:to: scene)`
    /// without a window and without having to invert UIKit's
    /// orientation-dependent screen mapping - the view-space rect is the
    /// number the round trip is actually about.
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
