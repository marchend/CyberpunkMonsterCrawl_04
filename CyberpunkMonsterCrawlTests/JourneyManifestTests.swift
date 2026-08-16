import XCTest

/// Repo-invariant scan over the `.mothership/journeys/*.json`
/// product-verification manifests (CYBERPUN-17-5-t5 review follow-up).
///
/// The failure mode this closes is **silent**: when a journey's
/// `demonstrates` field grows too long the journey probe skips the journey
/// entirely, so only the launch screen is captured and the run still
/// reports green. Nothing goes red, so a prose reminder in `AGENT.md`
/// cannot catch the next edit that re-breaks it — the over-long text this
/// story replaced was itself written one clarifying sentence at a time.
///
/// Same shape as this repo's other checked-in-file gates
/// (`NoBuildingGeometryConstructionTests`,
/// `AtlasCatalogNoExtraneousAssetsTests`): walk up from `#filePath` to the
/// repo root, read what is actually on disk, and **fail** rather than skip
/// quietly when the scanned directory is unreachable or the glob matches
/// nothing — otherwise this gate passes vacuously, which is the same
/// silent-green failure it exists to prevent.
final class JourneyManifestTests: XCTestCase {

    // MARK: - Budgets

    /// Length ceiling for a journey's `demonstrates` field.
    ///
    /// **This is an observed-safe ceiling, not a sourced hard limit.** The
    /// probe that skips over-long journeys lives outside this repository and
    /// publishes no figure that anything checked in here can cite, so the
    /// number below is calibrated from what this story actually observed:
    /// the ~1,300-character `demonstrates` that CYBERPUN-17-5-t5 replaced was
    /// skipped, and the ~480-character rewrite runs. 500 is the conservative
    /// round figure above the text that is known to work and far below the
    /// text that is known to fail. Treat it as a budget this repo chooses to
    /// hold itself to, not as a documented external contract; if the real
    /// limit is ever published, cite it here and adjust.
    ///
    /// **Unit:** deliberately enforced twice, because the external limit's
    /// unit is unknown — once in `String.count` (Swift characters / grapheme
    /// clusters) and once in UTF-8 **bytes**. Today's journey text is plain
    /// ASCII, where the two agree; a future edit that reaches for a typographic
    /// dash or a non-breaking space would make bytes outrun characters, and
    /// the byte assertion is what keeps that from quietly eating the margin.
    static let demonstratesBudget = 500

    /// Ceiling on the whole serialized journey file, for the case where the
    /// external cap applies to the serialized journey rather than to the
    /// `demonstrates` field alone — otherwise a journey could stay well
    /// inside the field budget and still be skipped because `steps` grew.
    /// Same status as above: an observed-safe ceiling, in UTF-8 bytes, with
    /// generous headroom over the ~1KB the current manifest occupies.
    static let serializedJourneyByteBudget = 2_000

    // MARK: - Locating the manifests

    private var journeysDirectory: URL {
        // ".../CyberpunkMonsterCrawlTests/JourneyManifestTests.swift"
        // -> repo root -> .mothership/journeys
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(".mothership")
            .appendingPathComponent("journeys")
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func journeyFiles() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: journeysDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Anti-vacuity

    /// If the directory moves or the extension filter stops matching, every
    /// other test in this file would iterate an empty list and pass. This one
    /// fails instead.
    func test_journeysDirectory_isReachable_andHoldsAtLeastOneJourney() {
        XCTAssertTrue(
            directoryExists(journeysDirectory),
            "\(journeysDirectory.path) is not reachable, so the whole journey-manifest gate is not running."
        )

        let files = journeyFiles()
        XCTAssertGreaterThanOrEqual(
            files.count,
            1,
            "Expected at least one .mothership/journeys/*.json manifest (menu-to-gameplay.json at minimum), "
                + "found \(files.count) — this gate would otherwise pass vacuously."
        )
    }

    // MARK: - The gate

    func test_everyJourney_hasADemonstratesFieldWithinBudget_inBothCharactersAndUTF8Bytes() throws {
        guard directoryExists(journeysDirectory) else {
            throw XCTSkip("Journeys directory not reachable; see test_journeysDirectory_isReachable_andHoldsAtLeastOneJourney.")
        }

        var offenders: [String] = []
        for fileURL in journeyFiles() {
            let name = fileURL.lastPathComponent

            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                offenders.append("\(name): unreadable or not a JSON object")
                continue
            }

            guard let demonstrates = json["demonstrates"] as? String else {
                offenders.append("\(name): no string \"demonstrates\" field — the probe has nothing to act on")
                continue
            }

            if demonstrates.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                offenders.append("\(name): \"demonstrates\" is empty")
                continue
            }

            if demonstrates.count > Self.demonstratesBudget {
                offenders.append(
                    "\(name): \"demonstrates\" is \(demonstrates.count) characters, over the "
                        + "\(Self.demonstratesBudget)-character budget — an over-long journey is SKIPPED by the "
                        + "probe, capturing only the launch screen while the run still reports green."
                )
            }

            if demonstrates.utf8.count > Self.demonstratesBudget {
                offenders.append(
                    "\(name): \"demonstrates\" is \(demonstrates.utf8.count) UTF-8 bytes, over the "
                        + "\(Self.demonstratesBudget)-byte budget — non-ASCII punctuation costs more bytes than "
                        + "characters, so the byte count is the one that runs out first."
                )
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Journey manifest budget violations:\n" + offenders.joined(separator: "\n"))
    }

    func test_everyJourney_hasANameAndNonEmptySteps_eachCarryingAnAction() throws {
        guard directoryExists(journeysDirectory) else {
            throw XCTSkip("Journeys directory not reachable; see test_journeysDirectory_isReachable_andHoldsAtLeastOneJourney.")
        }

        var offenders: [String] = []
        for fileURL in journeyFiles() {
            let name = fileURL.lastPathComponent

            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                offenders.append("\(name): unreadable or not a JSON object")
                continue
            }

            if (json["name"] as? String)?.isEmpty ?? true {
                offenders.append("\(name): missing or empty \"name\"")
            }

            guard let steps = json["steps"] as? [[String: Any]] else {
                offenders.append("\(name): missing \"steps\" array")
                continue
            }

            if steps.isEmpty {
                offenders.append("\(name): \"steps\" is empty — the journey would run nothing and still pass")
                continue
            }

            for (index, step) in steps.enumerated() where (step["action"] as? String)?.isEmpty ?? true {
                offenders.append("\(name): step \(index) has no \"action\"")
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Journey manifest structure violations:\n" + offenders.joined(separator: "\n"))
    }

    func test_everySerializedJourney_staysWithinTheByteBudget() throws {
        guard directoryExists(journeysDirectory) else {
            throw XCTSkip("Journeys directory not reachable; see test_journeysDirectory_isReachable_andHoldsAtLeastOneJourney.")
        }

        var offenders: [String] = []
        for fileURL in journeyFiles() {
            guard let data = try? Data(contentsOf: fileURL) else {
                offenders.append("\(fileURL.lastPathComponent): unreadable")
                continue
            }

            if data.count > Self.serializedJourneyByteBudget {
                offenders.append(
                    "\(fileURL.lastPathComponent): \(data.count) bytes, over the "
                        + "\(Self.serializedJourneyByteBudget)-byte serialized budget."
                )
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Serialized journey budget violations:\n" + offenders.joined(separator: "\n"))
    }

    /// Pins the budget rule itself, independent of what the manifests
    /// currently contain, so the gate keeps meaning something even if every
    /// journey file were deleted tomorrow.
    func test_budgets_areOrderedAndPositive() {
        XCTAssertGreaterThan(Self.demonstratesBudget, 0)
        XCTAssertGreaterThan(
            Self.serializedJourneyByteBudget,
            Self.demonstratesBudget,
            "A serialized journey contains its own demonstrates field, so the file budget must exceed the field budget."
        )
    }
}
