import CoreGraphics
import SpriteKit
import UIKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-12` PR 2: the *mounted* HUD (via a real `GameScene`, not
/// just `HUDLayout`'s own pure geometry -- `HUDLayoutTests` already pins
/// that) never overlaps the movement thumbstick's region, and a touch on a
/// HUD control routes to that control rather than passing through to the
/// thumbstick/world.
///
/// **Which region "the thumbstick's region" is, and why.**
/// `FloatingThumbstickNode` has two of them, and they are not
/// interchangeable:
///
/// - `leftRegion(forSize:safeAreaInsets:)` is the stick's *touch-acceptance
///   box*: the whole left half of the safe area, top to bottom. It is that
///   large on purpose -- the stick is a **floating** one that materialises
///   wherever the thumb lands, so anything excluded from this box becomes a
///   dead patch where a thumb-down does not move the player. A passive
///   read-out (the HP bar, the run clock) must therefore be *allowed* to
///   sit inside it: excluding the top-left corner would trade a cosmetic
///   overlap for a real input hole.
/// - `HUDLayout.thumbstickReservedRegion(sceneSize:safeAreaInsets:)` is the
///   region the stick actually *occupies*: its resting graphic (base +
///   knob + `maxRadius`) plus the ability-button slot stacked above it.
///   That is the region a HUD element may not be drawn into, and it is the
///   one `HUDLayoutTests` (PR 1) already pins the pure slot geometry
///   against -- pinned here again against the *mounted* nodes, in both
///   orientations.
///
/// The part `leftRegion` genuinely binds on is the HUD's one *interactive*
/// control: the pulse button must sit wholly outside the stick's
/// acceptance box, or a press on it would be ambiguous with a stick
/// engagement. That is asserted below on the button's whole frame, not
/// merely on its centre point.
final class HUDThumbstickOverlapTests: XCTestCase {

    private let portraitSize = CGSize(width: 390, height: 844)
    private let portraitInsets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    private let landscapeSize = CGSize(width: 844, height: 390)
    private let landscapeInsets = UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 47)

    private func makeGameplayScene(size: CGSize) -> GameScene {
        let scene = GameScene(size: size)
        XCTAssertTrue(scene.stateMachine.transition(to: .gameplay))
        return scene
    }

    /// Every mounted HUD element's own known size (see each element's own
    /// "no positioning logic here" doc note) turned into a frame centred on
    /// its current `position` -- the same convention `HUDLayoutTests`
    /// itself checks the *pure* slot geometry against.
    private func elementFrame(_ node: SKNode, size: CGSize) -> CGRect {
        CGRect(
            x: node.position.x - size.width / 2,
            y: node.position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func mountedElements(_ hud: HUDLayer) -> [(String, SKNode, CGSize)] {
        [
            ("hpBar", hud.hpBar, HUDLayout.hpBarSize),
            ("levelXPBar", hud.levelXPBar, HUDLayout.levelXPBarSize),
            ("runTimer", hud.runTimer, HUDLayout.runTimerSize),
            ("killCount", hud.killCount, HUDLayout.killCountSize),
            ("pulseButton", hud.pulseButton, HUDLayout.pulseButtonSize),
            ("swarmBanner", hud.swarmBanner, HUDLayout.swarmBannerSize),
        ]
    }

    private func laidOutHUD(
        in scene: GameScene,
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HUDLayer {
        let hud = try XCTUnwrap(scene.hudLayer, "entering .gameplay must mount HUDLayer", file: file, line: line)
        hud.applyLayout(
            for: sceneSize,
            safeAreaInsets: safeAreaInsets,
            orientation: HUDOrientation.current(forSceneSize: sceneSize)
        )
        return hud
    }

    private func assertNoElementOverlapsTheStick(
        scene: GameScene,
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let hud = try laidOutHUD(in: scene, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets, file: file, line: line)
        let occupied = HUDLayout.thumbstickReservedRegion(
            sceneSize: sceneSize,
            safeAreaInsets: safeAreaInsets
        )

        for (name, node, size) in mountedElements(hud) {
            let frame = elementFrame(node, size: size)
            XCTAssertFalse(
                frame.intersects(occupied),
                "\(name) frame \(frame) overlaps the region the thumbstick occupies \(occupied)",
                file: file, line: line
            )
        }
    }

    func test_noMountedHUDElement_overlapsTheRegionTheThumbstickOccupies_inPortrait() throws {
        let scene = makeGameplayScene(size: portraitSize)
        try assertNoElementOverlapsTheStick(scene: scene, sceneSize: portraitSize, safeAreaInsets: portraitInsets)
    }

    func test_noMountedHUDElement_overlapsTheRegionTheThumbstickOccupies_inLandscape() throws {
        let scene = makeGameplayScene(size: landscapeSize)
        try assertNoElementOverlapsTheStick(
            scene: scene, sceneSize: landscapeSize, safeAreaInsets: landscapeInsets
        )
    }

    // MARK: - The HUD's interactive control clears the stick's acceptance box

    /// The stick must not be able to claim *any* point of the pulse
    /// button, not just its centre -- so the whole frame is checked against
    /// `leftRegion`, and every corner is additionally offered to
    /// `canBeginTouch(at:)` (the predicate the scene really consults) to
    /// prove the two agree.
    private func assertThePulseButtonClearsTheSticksAcceptanceBox(
        scene: GameScene,
        sceneSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let hud = try laidOutHUD(in: scene, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets, file: file, line: line)
        let acceptanceBox = FloatingThumbstickNode.leftRegion(forSize: sceneSize, safeAreaInsets: safeAreaInsets)
        let button = elementFrame(hud.pulseButton, size: HUDLayout.pulseButtonSize)

        XCTAssertFalse(
            button.intersects(acceptanceBox),
            "the HUD pulse button \(button) must sit wholly outside the stick's touch-acceptance box "
                + "\(acceptanceBox), or a press on it is ambiguous with engaging the stick",
            file: file, line: line
        )

        // ... and the predicate the scene actually consults must agree, at
        // every corner as well as the centre.
        for corner in [
            CGPoint(x: button.minX, y: button.minY),
            CGPoint(x: button.maxX, y: button.minY),
            CGPoint(x: button.minX, y: button.maxY),
            CGPoint(x: button.maxX, y: button.maxY),
            CGPoint(x: button.midX, y: button.midY),
        ] {
            XCTAssertFalse(
                scene.thumbstick.canBeginTouch(at: corner),
                "the movement stick must refuse a touch at \(corner), inside the HUD pulse button",
                file: file, line: line
            )
        }
    }

    func test_theHUDPulseButton_clearsTheSticksTouchAcceptanceBox_inPortrait() throws {
        let scene = makeGameplayScene(size: portraitSize)
        try assertThePulseButtonClearsTheSticksAcceptanceBox(
            scene: scene, sceneSize: portraitSize, safeAreaInsets: portraitInsets
        )
    }

    func test_theHUDPulseButton_clearsTheSticksTouchAcceptanceBox_inLandscape() throws {
        let scene = makeGameplayScene(size: landscapeSize)
        try assertThePulseButtonClearsTheSticksAcceptanceBox(
            scene: scene, sceneSize: landscapeSize, safeAreaInsets: landscapeInsets
        )
    }

    // MARK: - A touch on a HUD control reaches that control

    func test_aTouchOnTheHUDPulseButton_dispatchesToIt_notToAnotherNode() throws {
        let scene = makeGameplayScene(size: portraitSize)
        let hud = try laidOutHUD(in: scene, sceneSize: portraitSize, safeAreaInsets: portraitInsets)

        let responder = scene.dispatchTouch(atScenePoint: hud.pulseButton.position)

        XCTAssertTrue(
            responder === hud.pulseButton,
            "a touch on the HUD pulse button's own slot must resolve to it, not to another uiLayer node"
        )
    }

    /// ... and it reaches the *ability*, not merely the node: the press has
    /// to arrive at the scene's own pulse trigger, which is the whole point
    /// of `HUDLayer.bind(to:)` wiring `onPress` to the run model.
    func test_aTouchOnTheHUDPulseButton_reachesTheScenesPulseTrigger() throws {
        let scene = makeGameplayScene(size: portraitSize)
        let hud = try laidOutHUD(in: scene, sceneSize: portraitSize, safeAreaInsets: portraitInsets)
        XCTAssertFalse(scene.pulseAbility.isOnCooldown, "precondition: a fresh run starts with the pulse ready")

        scene.dispatchTouch(atScenePoint: hud.pulseButton.position)

        XCTAssertTrue(
            scene.pulseAbility.isOnCooldown,
            "the HUD press must fire the real ability (which then goes on cooldown), not just animate the button"
        )
    }

    /// A HUD touch must not *also* be handed to the world/stick: the scene
    /// offers a touch to `thumbstick.beginTouch(at:)` only once
    /// `dispatchTouch(atScenePoint:)` has returned `nil`, so a HUD control
    /// consuming the touch is what keeps the stick out of it.
    func test_aTouchOnTheHUDPulseButton_isNotAlsoOfferedToTheThumbstick() throws {
        let scene = makeGameplayScene(size: portraitSize)
        let hud = try laidOutHUD(in: scene, sceneSize: portraitSize, safeAreaInsets: portraitInsets)
        let localPoint = scene.uiLayer.convert(hud.pulseButton.position, from: scene)

        XCTAssertNotNil(
            scene.dispatchTouch(atScenePoint: hud.pulseButton.position),
            "a HUD control must consume the touch, so the scene never falls through to the stick"
        )
        XCTAssertFalse(
            scene.thumbstick.canBeginTouch(at: localPoint),
            "the movement stick must not claim a touch on the HUD pulse button's slot"
        )
    }
}
