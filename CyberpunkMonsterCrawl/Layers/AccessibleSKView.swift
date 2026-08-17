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
/// 3. View space to the space UIKit wants the frame in.
///
/// Because the published frame is derived from the inverse of the hit test,
/// an element-driven tap and the scene's own routing cannot disagree.
/// `AccessibleSKViewTests` pins that agreement directly.
///
/// ## The fix, part 2: elements that survive the query
///
/// Publishing the right *numbers* is necessary but not sufficient - the
/// elements also have to still be there when the accessibility server comes
/// back to read them. Two things are load-bearing here, and each one on its
/// own is enough to make the whole tree vanish from an XCUITest snapshot
/// while every unit test stays green (those call
/// `publishedAccessibilityElements()` directly, in-process, inside one
/// autorelease pool - the one situation where both defects are invisible):
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
///   from the live scene graph on each publish and dropping any key the walk
///   no longer produces, so a screen swap (`GameScene.transitionScreens(to:)`),
///   a rotation (`didChangeSize(_:)`) or a camera move still cannot leave a
///   stale frame behind.
///
/// * **A published frame must not be degenerate.** An accessibility snapshot
///   is entitled to drop a zero-sized element, and a marker node such as
///   `MenuScreenNode`'s `menu.container` has no visual content, so its
///   accumulated frame is legitimately empty. Such elements are published at
///   a minimum 1pt size so they remain *findable by identifier* (which is all
///   a marker is for) instead of being culled.
///
/// ## The fix, part 3: vend the elements from a plain `UIView`, not from here
///
/// Publishing elements only closes the *query* half of the container
/// contract - "what elements do you have, and where are they?". There is a
/// second, independent half: "which element is at this point?". XCUITest's
/// `isHittable` is defined in terms of *that* question: it resolves an
/// element's activation point from the frame we publish, asks the app which
/// accessibility element sits there, and requires the **same** element back.
/// That is a uniquely nasty failure mode when it goes wrong, because the
/// element is still *found* (`app.descendants(matching: .any)["PLAY"]`
/// resolves) and a synthesized tap at those coordinates even works; only the
/// hittability predicate fails - which is exactly how
/// `CyberpunkMonsterCrawlUITests` failed, one line after finding PLAY.
///
/// An earlier attempt answered that second question from *this* class, by
/// overriding `accessibilityHitTest(_:event:)` on the `SKView` subclass. It
/// does not work: `SKView` ships its own (camera-unaware) accessibility
/// implementation, and on the simulator the accessibility server keeps
/// consulting *that* one for this view rather than our override, so it hands
/// back elements that are not the ones we vend and `isHittable` stays
/// `false` however correct our frames are.
///
/// So the container moves **off** `SKView` - off the one class whose
/// inherited implementation competes with ours.
/// `SceneAccessibilityContainerView` is a vanilla `UIView` sibling installed
/// above the `SKView` by `GameViewController`, it vends the elements this
/// class computes, and UIKit's *default* `UIView` behaviour answers **both**
/// halves of the contract from `accessibilityElements` and their frames. No
/// recent, private or SpriteKit-owned hook is involved. SpriteKit's competing
/// tree is silenced with `accessibilityElementsHidden` on the `SKView` (see
/// `attachAccessibilityContainer(_:)`), which is also why the container has
/// to be a *sibling*: that flag hides a view's whole accessibility subtree,
/// so a container nested inside the `SKView` would be hidden along with it.
///
/// Frames are handed over as `accessibilityFrameInContainerSpace` - the rect
/// in the *container view's* coordinate space - and UIKit performs the
/// view -> screen step itself, which is the only form that is correct in
/// every interface orientation: `AppLaunchAndRotationUITests` rotates to
/// `.landscapeLeft` and then taps `menu.playButton` by identifier, i.e. it
/// drives exactly this element-frame path in the orientation where
/// window != screen. Off-window (unit tests, a view mid-teardown) there is no
/// screen mapping to ask for, so `screenFrame(forSceneRect:in:)`'s view-space
/// fallback is written straight into `accessibilityFrame` and the element
/// still measures the button.
final class AccessibleSKView: SKView {

    /// The elements handed out by `publishedAccessibilityElements()`, keyed
    /// by the stable identity of the node each one mirrors.
    ///
    /// This property is what makes the published elements *owned*: without a
    /// strong reference living here they are unretained temporaries (see the
    /// class comment), and an accessibility client that comes back for them a
    /// message later finds nothing.
    private var elementCache: [String: UIAccessibilityElement] = [:]

    /// One published element together with the **container-space** rect it
    /// was published with, in scene-graph order.
    private struct PublishedElement {
        /// The `elementCache` key the element is owned under.
        let key: String
        let element: UIAccessibilityElement
        /// The rect handed to UIKit, in the container view's coordinate space.
        let containerRect: CGRect
        /// `true` when the node had no size of its own and `publishableRect(_:)`
        /// synthesised a 1pt rect for it (a marker such as `menu.container`).
        /// Such a rect exists to keep the element findable, not to be tapped,
        /// so a real-sized element under the same point wins.
        let isMarker: Bool
    }

    /// The elements from the most recent publish, with the rects they were
    /// published with - the lookup table the container's hit test answers
    /// from when UIKit routes one to us.
    private var publishedElements: [PublishedElement] = []

    /// The plain `UIView` this view's elements are vended from (see the class
    /// comment, part 3). Weak: the container is owned by the view hierarchy,
    /// and the reference here exists only so the elements can be built with
    /// the right container and the right coordinate space.
    private weak var containerView: SceneAccessibilityContainerView?

    // MARK: - Container wiring

    /// Hands accessibility for this view's scene over to `container`.
    ///
    /// Called from `SceneAccessibilityContainerView.init(sceneView:)`, so the
    /// two directions of the relationship cannot be wired up by halves.
    ///
    /// `accessibilityElementsHidden` is the load-bearing line: `SKView`'s own
    /// accessibility implementation would otherwise keep answering for this
    /// view with its camera-unaware elements, and it - not our container - is
    /// what the accessibility server consults for an `SKView`. Hiding it
    /// leaves exactly one tree in play, the container's.
    fileprivate func attachAccessibilityContainer(_ container: SceneAccessibilityContainerView) {
        containerView = container
        accessibilityElementsHidden = true
        elementCache.removeAll()
        publishedElements.removeAll()
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
        guard let published = publish() else { return nil }
        return published.map(\.element)
    }

    /// Recomputes the element set and *then* stores it.
    ///
    /// Compute and publish are deliberately split: `makePublishedElements()`
    /// reads the scene graph and the element cache but mutates nothing, and
    /// this method performs the one assignment at the end. UIKit asks a
    /// container several questions per snapshot pass (elements, count,
    /// index, hit test), and a getter that rewrote `elementCache` half way
    /// through its own answer used to be able to hand out one set of objects
    /// and keep a different one.
    @discardableResult
    private func publish() -> [PublishedElement]? {
        guard let published = makePublishedElements() else { return nil }

        // Assigning (rather than merging) drops every key the walk no longer
        // produces, so a swapped-out screen releases its elements.
        var live: [String: UIAccessibilityElement] = [:]
        for entry in published { live[entry.key] = entry.element }
        elementCache = live
        publishedElements = published

        return published
    }

    /// The element set the live scene graph implies, or `nil` when there is
    /// nothing of ours to publish (no `GameScene` presented, or an empty
    /// `uiLayer`). Side-effect-free apart from writing the properties of the
    /// elements it vends.
    private func makePublishedElements() -> [PublishedElement]? {
        guard let gameScene = scene as? GameScene, gameScene.view === self else { return nil }

        var published: [PublishedElement] = []

        for node in gameScene.accessibleUINodes() {
            guard let sceneFrame = gameScene.accessibilityFrameInScene(for: node) else { continue }

            let key = cacheKey(for: node)
            let element = elementCache[key] ?? UIAccessibilityElement(accessibilityContainer: elementContainer)
            element.accessibilityContainer = elementContainer
            element.accessibilityIdentifier = node.accessibilityIdentifier
            element.accessibilityLabel = node.accessibilityLabel
            element.accessibilityTraits = node.accessibilityTraits
            let rawViewRect = viewRect(forSceneRect: sceneFrame, in: gameScene)
            let containerRect = applyFrame(sceneRect: sceneFrame, to: element, in: gameScene)

            published.append(
                PublishedElement(
                    key: key,
                    element: element,
                    containerRect: containerRect,
                    isMarker: isDegenerate(rawViewRect)
                )
            )
        }

        return published.isEmpty ? nil : published
    }

    /// The object UIKit is told owns the published elements: the plain
    /// `UIView` container when one is installed, this view otherwise (a bare
    /// `AccessibleSKView` in a unit test).
    private var elementContainer: UIView {
        containerView ?? self
    }

    // MARK: - Hit testing support

    /// The topmost published element whose rect contains `point` (given in
    /// the container view's coordinate space), preferring a real-sized
    /// element over a marker's synthesised 1pt rect.
    ///
    /// The published set is refreshed first, so the answer reflects the same
    /// live scene graph a query would see. Scene-graph order is walked in
    /// reverse so a node drawn later - i.e. on top - wins, and a size-less
    /// marker only wins when nothing real covers the point: `menu.container`
    /// sits at the menu's centre, which is inside the PLAY button, and
    /// answering the marker there would make PLAY unhittable just as surely
    /// as answering nothing at all.
    fileprivate func publishedElement(atContainerPoint point: CGPoint) -> UIAccessibilityElement? {
        guard let published = publish() else { return nil }

        var marker: UIAccessibilityElement?

        for entry in published.reversed() where entry.containerRect.contains(point) {
            guard entry.isMarker else { return entry.element }
            if marker == nil { marker = entry.element }
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
    /// `accessibilityFrameInContainerSpace` - the container view's own
    /// coordinate space - and UIKit performs the view -> screen step itself,
    /// which is the only form that stays correct once the interface rotates.
    /// Off window there is no screen mapping to ask for, so
    /// `screenFrame(forSceneRect:in:)`'s view-space fallback goes straight
    /// into `accessibilityFrame`.
    ///
    /// Returns the rect in **container space** whichever branch was taken -
    /// the number `publishedElement(atContainerPoint:)` matches a point
    /// against, so the frame published and the frame hit-tested are one
    /// value, not two.
    @discardableResult
    private func applyFrame(
        sceneRect: CGRect,
        to element: UIAccessibilityElement,
        in scene: SKScene
    ) -> CGRect {
        let rect = publishableRect(viewRect(forSceneRect: sceneRect, in: scene))
        let container = elementContainer
        let containerRect = container === self ? rect : container.convert(rect, from: self)

        if container.window != nil {
            element.accessibilityFrameInContainerSpace = containerRect
        } else {
            element.accessibilityFrame =
                publishableRect(screenFrame(forSceneRect: sceneRect, in: scene))
        }
        return containerRect
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
    /// `accessibilityFrameInContainerSpace` (converted into the container
    /// view's space, which is the same rect while the container is installed
    /// edge to edge over this view).
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

// MARK: -

/// The plain `UIView` that presents `GameScene`'s UI to UIAccessibility.
///
/// This class is the whole point of "part 3" in `AccessibleSKView`'s comment,
/// and it is deliberately as boring as possible: a `UIView` that is *not*
/// itself an accessibility element and whose `accessibilityElements` are the
/// ones `AccessibleSKView` computes. UIKit's default container behaviour then
/// answers **both** halves of the accessibility contract from those elements
/// and their frames:
///
/// * "what elements are there, and where?" - the query half, which drives
///   `app.descendants(matching: .any)["PLAY"]` resolving at all;
/// * "which element is at this point?" - the hit-test half, which is what
///   XCUITest's `isHittable` actually asks, and the half that stayed broken
///   for as long as the container was the `SKView` itself (SpriteKit's own
///   accessibility implementation kept answering for that view instead of
///   ours, so it handed back elements we had never vended).
///
/// Installed by `GameViewController` as a *sibling* directly above the
/// `SKView` - not as a child of it, because
/// `AccessibleSKView.attachAccessibilityContainer(_:)` sets
/// `accessibilityElementsHidden` on the `SKView` to silence SpriteKit's
/// competing tree and that flag would hide a nested container too.
///
/// Touches are never intercepted (`isUserInteractionEnabled = false`), so a
/// real finger tap, and the synthesized tap XCUITest sends once the element
/// *is* hittable, both fall straight through to the `SKView` and into
/// `GameScene.touchesBegan(_:with:)` exactly as before. Being
/// non-interactive does not affect accessibility - `UILabel` is the same and
/// is perfectly hittable to XCUITest.
final class SceneAccessibilityContainerView: UIView {

    /// The view whose scene this container describes. Weak so the container
    /// cannot keep the render view alive; a `nil` here simply means there is
    /// nothing to vend.
    private weak var sceneView: AccessibleSKView?

    /// - Parameter sceneView: the render view whose `GameScene` this
    ///   container publishes. The back-reference on `sceneView` is wired up
    ///   here too, so the relationship cannot be established by halves.
    init(sceneView: AccessibleSKView) {
        super.init(frame: sceneView.frame)
        self.sceneView = sceneView

        // Invisible, but *present*: UIKit skips hidden / fully transparent
        // views when it walks the accessibility hierarchy, so the view stays
        // opaque-to-accessibility while drawing nothing.
        backgroundColor = .clear
        isOpaque = false

        // Never take a touch away from the SKView underneath.
        isUserInteractionEnabled = false

        // A container, never a leaf: UIKit consults `accessibilityElements`
        // only on a view that is not itself an accessibility element.
        isAccessibilityElement = false
        accessibilityElementsHidden = false

        sceneView.attachAccessibilityContainer(self)
    }

    /// Not used by the app (the container is only ever created in code), but
    /// required of a `UIView` subclass with its own designated initialiser.
    /// A container with no `sceneView` vends nothing rather than crashing.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    // MARK: - UIAccessibilityContainer

    override var accessibilityElements: [Any]? {
        get { sceneView?.publishedAccessibilityElements() }
        set { super.accessibilityElements = newValue }
    }

    /// Overridden alongside `accessibilityElements` deliberately: UIKit is
    /// free to reach for either the array above or this older count/index
    /// triplet, and answering both from one source removes any question of
    /// which one wins.
    override func accessibilityElementCount() -> Int {
        sceneView?.publishedAccessibilityElements()?.count ?? 0
    }

    override func accessibilityElement(at index: Int) -> Any? {
        guard let elements = sceneView?.publishedAccessibilityElements() else { return nil }
        guard elements.indices.contains(index) else { return nil }
        return elements[index]
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        guard
            let elements = sceneView?.publishedAccessibilityElements(),
            let candidate = element as? UIAccessibilityElement
        else {
            return NSNotFound
        }

        // Identity first, then identifier/label. Identity is the common case
        // (elements are cached and reused per node), which is what keeps
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

    // MARK: - Hit testing

    /// UIKit's default `UIView` implementation already resolves a point to
    /// one of `accessibilityElements` - that default is precisely what this
    /// class exists to inherit, and nothing here is required for `isHittable`
    /// to work.
    ///
    /// It is overridden only to *disambiguate* overlapping elements, which
    /// the default cannot do: `menu.container` is a size-less marker
    /// published at a synthesised 1pt rect and it sits inside the PLAY
    /// button, so a point covered by both must resolve to the button - a
    /// marker exists to be findable, not to be tapped. Anything this view
    /// does not cover falls through to `super`, so the inherited behaviour is
    /// never *replaced*, only refined.
    override func accessibilityHitTest(_ point: CGPoint, event: UIEvent?) -> Any? {
        guard let sceneView else { return inheritedAccessibilityHitTest(point, event: event) }

        if let hit = sceneView.publishedElement(atContainerPoint: point) { return hit }

        // The point arrives in this view's own coordinate space. Should a
        // caller hand over a window-space point instead, converting it costs
        // nothing and is a no-op for this app's full-bleed window.
        if window != nil {
            let converted = convert(point, from: nil)
            if converted != point,
               let hit = sceneView.publishedElement(atContainerPoint: converted) {
                return hit
            }
        }

        return inheritedAccessibilityHitTest(point, event: event)
    }

    /// `UIView`'s own answer to the hit test, for the cases where nothing of
    /// ours is under the point.
    ///
    /// The selector carries an iOS 18 availability annotation - so while the
    /// *override* needs no gate, a `super` call does. Below iOS 18 there is
    /// no callable inherited implementation to defer to, and `nil` is the
    /// correct answer anyway: it means "no accessibility element of mine is
    /// at this point", which is exactly the state this path is reached in.
    private func inheritedAccessibilityHitTest(_ point: CGPoint, event: UIEvent?) -> Any? {
        if #available(iOS 18.0, *) {
            return super.accessibilityHitTest(point, event: event)
        }
        return nil
    }
}
