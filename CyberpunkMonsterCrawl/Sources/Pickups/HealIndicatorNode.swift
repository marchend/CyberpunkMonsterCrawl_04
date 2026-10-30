import CoreGraphics
import SpriteKit

/// `CYBERPUN-17-21`: the floating "+N" heal indicator a med-kit pickup was
/// missing. `PlayerNode.heal(_:)` and `HUDRunModel.currentHP` (which reads
/// `player.hp` live every frame) both already apply/show the HP change
/// correctly -- the bug was that *nothing* told the player a med kit had
/// just healed them. This is the visual-feedback node that closes that
/// gap, in the same "logic/rendering, mount separately" split `HitEffects`
/// and `PulseRingNode` both already follow in this codebase: node
/// construction only, no scene knowledge.
///
/// **No shared code with `HitEffects`/`PulseRingNode`.** Those two wrap an
/// atlas-sliced `SKSpriteNode` animation; this is plain text with no art
/// asset, so an `SKLabelNode` is the simplest fit (the same choice
/// `KillCountLabel`/`RunTimerLabel` make for HUD numbers) rather than
/// inventing a shared "transient effect" base type for one text case and
/// two sprite cases.
///
/// **Mounting convention.** Expected to be parented directly under
/// `GameScene.effectsLayer` -- the same `worldLayer < effectsLayer <
/// uiLayer` convention `HitEffects`' muzzle-flash/hit-puff nodes and
/// `PulseRingNode` already use -- at a caller-resolved position already
/// converted into `effectsLayer`'s own space (`GameScene`'s private
/// `effectsSpacePoint(fromWorldSpace:)`, the same conversion
/// `applyPulseTrigger(raccoons:)` performs for `pulseRing`). Left with
/// **no relative `zPosition` of its own** (same as `HitEffects`' nodes):
/// `effectsLayer`'s own zPosition already sits at
/// `LayerConstants.effectsMinZ`, the floor of `LayerConstants.effectsBand`,
/// so a relative zPosition of `0` already lands this node's *cumulative*
/// zPosition safely inside that band -- strictly above `worldBand` and
/// strictly below `uiBand` -- with no per-node band arithmetic needed.
enum HealIndicatorNode {

    /// How far, in points, the label rises over its lifetime.
    static let riseDistance: CGFloat = 28

    /// One full rise-and-fade play-through, in seconds -- an initial
    /// tuning constant, like every other per-effect timing value in this
    /// codebase, expected to move in a later playtesting pass.
    static let duration: TimeInterval = 0.9

    /// Matches `KillCountLabel`/`RunTimerLabel`'s HUD numeral font.
    static let fontName = "Menlo-Bold"
    static let fontSize: CGFloat = 20

    /// The med kit's own accent color (`PickupNode.padColor(for: .medKit)`),
    /// so the indicator reads as "the thing that just healed you" rather
    /// than an unrelated color.
    static let textColor: SKColor = PixelGritPalette.neonAccent

    /// The action key `spawn(amount:at:)` runs its rise-and-fade under, so
    /// a caller (or test) can look it up by name instead of guessing
    /// whether one was applied.
    static let riseAndFadeActionKey = "healIndicatorRiseAndFade"

    /// Builds a `"+<amount>"` label at `position`, already running its
    /// rise-and-fade animation and scheduled to `removeFromParent()` on
    /// completion -- a caller must still `addChild` this node somewhere
    /// (and keep it there across frames) for the action to ever run or be
    /// visible, the same contract `HitEffects.spawnHitPuff(at:)` documents.
    ///
    /// `amount` is expected to be the amount **actually applied**
    /// (`PlayerNode.heal(_:)`'s return value), not the raw med-kit roll, so
    /// a heal clamped by `maxHP` shows the true number rather than one the
    /// HP bar never reflected. A non-positive `amount` is a no-op
    /// returning `nil`: there is nothing to show for a heal that applied
    /// zero HP.
    static func spawn(amount: Int, at position: CGPoint) -> SKLabelNode? {
        guard amount > 0 else { return nil }

        let label = SKLabelNode(text: "+\(amount)")
        label.fontName = fontName
        label.fontSize = fontSize
        label.fontColor = textColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = position

        let rise = SKAction.moveBy(x: 0, y: riseDistance, duration: duration)
        rise.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: duration)
        let riseAndFade = SKAction.group([rise, fade])
        label.run(
            SKAction.sequence([riseAndFade, SKAction.removeFromParent()]),
            withKey: riseAndFadeActionKey
        )

        return label
    }
}
