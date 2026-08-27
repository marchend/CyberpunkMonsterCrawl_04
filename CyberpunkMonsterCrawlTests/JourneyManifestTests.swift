import Foundation
import SpriteKit
import XCTest
@testable import CyberpunkMonsterCrawl

/// The runtime probe reaches a story's on-screen work through
/// `.mothership/journeys/<name>.json` and nothing else: the gate runs a
/// journey only for the story named in its `stories` array, and a story with
/// no journey of its own falls back to a launch-only capture. That fallback
/// is indistinguishable, in the resulting screenshots, from the feature never
/// having been built -- which is exactly how `CYBERPUN-17-9` (auto-fire,
/// bullets, the weapon overlay) came back from product verification reported
/// as "nothing on screen" while every one of its unit tests was green and its
/// production wiring was live in `GameScene`.
///
/// These journeys are hand-edited JSON that no compiler ever sees, so a typo
/// in a key, a `screenshot` step with no `label`, a `navigate` step with no
/// `expect` (the probe then cannot tell "arrived" from "tapped something
/// else and the screen changed anyway"), or a whole missing file all fail
/// silently at verification time, days after the PR merged. This turns those
/// into a compile-time-adjacent, in-suite gate, the same way
/// `DocumentationParityTests` does for the two context files and
/// `AtlasContractConventionTests` does for the texture-crop convention.
///
/// Unreachable or empty inputs FAIL rather than skip, for the reason those
/// two gates already state: a gate that evaporates must not read as a green
/// suite.
final class JourneyManifestTests: XCTestCase {

    // MARK: - Locations

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
    }

    private var journeysDirectory: URL {
        repoRoot
            .appendingPathComponent(".mothership")
            .appendingPathComponent("journeys")
    }

    /// Step actions the iOS probe understands. A step naming anything else is
    /// a typo that would be skipped (or would abort the run) at verification
    /// time with no signal here.
    private static let supportedActions: Set<String> = [
        "wait",
        "screenshot",
        "assert_running",
        "navigate",
        "tap_at",
        "wait_for_element",
    ]

    /// The upper bound the mothership journey schema puts on a single `wait`
    /// step's `seconds`; a longer step is rejected (or silently clamped) by
    /// the probe at verification time, days after the PR merged.
    ///
    /// The cap is defined by the mothership runner's journey schema, which is
    /// external to this repo -- there is no schema file under `.mothership/`
    /// to read it from, so this constant is the single in-suite definition of
    /// it and `test_everyStep_...` asserts it per step. Every journey in the
    /// tree honours it today (`raccoon-swarm` and `auto-fire-weapons` sit at
    /// exactly 30, the highest in the tree).
    ///
    /// This is the other end of
    /// `test_theDeathJourneysWaitForElementSteps_areBackstoppedByADerivedFloorWait`:
    /// that gate sums *contiguous* `wait` steps precisely because this cap
    /// makes the derived ~30.7s death floor uncoverable by one step. Without
    /// the assertion below, the `30 + 6` split could be collapsed back into a
    /// single `wait: 36`, which would keep this file green while breaching the
    /// schema at verification time. Pinned from both ends instead of only
    /// explained in prose.
    private static let maximumWaitSeconds: TimeInterval = 30

    // MARK: - Loading

    private struct Journey {
        let fileName: String
        let json: [String: Any]

        var name: String { json["name"] as? String ?? "" }
        var stories: [String] { json["stories"] as? [String] ?? [] }
        var steps: [[String: Any]] { json["steps"] as? [[String: Any]] ?? [] }
    }

    private func loadJourneys(file: StaticString = #filePath, line: UInt = #line) -> [Journey] {
        let directory = journeysDirectory

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail(
                "\(directory.path) is not readable, so the journey gate is not running. "
                    + "Product verification reaches on-screen work only through these files.",
                file: file, line: line
            )
            return []
        }

        let jsonURLs = contents.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }

        // Anti-vacuity: every assertion below iterates this collection, so an
        // empty (or renamed/moved) directory would pass all of them.
        XCTAssertFalse(
            jsonURLs.isEmpty,
            "No journeys found in \(directory.path) -- every gate in this file would pass vacuously.",
            file: file, line: line
        )

        return jsonURLs.compactMap { url in
            guard
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data),
                let json = object as? [String: Any]
            else {
                XCTFail(
                    "\(url.lastPathComponent) is not a readable JSON object. A journey the probe "
                        + "cannot parse is a story with no runtime evidence at all.",
                    file: file, line: line
                )
                return nil
            }
            return Journey(fileName: url.lastPathComponent, json: json)
        }
    }

    // MARK: - Structural contract

    func test_everyJourney_carriesTheFieldsTheProbeAndTheReviewerBothNeed() {
        let journeys = loadJourneys()

        for journey in journeys {
            let file = journey.fileName

            XCTAssertFalse(journey.name.isEmpty, "\(file): a journey needs a non-empty \"name\".")

            let demonstrates = journey.json["demonstrates"] as? String ?? ""
            XCTAssertFalse(
                demonstrates.isEmpty,
                "\(file): \"demonstrates\" is the reviewer's brief -- the gate is human/vision "
                    + "review of the screenshots, so a frame with no stated claim cannot be judged."
            )

            XCTAssertFalse(
                journey.stories.isEmpty,
                "\(file): \"stories\" must name at least one story, or the gate never runs this "
                    + "journey for anything."
            )
            for story in journey.stories {
                XCTAssertFalse(story.isEmpty, "\(file): \"stories\" must not contain an empty id.")
            }

            XCTAssertFalse(journey.steps.isEmpty, "\(file): a journey with no steps captures nothing.")
        }
    }

    func test_everyStep_namesASupportedAction_andCarriesItsRequiredFields() {
        let journeys = loadJourneys()

        for journey in journeys {
            let file = journey.fileName
            var screenshotCount = 0

            for (index, step) in journey.steps.enumerated() {
                let position = "\(file) step \(index)"

                guard let action = step["action"] as? String, !action.isEmpty else {
                    XCTFail("\(position): every step needs a non-empty \"action\".")
                    continue
                }

                XCTAssertTrue(
                    Self.supportedActions.contains(action),
                    "\(position): \"\(action)\" is not a probe verb this project uses "
                        + "(\(Self.supportedActions.sorted().joined(separator: ", ")))."
                )

                switch action {
                case "screenshot":
                    screenshotCount += 1
                    let label = step["label"] as? String ?? ""
                    XCTAssertFalse(
                        label.isEmpty,
                        "\(position): a screenshot needs a \"label\" -- it is how the captured "
                            + "frame is named in the evidence bundle and referred to in review."
                    )

                case "navigate":
                    let target = step["target"] as? String ?? ""
                    XCTAssertFalse(
                        target.isEmpty,
                        "\(position): navigate needs a plain-language \"target\"; the probe locates "
                            + "the control visually, not by accessibility identifier."
                    )
                    let expect = step["expect"] as? String ?? ""
                    XCTAssertFalse(
                        expect.isEmpty,
                        "\(position): navigate needs an \"expect\" describing the DESTINATION state. "
                            + "Without it, a tap that misses PLAY and opens something else still "
                            + "\"changed the screen\", and the next screenshot is labelled gameplay "
                            + "while showing a menu."
                    )

                case "wait":
                    let seconds = (step["seconds"] as? NSNumber)?.doubleValue ?? 0
                    XCTAssertGreaterThan(
                        seconds, 0,
                        "\(position): a wait needs a positive \"seconds\"."
                    )
                    XCTAssertLessThanOrEqual(
                        seconds, Self.maximumWaitSeconds,
                        "\(position): a single wait may not exceed "
                            + "\(Self.maximumWaitSeconds)s (see maximumWaitSeconds -- the "
                            + "mothership journey schema's per-step cap). A longer floor wait "
                            + "must be split across consecutive wait steps, which "
                            + "test_theDeathJourneysWaitForElementSteps_areBackstoppedByADerivedFloorWait "
                            + "sums; a single over-cap step stays green here and is rejected or "
                            + "clamped by the probe at verification time."
                    )

                case "tap_at":
                    XCTAssertNotNil(step["x"] as? NSNumber, "\(position): tap_at needs an \"x\".")
                    XCTAssertNotNil(step["y"] as? NSNumber, "\(position): tap_at needs a \"y\".")

                case "wait_for_element":
                    let target = step["target"] as? String ?? ""
                    XCTAssertFalse(target.isEmpty, "\(position): wait_for_element needs a \"target\".")

                default:
                    break
                }
            }

            XCTAssertGreaterThan(
                screenshotCount, 0,
                "\(file): a journey with no screenshot produces no evidence for the gate to review."
            )
        }
    }

    // MARK: - Coverage

    /// The earliest moment after entering `.gameplay` at which a raccoon can
    /// be on screen at all, derived end-to-end from the production constants
    /// rather than from `initialSpawnInterval` alone.
    ///
    /// `RaccoonSpawnDirector` does not even *attempt* its first spawn until
    /// `initialSpawnInterval` (3s), and that spawn then lands off-screen and
    /// has to walk in. `farAxisMinimumTiles`' own doc comment derives the
    /// guaranteed gap: the lane-snapped near axis contributes at most its own
    /// bound plus `CityLatticeGenerator.period / 2` tiles, so
    /// `|dx - dy| >= farAxisMinimumTiles - (nearAxisRange bound + 3)` tiles,
    /// which `IsometricProjection` puts on screen at `tileHalfWidth` points
    /// per tile of that difference (`screenX = (dx - dy) * 48`) --
    /// `22 * 48 = 1_056` points at today's values. The swarm closes that at
    /// `RaccoonSeekBehavior.pointsPerSecond` (~121 pts/s), i.e. ~8.7s of walk
    /// on top of the 3s spawn delay, for a floor of ~11.7s.
    ///
    /// Every term is read from the type that owns it, so a retune of the
    /// spawn cadence, the spawn radius, the projection or the seek speed
    /// moves this floor with it instead of leaving a stale literal behind.
    /// This is deliberately the *floor* (the earliest a raccoon can appear),
    /// not the journey's chosen wait: the journeys budget margin on top of it
    /// for spawn jitter and the approach not being purely along screen-x.
    private static var secondsBeforeARaccoonCanBeOnScreen: TimeInterval {
        let nearAxisWorstCaseTiles = RaccoonSpawnDirector.nearAxisRange.upperBound
            + Double(CityLatticeGenerator.period) / 2
        let offScreenGapTiles = RaccoonSpawnDirector.farAxisMinimumTiles - nearAxisWorstCaseTiles
        let offScreenGapPoints = offScreenGapTiles * IsometricProjection.tileHalfWidth
        let walkInSeconds = offScreenGapPoints / RaccoonSeekBehavior.pointsPerSecond
        return RaccoonSpawnDirector.initialSpawnInterval + walkInSeconds
    }

    /// The earliest moment after entering `.gameplay` at which the player
    /// can be dead -- i.e. the earliest a death screen can exist for a
    /// `wait_for_element` to find -- derived from the production constants
    /// the same way `secondsBeforeARaccoonCanBeOnScreen` is.
    ///
    /// Nothing can damage the player before a raccoon is on screen at all,
    /// so that floor is the first term. From contact, `BiteComponent` seeds
    /// its cooldown at `biteIntervalSeconds` so the first bite lands on the
    /// frame contact is observed, and `N` bites therefore span `N - 1`
    /// intervals; `N` is `baseMaxHP / biteDamage` rounded up (20 bites of 5
    /// against 100 HP at today's values), for ~19s on top of the ~11.7s
    /// approach.
    ///
    /// Deliberately the *floor*, not the journey's chosen wait: the journey
    /// budgets margin on top of it, and a single biter is the slowest case
    /// (a fuller swarm only kills sooner), so nothing here claims to predict
    /// when death actually happens -- only that it cannot have happened
    /// before this.
    private static var secondsBeforeThePlayerCanBeDead: TimeInterval {
        let bitesToDrainFullHP = (Double(PlayerNode.baseMaxHP) / Double(BiteComponent.biteDamage))
            .rounded(.up)
        let drainSeconds = max(0, bitesToDrainFullHP - 1) * BiteComponent.biteIntervalSeconds
        return secondsBeforeARaccoonCanBeOnScreen + drainSeconds
    }

    /// `CYBERPUN-17-13`'s journey is the first in this tree to use
    /// `wait_for_element`, and the probe's default timeout for that verb is
    /// not documented anywhere here (PR #58 review). If that default is
    /// shorter than the run, the step falls through while the game is still
    /// in `.gameplay` and the next `screenshot` -- labelled
    /// `death-screen-summary` -- captures a gameplay frame instead, which is
    /// the same "empty rooftop reads as feature missing" failure the gate
    /// above exists for, one level subtler because the label asserts what
    /// the pixels do not show.
    ///
    /// So each `wait_for_element` must be backstopped by one or more explicit
    /// `wait` steps that together already cover the derived time-to-death:
    /// the element wait then
    /// only has to absorb the tail (spawn jitter, approach heading, swarm
    /// size), not the whole run. Overshoot costs nothing -- `DeathScreenNode`
    /// mounts no auto-dismiss, so the death screen stays up until a button
    /// is tapped -- which is what makes the floor safe to set from the
    /// production constants rather than guessed downward.
    ///
    /// Binding the literals to the derived floor is the point: a CI-speedup
    /// trim of the journey's waits, or a retune of the spawn cadence, seek
    /// speed, bite cadence, bite damage or player HP, fails here instead of
    /// silently mislabelling an evidence capture days later.
    ///
    /// The floor wait is summed over every contiguous `wait` step immediately
    /// preceding `wait_for_element`, not just the single previous step. The
    /// mothership schema caps a single `wait` step at `maximumWaitSeconds`
    /// (30s) -- pinned there and asserted per step by `test_everyStep_...`,
    /// so the premise this sum rests on is enforced in-suite rather than only
    /// stated here -- and the derived
    /// floor here (~30.7s) already exceeds that cap on its own, so the
    /// journey has to split its floor wait across two (or more) consecutive,
    /// schema-compliant `wait` steps -- summing only the immediately
    /// preceding step would make that split unrepresentable without either
    /// breaching the schema (a single step over 30s) or under-covering the
    /// floor (falling back to one short step).
    func test_theDeathJourneysWaitForElementSteps_areBackstoppedByADerivedFloorWait() {
        let journeys = loadJourneys()

        let deathJourneys = journeys.filter { $0.stories.contains("CYBERPUN-17-13") }
        XCTAssertFalse(
            deathJourneys.isEmpty,
            "No journey names CYBERPUN-17-13 in its \"stories\", so product verification has "
                + "nothing to run for the death-screen/high-scores work and falls back to a "
                + "launch-only capture."
        )

        for journey in deathJourneys {
            let file = journey.fileName
            var waitForElementSteps = 0

            for (index, step) in journey.steps.enumerated()
            where (step["action"] as? String) == "wait_for_element" {
                waitForElementSteps += 1

                // Walk backwards over every contiguous "wait" step immediately
                // preceding this wait_for_element and sum their "seconds".
                // A journey may need more than one schema-compliant wait step
                // (each <= `maximumWaitSeconds`, which `test_everyStep_...`
                // enforces per step) to cover a floor above that per-step cap.
                var floorStartIndex = index
                var summedSeconds: TimeInterval = 0
                while floorStartIndex > 0,
                      (journey.steps[floorStartIndex - 1]["action"] as? String) == "wait" {
                    floorStartIndex -= 1
                    summedSeconds += (journey.steps[floorStartIndex]["seconds"] as? NSNumber)?.doubleValue ?? 0
                }

                guard floorStartIndex < index else {
                    XCTFail(
                        "\(file) step \(index): wait_for_element must be immediately preceded by "
                            + "one or more floor \"wait\" steps. The probe's default element "
                            + "timeout is unknown here, and a fall-through captures a gameplay "
                            + "frame under a death-screen label."
                    )
                    continue
                }

                let stepRange = floorStartIndex == index - 1
                    ? "step \(floorStartIndex)"
                    : "steps \(floorStartIndex)-\(index - 1)"

                XCTAssertGreaterThanOrEqual(
                    summedSeconds,
                    Self.secondsBeforeThePlayerCanBeDead,
                    "\(file) \(stepRange): waits only \(summedSeconds)s (summed) before the "
                        + "wait_for_element that follows, but the player cannot be dead before "
                        + "\(Self.secondsBeforeThePlayerCanBeDead)s "
                        + "(no raccoon on screen before "
                        + "\(Self.secondsBeforeARaccoonCanBeOnScreen)s, then "
                        + "\(PlayerNode.baseMaxHP) HP drained at BiteComponent.biteDamage "
                        + "\(BiteComponent.biteDamage) every "
                        + "\(BiteComponent.biteIntervalSeconds)s). That leaves the whole run "
                        + "resting on an undocumented element-wait default."
                )
            }

            // Anti-vacuity: the loop above is the entire gate, so a journey
            // rewritten back to guessed `wait` durations -- or one that drops
            // the death capture altogether -- would pass it silently.
            XCTAssertGreaterThan(
                waitForElementSteps, 0,
                "\(file): names CYBERPUN-17-13 but uses no wait_for_element step, so this gate "
                    + "passes vacuously. The death screen is reached at a duration nobody can "
                    + "predict; if that is deliberately being guessed again, this gate needs "
                    + "rewriting rather than emptying."
            )
        }
    }

    /// Anti-vacuity for the gate above, mirroring
    /// `test_theOnScreenFloor_isStrictlyStrongerThanTheSpawnIntervalAlone`:
    /// the death floor must stay strictly stronger than the approach floor it
    /// builds on. If a retune ever collapsed the drain term (a one-bite kill,
    /// a zero bite interval), the assertion above would quietly weaken to
    /// "waited until a raccoon could be on screen" -- which is nowhere near
    /// the death screen the capture is labelled for.
    func test_theDeathFloor_isStrictlyStrongerThanTheApproachFloorAlone() {
        XCTAssertGreaterThan(
            Self.secondsBeforeThePlayerCanBeDead,
            Self.secondsBeforeARaccoonCanBeOnScreen,
            "The derived death floor (\(Self.secondsBeforeThePlayerCanBeDead)s) has collapsed onto "
                + "the on-screen floor (\(Self.secondsBeforeARaccoonCanBeOnScreen)s), so the "
                + "wait_for_element backstop no longer binds on the time the player actually "
                + "takes to die."
        )
    }

    /// `CYBERPUN-17-9`'s own journey. This story's visible work (the weapon
    /// overlay composited on the player, the swarm closing into weapon range)
    /// is only reachable well after PLAY -- `RaccoonSpawnDirector` does not
    /// even attempt its first spawn until `initialSpawnInterval` (3s), and a
    /// spawn lands at least ~1,056 points off-screen and then has to walk in.
    /// A journey that screenshots a few seconds after PLAY therefore captures
    /// an empty rooftop and reads as "feature missing", which is what
    /// happened before this file existed.
    ///
    /// Two things this gate is careful to bind on, because the obvious
    /// cheaper versions of it do not (PR #45 review):
    ///
    /// 1. **The waits counted are the ones before the FIRST capture that
    ///    follows `navigate`**, not every wait after `navigate`. A total
    ///    would let `navigate -> screenshot -> wait 30` pass while
    ///    screenshotting the frame immediately after PLAY -- exactly the
    ///    empty-rooftop failure described above.
    /// 2. **The threshold is `secondsBeforeARaccoonCanBeOnScreen`**, not
    ///    `initialSpawnInterval`. 3s only gets the swarm *spawned*, ~1,056
    ///    points off-screen; it is nowhere near enough for one to be in
    ///    frame. Gating on 3s would leave a CI-speedup trim of the journey's
    ///    30s wait down to 4s green.
    func test_aJourneyExistsForThisStorysCombatWork_andDrivesIntoGameplayBeforeCapturing() {
        let journeys = loadJourneys()

        let combatJourneys = journeys.filter { $0.stories.contains("CYBERPUN-17-9") }
        XCTAssertFalse(
            combatJourneys.isEmpty,
            "No journey names CYBERPUN-17-9 in its \"stories\", so product verification has nothing "
                + "to run for the auto-fire/weapon work and falls back to a launch-only capture."
        )

        for journey in combatJourneys {
            let file = journey.fileName

            // Indexed over `steps` itself, not over a compacted action list:
            // a step missing its "action" key (already failed above) would
            // otherwise shift every subsequent index.
            guard let navigateIndex = journey.steps.firstIndex(
                where: { ($0["action"] as? String) == "navigate" }
            ) else {
                XCTFail("\(file): must navigate past the menu -- the combat work is not on the menu.")
                continue
            }

            let stepsAfterNavigate = Array(journey.steps.dropFirst(navigateIndex + 1))

            guard let firstCaptureIndex = stepsAfterNavigate.firstIndex(
                where: { ($0["action"] as? String) == "screenshot" }
            ) else {
                XCTFail("\(file): must screenshot after entering gameplay.")
                continue
            }

            // Only the waits that precede the FIRST post-navigate capture can
            // put a raccoon in that frame. Summing every wait after
            // `navigate` -- including the ones between later screenshots --
            // would pass a journey reordered to
            // `navigate -> screenshot -> wait 30`, which captures the frame
            // immediately after PLAY.
            let waitSecondsBeforeFirstCapture = stepsAfterNavigate
                .prefix(firstCaptureIndex)
                .filter { ($0["action"] as? String) == "wait" }
                .compactMap { ($0["seconds"] as? NSNumber)?.doubleValue }
                .reduce(0, +)

            XCTAssertGreaterThanOrEqual(
                waitSecondsBeforeFirstCapture,
                Self.secondsBeforeARaccoonCanBeOnScreen,
                "\(file): waits only \(waitSecondsBeforeFirstCapture)s between navigate and its "
                    + "first screenshot, but no raccoon can be on screen before "
                    + "\(Self.secondsBeforeARaccoonCanBeOnScreen)s "
                    + "(RaccoonSpawnDirector.initialSpawnInterval "
                    + "\(RaccoonSpawnDirector.initialSpawnInterval)s, then the guaranteed "
                    + "off-screen spawn gap walked in at RaccoonSeekBehavior.pointsPerSecond "
                    + "\(RaccoonSeekBehavior.pointsPerSecond) pts/s). That frame is an empty "
                    + "rooftop, and an empty rooftop reads as \"feature missing\"."
            )
        }
    }

    /// Anti-vacuity for the gate above: the derived floor must actually be
    /// stronger than the `initialSpawnInterval` it replaced. If a retune ever
    /// collapses the spawn radius or inflates the seek speed to the point
    /// where the walk-in term vanishes, the assertion above would silently
    /// weaken back to "waited past the spawn attempt" -- the exact gate that
    /// let a 4s wait through.
    func test_theOnScreenFloor_isStrictlyStrongerThanTheSpawnIntervalAlone() {
        XCTAssertGreaterThan(
            Self.secondsBeforeARaccoonCanBeOnScreen,
            RaccoonSpawnDirector.initialSpawnInterval,
            "The derived on-screen floor (\(Self.secondsBeforeARaccoonCanBeOnScreen)s) has "
                + "collapsed onto RaccoonSpawnDirector.initialSpawnInterval "
                + "(\(RaccoonSpawnDirector.initialSpawnInterval)s), so the journey timing gate no "
                + "longer binds on the walk-in time the journeys actually depend on."
        )
    }
}
