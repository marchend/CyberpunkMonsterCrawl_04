import CoreGraphics
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6-t2: `ActorShadowNode` is built for reuse (`PlayerNode`
/// today, the raccoon swarm in `CYBERPUN-17-8`), so the contract it
/// advertises -- 2:1 geometry derived from the caller's width, a
/// semi-transparent fill, hard pixel edges, no touch interception -- is
/// pinned here rather than only incidentally through
/// `PlayerNodeTests.test_shadow_isADistinctChildNode_fromTheBody`, which
/// asserts nothing stronger than `path != nil` and so would not catch
/// `aspectRatio`/`height` drift, a wrong ellipse bounds rect, or the alpha
/// dropping to fully opaque.
final class ActorShadowNodeTests: XCTestCase {

    private static let sampleWidths: [CGFloat] = [14, 20, 33]

    // MARK: - Geometry: 2:1, derived, centred on the actor's anchor

    func test_height_isAlwaysWidthOverTheAspectRatio() {
        for width in Self.sampleWidths {
            let shadow = ActorShadowNode(width: width)
            XCTAssertEqual(shadow.width, width, accuracy: 1e-9)
            XCTAssertEqual(shadow.height, width / ActorShadowNode.aspectRatio, accuracy: 1e-9)
        }
    }

    func test_aspectRatio_isTheIsometricDiamonds2To1() {
        // The world's tile diamonds are 96x48 (`docs/bootstrap.md` section
        // 4); the shadow reads as lying on that ground plane only if it
        // shares their ratio, so this is derived from the projection's own
        // half-width/half-height rather than restated as a `2` literal.
        XCTAssertEqual(
            ActorShadowNode.aspectRatio,
            CGFloat(IsometricProjection.tileHalfWidth / IsometricProjection.tileHalfHeight),
            accuracy: 1e-9,
            "The shadow's aspect ratio must stay the isometric diamond's own 2:1."
        )
    }

    func test_path_isAnEllipseOfWidthByHeight_centredOnTheNodesOrigin() {
        for width in Self.sampleWidths {
            let shadow = ActorShadowNode(width: width)
            guard let bounds = shadow.path?.boundingBox else {
                return XCTFail("width \(width): the shadow drew no path at all.")
            }

            XCTAssertEqual(bounds.width, width, accuracy: 1e-6, "width \(width): wrong ellipse width.")
            XCTAssertEqual(bounds.height, shadow.height, accuracy: 1e-6, "width \(width): wrong ellipse height.")

            // Centred on the node's own origin, which is the positioning
            // contract this type documents: a caller leaves it at `.zero` in
            // the actor's node space and the ellipse lands under the feet.
            XCTAssertEqual(bounds.midX, 0, accuracy: 1e-6, "width \(width): ellipse is not horizontally centred.")
            XCTAssertEqual(bounds.midY, 0, accuracy: 1e-6, "width \(width): ellipse is not vertically centred.")
        }
    }

    // MARK: - Fill: semi-transparent, never a solid hole in the ground

    func test_fillColor_isSemiTransparentBlack_notFullyOpaque() {
        let shadow = ActorShadowNode(width: 20)
        let alpha = shadow.fillColor.cgColor.alpha

        XCTAssertGreaterThan(alpha, 0, "A fully transparent shadow is not a shadow.")
        XCTAssertLessThan(
            alpha, 1,
            "A fully opaque fill reads as a hole in the ground, not as a shadow."
        )
        XCTAssertEqual(alpha, ActorShadowNode.shadowFillColor.cgColor.alpha, accuracy: 1e-6)
    }

    func test_strokeIsInvisible_soTheShadowHasNoOutline() {
        let shadow = ActorShadowNode(width: 20)
        XCTAssertEqual(shadow.strokeColor.cgColor.alpha, 0, accuracy: 1e-6)
        XCTAssertEqual(shadow.lineWidth, 0, accuracy: 1e-9)
    }

    // MARK: - Pixel crispness (docs/bootstrap.md section 1)

    func test_isNotAntialiased_soItsEdgesStayPixelCrisp() {
        // `SKShapeNode.isAntialiased` defaults to `true`; this game's whole
        // rendering rule is hard pixel edges, and a shape node cannot go
        // through `PixelCrispness.apply(to:)` (that takes `SKSpriteNode`),
        // so the opt-out has to be explicit -- and pinned.
        XCTAssertFalse(ActorShadowNode(width: 20).isAntialiased)
    }

    // MARK: - Z-order and touch contracts

    func test_zPosition_isLeftAtZero_soTheOwningActorOwnsTheOrdering() {
        XCTAssertEqual(ActorShadowNode(width: 20).zPosition, 0, accuracy: 1e-9)
    }

    func test_doesNotOptIntoUIKitTouchDelivery() {
        // `GameScene.nodesBypassingSceneTouchDispatch()` audits this
        // graph-wide; a decorative node must never be the reason it trips.
        XCTAssertFalse(ActorShadowNode(width: 20).isUserInteractionEnabled)
    }

    // MARK: - The player's shadow is sized from a measured footprint

    func test_playerShadowWidth_isThePlayersMeasuredGroundFootprint_notAHandPickedNumber() {
        XCTAssertEqual(
            PlayerNode.shadowWidth,
            PlayerSpriteSheet.hitboxSize.width,
            accuracy: 1e-9,
            "The player's shadow width must stay derived from its measured hitbox, not re-invented."
        )

        let player = PlayerNode()
        XCTAssertEqual(player.shadow.width, PlayerSpriteSheet.hitboxSize.width, accuracy: 1e-9)
        XCTAssertEqual(
            player.shadow.height,
            PlayerSpriteSheet.hitboxSize.width / ActorShadowNode.aspectRatio,
            accuracy: 1e-9
        )
    }
}
