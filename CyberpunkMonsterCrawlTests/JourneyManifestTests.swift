import Foundation
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
