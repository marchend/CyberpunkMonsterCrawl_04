import CoreGraphics
import SpriteKit
import UIKit

/// The live run state `HUDLayer` mounts/binds against -- HP, level/XP, run
/// clock, kill count, pulse-ability cooldown, a pulse-trigger action and a
/// swarm-escalation notification hook.
///
/// A protocol (rather than a concrete type) so `HUDLayer` itself stays
/// independent of `GameScene`: `GameScene`'s own conformance (see the
/// extension at the end of `GameScene.swift`) reads every value straight
/// off its existing state with no intermediate cached copy, and a test
/// double can conform just as easily (`HUDRunModelBindingTests`,
/// `SwarmBannerEscalationTests`).
///
/// `AnyObject`-constrained because `onSwarmEscalation` is a mutable,
/// reference-identity-sensitive property `HUDLayer.bind(to:)` overwrites in
/// place -- a value-type conformer would silently rebind a *copy*.
protocol HUDRunModel: AnyObject {
    /// The player's current/maximum HP -- forwarded straight into
    /// `HPSegmentBar.update(currentHP:maxHP:)`.
    var currentHP: Int { get }
    var maxHP: Int { get }

    /// The player's current level and XP progress *within that level* (not
    /// raw cumulative XP -- see `LevelXPBar`'s own "a level-up simply
    /// arrives here as a lower currentXP" doc note) -- forwarded straight
    /// into `LevelXPBar.update(level:currentXP:xpForNextLevel:)`.
    var level: Int { get }
    var currentXP: Int { get }
    var xpForNextLevel: Int { get }

    /// Seconds elapsed in the current run -- forwarded straight into
    /// `RunTimerLabel.update(elapsedSeconds:)`.
    var elapsedSeconds: TimeInterval { get }

    /// Raccoons killed this run -- forwarded straight into
    /// `KillCountLabel.update(kills:)`.
    var kills: Int { get }

    /// The pulse ability's cooldown state -- forwarded straight into
    /// `HUDPulseButton.update(cooldownFraction:isReady:)`. `1.0` ==
    /// fully ready, `0.0` == a cooldown was just started, matching that
    /// method's own scale.
    var pulseCooldownFraction: CGFloat { get }
    var isPulseReady: Bool { get }

    /// Invoked by `HUDLayer`'s mounted `HUDPulseButton` on every accepted
    /// press -- the run model's own pulse-trigger action (`GameScene
    /// .handlePulsePress()` in production).
    func triggerPulse()

    /// Set by `HUDLayer.bind(to:)`; the conformer calls this whenever a
    /// swarm-escalation event occurs, so `HUDLayer` can show `SwarmBanner`
    /// without the run model needing to know `SwarmBanner` exists.
    var onSwarmEscalation: (() -> Void)? { get set }
}

/// Coarse device orientation, derived from a scene size's own aspect
/// (`width >= height` reads as landscape). `HUDLayout` itself needs no
/// separate portrait/landscape branch (every frame is already a pure
/// function of `sceneSize`/`safeAreaInsets` -- see that type's own doc
/// comment), so this exists purely so `HUDLayer.applyLayout(for:
/// safeAreaInsets:orientation:)` has a stable, introspectable record of
/// which orientation a given layout pass was called for (readable by
/// `HUDRotationUITests`), independent of re-deriving it from the frame
/// dimensions at every call site.
enum HUDOrientation: Equatable {
    case portrait
    case landscape

    static func current(forSceneSize sceneSize: CGSize) -> HUDOrientation {
        sceneSize.width >= sceneSize.height ? .landscape : .portrait
    }
}

/// `CYBERPUN-17-12` PR 2's composition root: instantiates all six PR-1 HUD
/// elements, positions them via `HUDLayout`, and binds them to a live
/// `HUDRunModel` with no intermediate cached state of its own -- every
/// `refresh()` call forwards the model's *current* reading straight into
/// each element's own `update(...)`, so a mutation on the bound model is
/// visible on the very next `refresh()`, never delayed by a stale copy
/// living here.
///
/// **Mounting.** `GameScene` adds one instance directly under `uiLayer`
/// the first time a run enters `.gameplay` -- independent of the
/// state-driven screen registry, the same convention `thumbstick`/the
/// older bottom-left `pulseButton` already follow (`GameplayScreenNode`
/// itself mounts nothing of its own) -- and reuses it, never rebuilding,
/// across a RUN AGAIN.
final class HUDLayer: SKNode {

    // MARK: - Elements

    let hpBar = HPSegmentBar()
    let levelXPBar = LevelXPBar()
    let runTimer = RunTimerLabel()
    let killCount = KillCountLabel()
    let swarmBanner = SwarmBanner()

    /// Built after `super.init()` (see `init()`) because its `onPress`
    /// closure needs to reference `self` -- the same "implicitly-unwrapped,
    /// built post-`super.init()`" convention `GameScene.pulseButton`
    /// already uses for exactly the same reason.
    private(set) var pulseButton: HUDPulseButton!

    // MARK: - Tunables

    /// Message/duration `bind(to:)` wires the bound model's
    /// `onSwarmEscalation` notification to show on `swarmBanner`. An
    /// initial tuning constant, like every other named UI-feel constant in
    /// this codebase.
    static let swarmEscalationMessage = "SWARM INCOMING"
    static let swarmEscalationDuration: TimeInterval = 4.0

    // MARK: - Binding state

    /// The currently bound run model, held weakly: `GameScene` (the
    /// production conformer) owns this node's lifetime as its parent in
    /// `uiLayer`, not the other way around, so this must never keep a
    /// torn-down scene alive -- the same weak-reference convention
    /// `Player.worldSpaceReference` documents for the same reason.
    private(set) weak var runModel: HUDRunModel?

    /// Indirection for `pulseButton`'s `onPress`, so a fresh `bind(to:)`
    /// call can retarget the trigger without needing to reconstruct
    /// `pulseButton` itself (its `onPress` closure is fixed at
    /// construction).
    private var pulseTriggerHandler: (() -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        name = "hudLayer"

        addChild(hpBar)
        addChild(levelXPBar)
        addChild(runTimer)
        addChild(killCount)
        addChild(swarmBanner)

        pulseButton = HUDPulseButton(onPress: { [weak self] in
            self?.pulseTriggerHandler?()
        })
        addChild(pulseButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    /// Positions every mounted element from `HUDLayout`'s own per-slot
    /// frames, anchored at each frame's centre -- every element draws
    /// itself centred on its own local origin (see e.g. `HPSegmentBar`'s
    /// own doc comment), so `frame.midX`/`frame.midY` is the correct
    /// mount point, the same convention `GameScene.layoutPulseButton()`
    /// already follows for the older bottom-left button.
    func applyLayout(for sceneSize: CGSize, safeAreaInsets: UIEdgeInsets, orientation: HUDOrientation) {
        position(hpBar, at: .hpBar, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        position(levelXPBar, at: .levelXPBar, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        position(runTimer, at: .runTimer, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        position(killCount, at: .killCount, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        position(pulseButton, at: .pulseButton, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        position(swarmBanner, at: .swarmBanner, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        currentOrientation = orientation
    }

    /// The orientation the most recent `applyLayout(...)` call was given --
    /// exposed purely so a test can introspect it without re-deriving it
    /// from `sceneSize`.
    private(set) var currentOrientation: HUDOrientation = .portrait

    private func position(_ node: SKNode, at slot: HUDSlot, sceneSize: CGSize, safeAreaInsets: UIEdgeInsets) {
        let frame = HUDLayout.frame(for: slot, sceneSize: sceneSize, safeAreaInsets: safeAreaInsets)
        node.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Binding

    /// Binds this layer to `runModel`: retargets the pulse button's press
    /// to `runModel.triggerPulse()`, wires `runModel.onSwarmEscalation` to
    /// show `swarmBanner`, and forwards its current values into every
    /// element immediately (`refresh()`) -- so a bind mid-run (a RUN AGAIN
    /// reusing this same `HUDLayer`) never leaves an element showing the
    /// previous binding's last-read values even for one frame.
    func bind(to runModel: HUDRunModel) {
        self.runModel = runModel
        pulseTriggerHandler = { [weak runModel] in runModel?.triggerPulse() }
        runModel.onSwarmEscalation = { [weak self] in
            self?.swarmBanner.show(
                message: Self.swarmEscalationMessage,
                duration: Self.swarmEscalationDuration
            )
        }
        refresh()
    }

    /// Forwards `runModel`'s *current* values straight into each element's
    /// own `update(...)` -- no intermediate cached state lives on this
    /// type: every call reads the bound model fresh, so a mutation made to
    /// it since the last `refresh()` (or since `bind(to:)`) is always
    /// reflected, never delayed by a stale copy. A no-op before any
    /// `bind(to:)` call.
    ///
    /// `GameScene.advanceMovementAndCamera(currentTime:)` calls this once
    /// per `.gameplay` frame, the same per-frame cadence
    /// `pulseButton.setCooldownProgress(...)` already used for the older
    /// bottom-left button.
    func refresh() {
        guard let runModel else { return }
        hpBar.update(currentHP: runModel.currentHP, maxHP: runModel.maxHP)
        levelXPBar.update(
            level: runModel.level,
            currentXP: runModel.currentXP,
            xpForNextLevel: runModel.xpForNextLevel
        )
        runTimer.update(elapsedSeconds: runModel.elapsedSeconds)
        killCount.update(kills: runModel.kills)
        pulseButton.update(cooldownFraction: runModel.pulseCooldownFraction, isReady: runModel.isPulseReady)
    }
}
