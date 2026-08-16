import XCTest

/// AC8 of CYBERPUN-17-5-t2: "no geometry construction" \u2014 buildings are whole
/// pre-rendered sprites (`docs/bootstrap.md`: "Whole pre-rendered building
/// sprites, never assembled in code"), never assembled per-face,
/// per-storey, or as a procedurally-drawn prism in Swift. This is a plain
/// source scan over checked-in `.swift` sources (the same shape
/// `AtlasCatalogNoExtraneousAssetsTests` uses for its catalog scan), not a
/// SpriteKit-runtime test, so it needs no live scene.
final class NoBuildingGeometryConstructionTests: XCTestCase {

    /// Substrings that would indicate a building is being assembled from
    /// primitive drawing calls rather than loaded whole from the shipped
    /// art. Deliberately concrete API/identifier tokens \u2014 not the bare
    /// English words "storey"/"face"/"prism", which already appear in this
    /// PR's own doc comments (`BuildingCatalog.HeightClass`,
    /// `BuildingSprite.HeightClass`: "~1 storey", "~4 storey") and inside
    /// ordinary identifiers (`Chunk.placementSurface` contains "face") \u2014
    /// those would make this gate fail on prose it should never touch.
    private static let forbiddenGeometrySubstrings: [String] = [
        "SKShapeNode",
        "UIBezierPath",
        "CGMutablePath",
        "CAShapeLayer",
        "CGPath(",
        "perFace",
        "per-face",
        "perStorey",
        "per-storey",
        "buildingPrism",
    ]

    /// Files that are building-related even though their own filename does
    /// not contain "building" \u2014 the rendering/depth primitives this PR adds.
    private static let explicitBuildingRelatedFilenames: Set<String> = [
        "TileFieldRenderer.swift",
        "IsometricDepthSorting.swift",
        "BuildingObstruction.swift",
    ]

    private var sourcesDirectory: URL {
        // ".../CyberpunkMonsterCrawlTests/NoBuildingGeometryConstructionTests.swift"
        // -> repo root -> CyberpunkMonsterCrawl/Sources
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("CyberpunkMonsterCrawl")
            .appendingPathComponent("Sources")
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func allSwiftFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func isBuildingRelated(_ fileURL: URL) -> Bool {
        let name = fileURL.lastPathComponent
        if Self.explicitBuildingRelatedFilenames.contains(name) { return true }
        return name.lowercased().contains("building")
    }

    func test_sourcesDirectory_isReachable() {
        XCTAssertTrue(
            directoryExists(sourcesDirectory),
            "\(sourcesDirectory.path) is not reachable, so this whole gate is not running."
        )
    }

    func test_buildingRelatedFiles_containNoPerFaceOrPerStoreyOrPrismGeometryConstruction() throws {
        guard directoryExists(sourcesDirectory) else {
            throw XCTSkip("Sources directory not reachable; see test_sourcesDirectory_isReachable.")
        }

        let buildingRelatedFiles = allSwiftFiles(under: sourcesDirectory).filter(isBuildingRelated)
        // Anti-vacuity guard: BuildingCatalog/BuildingPlacement/BuildingSprite
        // plus this PR's own three new files, at minimum.
        XCTAssertGreaterThanOrEqual(
            buildingRelatedFiles.count,
            6,
            "Expected at least six building-related source files to be scanned, found "
                + "\(buildingRelatedFiles.count) - this gate would otherwise pass vacuously."
        )

        var offenders: [String] = []
        for fileURL in buildingRelatedFiles {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                offenders.append("\(fileURL.lastPathComponent): unreadable")
                continue
            }
            for forbidden in Self.forbiddenGeometrySubstrings where contents.contains(forbidden) {
                offenders.append(
                    "\(fileURL.lastPathComponent) contains forbidden geometry-construction marker \"\(forbidden)\""
                )
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Buildings are whole pre-rendered sprites, never assembled in code:\n" + offenders.joined(separator: "\n")
        )
    }

    func test_tilesetStructure_appearsNowhereInSources() throws {
        guard directoryExists(sourcesDirectory) else {
            throw XCTSkip("Sources directory not reachable; see test_sourcesDirectory_isReachable.")
        }

        var offenders: [String] = []
        for fileURL in allSwiftFiles(under: sourcesDirectory) {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if contents.lowercased().contains("tileset_structure") {
                offenders.append(fileURL.lastPathComponent)
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "\"tileset_structure\" (the opaque source-of-record showcase sheet) must never be referenced from "
                + "Sources/: \(offenders.joined(separator: ", "))"
        )
    }
}
