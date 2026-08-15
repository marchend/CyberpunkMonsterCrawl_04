import CoreGraphics

/// The actor half of `DepthModel`'s painter's-algorithm depth scheme: turns
/// an actor's fractional tile-space position plus an in-band offset into the
/// absolute `zPosition` a rendering consumer (`PlayerNode`, and later the
/// raccoon swarm) assigns its node.
///
/// This deliberately does not duplicate `DepthModel`'s band math -- it is a
/// thin, actor-specific composition over `DepthModel.band(forActorAt:)`
/// (which already samples the actor's **rounded** tile coordinate, per
/// `docs/bootstrap.md` section 4's "actors sampling their rounded tile") and
/// `DepthModel.actorOffsetRange` (`6.5...9.9`). Everything here stays in
/// terms of that single source of truth so the two modules can never
/// disagree about where a band starts or ends.
///
/// ## The player-max tie-break
///
/// The story requires the player's `zPosition` to be the *maximum* among any
/// actors sharing a band -- e.g. a raccoon standing on the same tile as the
/// player must always draw behind it. Rather than resolving that as a
/// runtime comparison (which would need every actor's zPosition recomputed
/// and compared on every frame just to break a tie), this is enforced
/// **structurally**: the player is unconditionally assigned
/// `DepthModel.actorOffsetRange.upperBound` (`9.9`, the very top of the
/// actor slot), and `nonPlayerActorOffsetRange` -- the range every other
/// actor generator is expected to draw its own offset from -- excludes that
/// exact value. As long as a future actor (the raccoon swarm, `CYBERPUN-17-8`)
/// picks its offset from `nonPlayerActorOffsetRange` rather than from the
/// full `DepthModel.actorOffsetRange`, it can never tie with, let alone
/// exceed, the player's offset within the same band. This is a deliberate
/// readability override, not a physical simulation: two actors standing on
/// the same tile do not actually occupy the same point, but forcing the
/// player to always read as "in front" is simpler and more legible than a
/// finer-grained depth sort within a single tile's actor slot.
enum DepthBanding {

    /// The offset reserved exclusively for the player: the top of
    /// `DepthModel.actorOffsetRange`. See the type-level doc comment for why
    /// this guarantees the player is always the band's max.
    static let playerActorOffset: CGFloat = DepthModel.actorOffsetRange.upperBound

    /// The half-open sub-range of `DepthModel.actorOffsetRange` every
    /// **non-player** actor must draw its own offset from. Half-open at
    /// `playerActorOffset` so a non-player actor's offset can get
    /// arbitrarily close to the player's but can never equal it -- the
    /// structural half of the player-max tie-break described above.
    static let nonPlayerActorOffsetRange: Range<CGFloat> = DepthModel.actorOffsetRange.lowerBound..<playerActorOffset

    /// The absolute `zPosition` for an actor standing at fractional
    /// tile-space `position`, at in-band `offset`.
    ///
    /// `offset` must be a legal actor offset (`DepthModel
    /// .isValidActorOffset(_:)`); an out-of-range value is a programmer
    /// error at the call site (a mis-derived offset), not a recoverable
    /// runtime condition, so DEBUG builds assert rather than silently
    /// clamping -- clamping would let two different, wrong offsets collapse
    /// to the same zPosition with no signal that anything was wrong.
    static func actorZPosition(forActorAt position: TilePoint, offset: CGFloat) -> CGFloat {
        assert(
            DepthModel.isValidActorOffset(offset),
            "DepthBanding.actorZPosition received offset \(offset), outside "
                + "DepthModel.actorOffsetRange (\(DepthModel.actorOffsetRange))."
        )
        return DepthModel.band(forActorAt: position) + offset
    }

    /// The absolute `zPosition` for the player standing at fractional
    /// tile-space `position`: always `actorZPosition(forActorAt:offset:
    /// playerActorOffset)`, so the player is the band's maximum by
    /// construction (see the type-level doc comment).
    static func playerZPosition(at position: TilePoint) -> CGFloat {
        actorZPosition(forActorAt: position, offset: playerActorOffset)
    }
}
