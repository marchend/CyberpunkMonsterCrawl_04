import GameplayKit

/// The game's top-level state, per docs/bootstrap.md:
/// `menu -> gameplay -> death -> highScores` (plus the RUN AGAIN and
/// back-to-menu paths spelled out below). This enum is the public,
/// scene/rendering-agnostic surface; `GameStateMachine` wraps the
/// `GKStateMachine` implementation detail behind it.
enum GameState: CaseIterable, Equatable {
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
final class MenuState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == GameplayState.self || stateClass == HighScoresState.self
    }
}

final class GameplayState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == DeathState.self
    }
}

final class DeathState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == GameplayState.self || stateClass == MenuState.self
    }
}

final class HighScoresState: GKState {
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == MenuState.self
    }
}

/// Thin, scene/rendering-agnostic wrapper around `GKStateMachine` exposing
/// the game's four states as the `GameState` enum instead of leaking the
/// `GKState` subclasses to callers. Starts in `.menu`.
final class GameStateMachine {
    private let menuState = MenuState()
    private let gameplayState = GameplayState()
    private let deathState = DeathState()
    private let highScoresState = HighScoresState()
    private let machine: GKStateMachine

    init() {
        machine = GKStateMachine(states: [menuState, gameplayState, deathState, highScoresState])
        // First entry into a GKStateMachine is unconditional (there is no
        // current state yet for `isValidNextState` to consult), so this
        // always succeeds and establishes `.menu` as the starting state.
        // Result explicitly discarded (some SDK versions don't mark
        // `enter(_:)` `@discardableResult`) to avoid an "unused result"
        // build warning.
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
    /// `currentState` unchanged) for any transition not in the legal table.
    @discardableResult
    func transition(to state: GameState) -> Bool {
        machine.enter(stateClass(for: state))
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
