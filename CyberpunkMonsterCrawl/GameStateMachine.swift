import GameplayKit
import os

/// The game's top-level state, per docs/bootstrap.md:
/// `menu -> gameplay -> death -> highScores` (plus the RUN AGAIN and
/// back-to-menu paths spelled out below). This enum is the public,
/// scene/rendering-agnostic surface; `GameStateMachine` wraps the
/// `GKStateMachine` implementation detail behind it.
///
/// `Hashable` (which implies `Equatable`) so `GameScene`
/// (CYBERPUN-17-2-t2) can key its `[GameState: ScreenNode]` screen
/// registry directly off this enum.
enum GameState: CaseIterable, Hashable {
    case menu
    case gameplay
    case death
    case highScores
}

/// Legal transition table (exhaustive — anything not listed here is
/// illegal and rejected by `isValidNextState`):
///   menu       -> gameplay    (Play)
///   menu       -> highScores  (View high scores)
///   gameplay   -> death       (Player dies)
///   death      -> gameplay    (RUN AGAIN)
///   death      -> menu        (Back to menu)
///   highScores -> menu        (Back to menu)
///
/// Each state holds a weak back-reference to its owning `GameStateMachine`
/// so `didEnter(from:)` can push the change out through `onChange`; the
/// machine owns its states, so a strong reference here would be a cycle.
final class MenuState: GKState {
    weak var owner: GameStateMachine?

    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == GameplayState.self || stateClass == HighScoresState.self
    }

    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        owner?.stateDidEnter(.menu)
    }
}

final class GameplayState: GKState {
    weak var owner: GameStateMachine?

    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == DeathState.self
    }

    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        owner?.stateDidEnter(.gameplay)
    }
}

final class DeathState: GKState {
    weak var owner: GameStateMachine?

    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == GameplayState.self || stateClass == MenuState.self
    }

    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        owner?.stateDidEnter(.death)
    }
}

final class HighScoresState: GKState {
    weak var owner: GameStateMachine?

    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == MenuState.self
    }

    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        owner?.stateDidEnter(.highScores)
    }
}

/// Thin, scene/rendering-agnostic wrapper around `GKStateMachine` exposing
/// the game's four states as the `GameState` enum instead of leaking the
/// `GKState` subclasses to callers. Starts in `.menu`.
///
/// Consumers observe state changes by installing `onChange` rather than
/// polling `currentState`, and rejected transitions are reported through
/// `onIllegalTransition` (DEBUG default: an `os.Logger` warning) so a
/// mis-wired button that silently does nothing is visible at the moment it
/// misbehaves. `GameScene` (CYBERPUN-17-2-t2) is the scene/UI consumer
/// that uses `onChange` to drive its screen registry.
final class GameStateMachine {
    /// Fired on every *successful* entry into a state, with the state just
    /// entered. Rejected transitions never fire it. Supplying the hook via
    /// `init(onChange:)` also delivers the initial `.menu` entry; assigning
    /// it afterwards does not, because that entry already happened — read
    /// `currentState` for the initial render in that case.
    var onChange: ((GameState) -> Void)?

    /// Fired with `(from, to)` whenever `transition(to:)` rejects a pair
    /// that is not in the legal table. Defaults to `nil`, in which case
    /// DEBUG builds log a warning; set it to observe (or to fail loudly) in
    /// tests and in the scene layer.
    var onIllegalTransition: ((GameState, GameState) -> Void)?

    private let menuState = MenuState()
    private let gameplayState = GameplayState()
    private let deathState = DeathState()
    private let highScoresState = HighScoresState()
    private let machine: GKStateMachine

    private static let log = Logger(
        subsystem: "com.cyberpunkmonstercrawl.CyberpunkMonsterCrawl",
        category: "GameStateMachine"
    )

    init(
        onChange: ((GameState) -> Void)? = nil,
        onIllegalTransition: ((GameState, GameState) -> Void)? = nil
    ) {
        self.onChange = onChange
        self.onIllegalTransition = onIllegalTransition
        machine = GKStateMachine(states: [menuState, gameplayState, deathState, highScoresState])
        // Every stored property is initialised above, so `self` may now be
        // handed to the states as their (weak) change-notification target.
        menuState.owner = self
        gameplayState.owner = self
        deathState.owner = self
        highScoresState.owner = self
        // First entry into a GKStateMachine is unconditional (there is no
        // current state yet for `isValidNextState` to consult), so this
        // always succeeds and establishes `.menu` as the starting state.
        // Result explicitly discarded (some SDK versions don't mark
        // `enter(_:)` `@discardableResult`) to avoid an "unused result"
        // build warning. Owners are wired first so a hook passed to `init`
        // sees this initial `.menu` entry too.
        _ = machine.enter(MenuState.self)
    }

    var currentState: GameState {
        // `machine.currentState` is `GKState?`; using `is` as a boolean
        // check (rather than a switch pattern) sidesteps any ambiguity
        // around type-casting patterns over an optional.
        if machine.currentState is MenuState { return .menu }
        if machine.currentState is GameplayState { return .gameplay }
        if machine.currentState is DeathState { return .death }
        if machine.currentState is HighScoresState { return .highScores }
        preconditionFailure("GameStateMachine has no current state after init")
    }

    /// Mirrors `GKStateMachine.canEnterState(_:)` without exposing the
    /// underlying `GKState` classes to callers.
    func canTransition(to state: GameState) -> Bool {
        machine.canEnterState(stateClass(for: state))
    }

    /// Mirrors `GKStateMachine.enter(_:)`. Returns `false` (and leaves
    /// `currentState` unchanged) for any transition not in the legal table;
    /// every rejection is reported through `reportIllegalTransition` so the
    /// no-op is never silent.
    @discardableResult
    func transition(to state: GameState) -> Bool {
        let from = currentState
        guard machine.enter(stateClass(for: state)) else {
            reportIllegalTransition(from: from, to: state)
            return false
        }
        return true
    }

    /// Called by the `GKState` subclasses on entry; forwards to `onChange`.
    fileprivate func stateDidEnter(_ state: GameState) {
        onChange?(state)
    }

    /// Surfaces a rejected transition. Deliberately a log rather than an
    /// unconditional `assertionFailure`: the transition table is a hard
    /// invariant that `GameStateMachineTests` exercises exhaustively —
    /// illegal pairs included — so trapping here would make the suite unable
    /// to assert the rejection contract at all. A DEBUG warning still puts
    /// the mis-wired button (e.g. a RUN AGAIN handler calling
    /// `transition(to: .highScores)` from `.death`) in the simulator console
    /// the instant it does nothing, instead of leaving it for QA; a consumer
    /// that wants a harder failure installs `onIllegalTransition`.
    private func reportIllegalTransition(from: GameState, to: GameState) {
        if let onIllegalTransition = onIllegalTransition {
            onIllegalTransition(from, to)
            return
        }
        #if DEBUG
        Self.log.warning(
            """
            Illegal GameState transition rejected: \
            \(String(describing: from), privacy: .public) -> \
            \(String(describing: to), privacy: .public); currentState unchanged.
            """
        )
        #endif
    }

    private func stateClass(for state: GameState) -> AnyClass {
        switch state {
        case .menu: return MenuState.self
        case .gameplay: return GameplayState.self
        case .death: return DeathState.self
        case .highScores: return HighScoresState.self
        }
    }
}
