import CoreGraphics
import UIKit

/// The six HUD elements `CYBERPUN-17-12` mounts, and the one name
/// `HUDLayout` computes a frame for.
enum HUDSlot: CaseIterable {
    case hpBar
    case levelXPBar
    case runTimer
    case killCount
    case pulseButton
    case swarmBanner
}

/// Pure layout-spec type: `(sceneSize, safeAreaInsets) -> [HUDSlot: CGRect]`.
///
/// No `SKNode`/SpriteKit import here on purpose -- this is the same split
/// `FloatingThumbstickNode`'s own static geometry helpers
/// (`leftRegion(forSize:safeAreaInsets:)`, `restingPosition(forSize:
/// safeAreaInsets:)`) already use: placement math is a pure function of
/// size + insets, testable with no scene, no view, no node.
///
/// **Coordinate space.** Every frame is in `GameScene.uiLayer`'s own space:
/// `(0, 0)` at the centre of the visible area, `x` increasing right, `y`
/// increasing up -- exactly the convention `FloatingThumbstickNode` and
/// `MenuScreenNode` already document and lay out in. A future mount simply
/// sets `node.position = CGPoint(x: frame.midX, y: frame.midY)` (or, for an
/// element with real width/height baked into its own children, positions
/// its children within `frame` directly) with no further coordinate
/// translation.
///
/// **Orientation.** There is no separate "portrait" / "landscape" branch:
/// every frame is derived from `sceneSize`/`safeAreaInsets` directly, and a
/// rotation is just a different `sceneSize` (width/height swapped) with
/// different insets (the notch moves from top to a side, the home indicator
/// stays at the bottom). `HUDLayoutTests` exercises both a representative
/// portrait and a representative landscape input rather than branching
/// logic here.
///
/// **Two edge-anchored top columns, then the banner.** The top row is split
/// into a left column (HP bar, then the level/XP bar under it) and a right
/// column (run timer, then the kill count under it), each anchored to its
/// own safe-area edge, with the transient swarm banner hung below both.
/// That is a width constraint, not a taste call: portrait is 390pt wide, so
/// a 220pt HP bar anchored left already reaches past the screen's centre
/// and a *centred* 120pt run timer (which is where `CYBERPUN-17-12` PR 1
/// put it) is drawn straight through it -- with the kill count overlapping
/// the timer's other edge by a further point. `HUDLayoutTests` /
/// `HUDRotationUITests` pin mutual disjointness in both orientations so a
/// future retune of any element's size cannot silently reintroduce that.
///
/// **Stays clear of the thumbstick's bottom-left region.** The movement
/// thumbstick (`FloatingThumbstickNode`) and the ability button it used to
/// reserve a slot for both live in the bottom-left "thumb quadrant"
/// (`FloatingThumbstickNode.leftRegion(forSize:safeAreaInsets:)`). This
/// story's pulse-button slot is bottom-**right** instead (per this ticket's
/// own wording -- see the still-open placement note in `AGENT.md`'s
/// `CYBERPUN-17-10` entry), and every other slot here hangs from the top of
/// the safe area, so no slot this type produces can overlap that region by
/// construction -- but only just, in landscape: see `swarmBannerSize`'s own
/// doc comment for the 137pt vertical budget the whole top stack has to fit
/// inside there. `HUDLayoutTests` still pins the non-overlap
/// directly (computed from `FloatingThumbstickNode`'s own geometry, so the
/// two can never silently drift apart) rather than leaving it as an
/// assumption about "top" and "bottom-left" never meeting.
enum HUDLayout {

    // MARK: - Element sizes

    static let hpBarSize = CGSize(width: 220, height: 28)
    static let levelXPBarSize = CGSize(width: 220, height: 20)
    static let runTimerSize = CGSize(width: 120, height: 32)
    static let killCountSize = CGSize(width: 120, height: 32)
    static let pulseButtonSize = CGSize(width: 72, height: 72)

    /// The banner is the one slot whose height is set by a *budget* rather
    /// than by its own content (an 18pt `Menlo-Bold` line): it hangs below
    /// both top columns, and in landscape the whole stack has to fit
    /// between the safe area's top edge and `thumbstickReservedRegion`'s
    /// top -- 137pt at the representative landscape insets
    /// (`safeRect.maxY 195` down to `58`). `16 + 32 + 8 + 32 + 8 + 36 =
    /// 132` fits with 5pt to spare; the 44pt this was until
    /// `CYBERPUN-17-12` PR 2 did not (`140 > 137`), which pushed the banner
    /// into the stick's reserved region in landscape.
    static let swarmBannerSize = CGSize(width: 280, height: 36)

    /// Gap kept between the safe area's own edge and any slot's outer edge.
    static let edgeMargin: CGFloat = 16

    /// Gap kept between two vertically stacked slots (HP -> XP, run timer
    /// -> kill count, and either column's bottom -> the swarm banner).
    static let verticalSpacing: CGFloat = 8

    // MARK: - Safe content area

    /// The safe content rect in `uiLayer` space: `sceneSize` shrunk by
    /// `safeAreaInsets` on every edge, centred on the origin.
    static func safeContentRect(sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let minX = -sceneSize.width / 2 + safeAreaInsets.left
        let maxX = sceneSize.width / 2 - safeAreaInsets.right
        let minY = -sceneSize.height / 2 + safeAreaInsets.bottom
        let maxY = sceneSize.height / 2 - safeAreaInsets.top
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// The bottom-left region `FloatingThumbstickNode` claims for itself
    /// plus its own reserved (legacy, bottom-left) pulse-button slot --
    /// mirrored from that type's own geometry rather than re-declared, so
    /// this can never silently drift out of step with it.
    static func thumbstickReservedRegion(sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let safeRect = safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        let reservedSlot = FloatingThumbstickNode.reservedPulseButtonSlot(
            forSize: sceneSize,
            safeAreaInsets: safeAreaInsets
        )
        return CGRect(
            x: safeRect.minX,
            y: safeRect.minY,
            width: FloatingThumbstickNode.leftRegion(forSize: sceneSize, safeAreaInsets: safeAreaInsets).width,
            height: reservedSlot.maxY - safeRect.minY
        )
    }

    // MARK: - Per-slot frames

    /// The anchor frame for `slot`, in `uiLayer` space.
    static func frame(for slot: HUDSlot, sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let safeRect = safeContentRect(sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)

        switch slot {
        case .hpBar:
            return CGRect(
                x: safeRect.minX + edgeMargin,
                y: safeRect.maxY - edgeMargin - hpBarSize.height,
                width: hpBarSize.width,
                height: hpBarSize.height
            )

        case .levelXPBar:
            let hp = frame(for: .hpBar, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
            return CGRect(
                x: safeRect.minX + edgeMargin,
                y: hp.minY - verticalSpacing - levelXPBarSize.height,
                width: levelXPBarSize.width,
                height: levelXPBarSize.height
            )

        case .runTimer:
            return CGRect(
                x: safeRect.maxX - edgeMargin - runTimerSize.width,
                y: safeRect.maxY - edgeMargin - runTimerSize.height,
                width: runTimerSize.width,
                height: runTimerSize.height
            )

        case .killCount:
            let timer = frame(for: .runTimer, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
            return CGRect(
                x: safeRect.maxX - edgeMargin - killCountSize.width,
                y: timer.minY - verticalSpacing - killCountSize.height,
                width: killCountSize.width,
                height: killCountSize.height
            )

        case .pulseButton:
            return CGRect(
                x: safeRect.maxX - edgeMargin - pulseButtonSize.width,
                y: safeRect.minY + edgeMargin,
                width: pulseButtonSize.width,
                height: pulseButtonSize.height
            )

        case .swarmBanner:
            // Hung below *both* columns, not just one: the banner is
            // horizontally centred and 280pt wide, so on a 390pt-wide
            // portrait screen its x-range overlaps the left column (the HP
            // and level/XP bars run from the safe-area edge to +41) *and*
            // the right column (the run timer and kill count start at +59).
            // Clearing only one of them would put the banner straight
            // through the other -- which is exactly what a top-centre run
            // timer did to the HP bar before this layout split the top row
            // into two edge-anchored columns.
            let leftColumnBottom = frame(
                for: .levelXPBar, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets
            ).minY
            let rightColumnBottom = frame(
                for: .killCount, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets
            ).minY
            return CGRect(
                x: -swarmBannerSize.width / 2,
                y: min(leftColumnBottom, rightColumnBottom) - verticalSpacing - swarmBannerSize.height,
                width: swarmBannerSize.width,
                height: swarmBannerSize.height
            )
        }
    }

    /// Every slot's frame, computed once for a given `sceneSize` /
    /// `safeAreaInsets`.
    static func allFrames(sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) -> [HUDSlot: CGRect] {
        Dictionary(
            uniqueKeysWithValues: HUDSlot.allCases.map {
                ($0, frame(for: $0, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets))
            }
        )
    }
}
