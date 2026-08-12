import CoreGraphics

/// Named `zPosition` bands for the three persistent `GameScene` layers, per
/// `docs/bootstrap.md` \u00a73: `worldLayer < effectsLayer < uiLayer`, with
/// `uiLayer` pinned to the camera and given first refusal on every touch.
///
/// v1 shipped unplayable because the world node rendered over the UI while
/// every unit test passed. These constants exist so "the world can never
/// out-paint the UI" is a single, testable numeric fact
/// (`LayerOrderingTests`) rather than an unenforced convention that a single
/// hard-coded literal can quietly violate.
///
/// Each layer owns a closed range; `GameScene` sets the *container* node
/// (`worldLayer`/`effectsLayer`/`uiLayer`) to that range's minimum, so
/// content added directly under a container (zPosition 0 relative offset)
/// starts at the band floor and any finer-grained offsets future PRs add
/// (e.g. the depth module's painter's-algorithm bands in `worldLayer`) stay
/// inside the band as long as they respect `worldMinZ...worldMaxZ`.
enum LayerConstants {
    // MARK: - World layer

    /// Lower bound of the world layer's zPosition band. The future depth
    /// module (painter's-algorithm bands `-(tileX + tileY) * 10`, ground
    /// plane 5000 below all bands \u2014 docs/bootstrap.md \u00a74) places every
    /// world-space node's zPosition inside `worldMinZ...worldMaxZ`.
    static let worldMinZ: CGFloat = -100_000

    /// Upper bound of the world layer's zPosition band. Strictly below
    /// `effectsMinZ`, which is in turn strictly below `uiMinZ` \u2014 see
    /// `LayerOrderingTests.test_orderingInvariant_worldBelowEffectsBelowUI`.
    static let worldMaxZ: CGFloat = -1_000

    // MARK: - Effects layer

    /// Lower bound of the effects layer's zPosition band (particles, muzzle
    /// flashes, hit puffs \u2014 sandwiched strictly between world and UI).
    static let effectsMinZ: CGFloat = -999

    /// Upper bound of the effects layer's zPosition band.
    static let effectsMaxZ: CGFloat = 999

    // MARK: - UI layer

    /// Lower bound of the UI layer's zPosition band. `uiLayer` and every
    /// node it contains must never fall below this value \u2014 that is the
    /// contract `LayerOrderingTests` checks directly against a live
    /// `GameScene`.
    static let uiMinZ: CGFloat = 1_000

    /// Upper bound of the UI layer's zPosition band.
    static let uiMaxZ: CGFloat = 100_000

    // MARK: - Container zPositions

    /// The zPosition `GameScene` assigns to the `worldLayer` container node.
    static let worldLayerZ: CGFloat = worldMinZ

    /// The zPosition `GameScene` assigns to the `effectsLayer` container
    /// node.
    static let effectsLayerZ: CGFloat = effectsMinZ

    /// The zPosition `GameScene` assigns to the `uiLayer` container node
    /// (parented to the scene's `SKCameraNode`).
    static let uiLayerZ: CGFloat = uiMinZ
}
