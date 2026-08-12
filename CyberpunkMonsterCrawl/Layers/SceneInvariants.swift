import CoreGraphics
import SpriteKit
import os

/// One layer container plus the `LayerConstants` band its whole subtree must
/// stay inside. `baseZ` is the container's own *cumulative* zPosition (for
/// `uiLayer`, that includes the camera it hangs off), because SpriteKit
/// accumulates `zPosition` down the tree.
private struct LayerBand {
    let name: String
    let root: SKNode
    let baseZ: CGFloat
    /// The layer's inclusive band, taken straight from `LayerConstants` so
    /// this audit and `DepthModel.isWithinWorldBand(_:)` share one
    /// containment rule instead of each spelling out its own comparison.
    let zRange: ClosedRange<CGFloat>

    func contains(_ cumulativeZ: CGFloat) -> Bool {
        zRange.contains(cumulativeZ)
    }
}

/// Runtime audits for the two structural invariants this feature exists to
/// protect, so that "the UI always wins" is checked for *every* node in the
/// graph rather than only for the three container nodes.
///
/// Both audits are plain functions so tests can drive them with hostile
/// input (a UI child with a large negative `zPosition`, a world child with a
/// large positive one, a node that opts into UIKit touch delivery), and both
/// are wired into `enforceSceneInvariants()`, which `GameScene` runs when a
/// screen is mounted, when the ground plane mounts, when the scene is
/// presented and on every dispatched touch. A future screen that violates
/// either contract is reported at the moment it is added instead of silently
/// reproducing the v1 "world paints over UI" / "dead button" bugs with a
/// green suite.
///
/// **Every line below compiles into Release** (`CYBERPUN-17-4-t6`). The audits
/// used to be reachable only through an `#if DEBUG` `assertSceneInvariants()`,
/// which meant the one build configuration nobody could audit was the one the
/// product actually ships and the runtime probe actually drives: a regression
/// that only manifests in an optimized build would trip loudly in every
/// Debug test run and then ship in silence. Now the audit *runs* in both
/// configurations and only the *reaction* differs \u2014 `assert` in DEBUG (fail
/// fast, at the offending mount), a non-fatal `os.Logger` fault plus the
/// `GameScene.onSceneInvariantViolation` hook in Release. Crashing a shipped
/// build over a caught invariant would be worse than the bug it catches.
/// `SceneInvariantsTests` pins both halves, including a source scan that
/// fails if any of this machinery is put back behind `#if DEBUG`.
extension GameScene {

    private var auditedBands: [LayerBand] {
        [
            LayerBand(
                name: "worldLayer",
                root: worldLayer,
                baseZ: worldLayer.zPosition,
                zRange: LayerConstants.worldBand
            ),
            LayerBand(
                name: "effectsLayer",
                root: effectsLayer,
                baseZ: effectsLayer.zPosition,
                zRange: LayerConstants.effectsBand
            ),
            LayerBand(
                name: "uiLayer",
                root: uiLayer,
                baseZ: cameraNode.zPosition + uiLayer.zPosition,
                zRange: LayerConstants.uiBand
            ),
        ]
    }

    // MARK: - Layer-band audit

    /// Every node in the three layer subtrees whose *cumulative* zPosition
    /// escapes its layer's declared band - i.e. every node that could paint
    /// outside the ordering `worldLayer < effectsLayer < uiLayer` promises.
    /// Empty means the invariant holds for the whole graph.
    func nodesEscapingTheirLayerBand() -> [SKNode] {
        var offenders: [SKNode] = []
        for band in auditedBands {
            if !band.contains(band.baseZ) {
                offenders.append(band.root)
            }
            collectBandEscapees(in: band, under: band.root, cumulativeZ: band.baseZ, into: &offenders)
        }
        return offenders
    }

    private func collectBandEscapees(
        in band: LayerBand,
        under node: SKNode,
        cumulativeZ: CGFloat,
        into offenders: inout [SKNode]
    ) {
        for child in node.children {
            let childZ = cumulativeZ + child.zPosition
            if !band.contains(childZ) {
                offenders.append(child)
            }
            collectBandEscapees(in: band, under: child, cumulativeZ: childZ, into: &offenders)
        }
    }

    /// Human-readable form of `nodesEscapingTheirLayerBand()`, used in
    /// assertion messages and test failure output.
    func layerBandViolationReport() -> [String] {
        var report: [String] = []
        for band in auditedBands {
            if !band.contains(band.baseZ) {
                report.append(
                    "\(band.name) itself at cumulative z \(band.baseZ), "
                        + "band \(band.zRange.lowerBound)...\(band.zRange.upperBound)"
                )
            }
            collectBandViolationDescriptions(in: band, under: band.root, cumulativeZ: band.baseZ, into: &report)
        }
        return report
    }

    private func collectBandViolationDescriptions(
        in band: LayerBand,
        under node: SKNode,
        cumulativeZ: CGFloat,
        into report: inout [String]
    ) {
        for child in node.children {
            let childZ = cumulativeZ + child.zPosition
            if !band.contains(childZ) {
                report.append(
                    "\(describe(child)) under \(band.name) at cumulative z \(childZ), "
                        + "band \(band.zRange.lowerBound)...\(band.zRange.upperBound)"
                )
            }
            collectBandViolationDescriptions(in: band, under: child, cumulativeZ: childZ, into: &report)
        }
    }

    // MARK: - Sole-dispatcher audit

    /// Every node that has opted into UIKit touch delivery
    /// (`isUserInteractionEnabled == true`). UIKit hands such a node the
    /// touch *before* `SKScene.touchesBegan(_:with:)` runs, so it bypasses
    /// `routeTouch(at:)` and the UI-first guarantee with it. The contract is
    /// that this list is always empty and the scene dispatches every touch
    /// itself to a `TouchResponder` - see `TouchResponder`.
    func nodesBypassingSceneTouchDispatch() -> [SKNode] {
        var offenders: [SKNode] = []
        for root in [worldLayer, effectsLayer, uiLayer] {
            if root.isUserInteractionEnabled {
                offenders.append(root)
            }
            collectInteractionEnabledNodes(under: root, into: &offenders)
        }
        return offenders
    }

    private func collectInteractionEnabledNodes(under node: SKNode, into offenders: inout [SKNode]) {
        for child in node.children {
            if child.isUserInteractionEnabled {
                offenders.append(child)
            }
            collectInteractionEnabledNodes(under: child, into: &offenders)
        }
    }

    private func describe(_ node: SKNode) -> String {
        node.name.map { "\($0) (\(type(of: node)))" } ?? "\(type(of: node))"
    }

    // MARK: - Enforcement (every build configuration)

    private static let invariantLog = Logger(
        subsystem: "com.cyberpunkmonstercrawl.CyberpunkMonsterCrawl",
        category: "SceneInvariants"
    )

    /// Both invariants' violations as one human-readable list, in the order
    /// they are audited (layer bands, then touch dispatch). Empty means the
    /// whole graph satisfies both contracts.
    ///
    /// The two audits are walked exactly once each, which is why this is the
    /// single source both the DEBUG assertion message and the Release log
    /// read from - the previous DEBUG-only assertion walked the
    /// touch-dispatch subtree twice (once for the condition, once for the
    /// message) and could not be shared with a non-fatal path at all.
    func sceneInvariantViolations() -> [String] {
        var violations = layerBandViolationReport().map { "layer band escaped: \($0)" }
        violations += nodesBypassingSceneTouchDispatch().map {
            "touch dispatch bypassed: \(describe($0)) sets isUserInteractionEnabled"
        }
        return violations
    }

    /// Runs both audits and *reports* whatever they find - non-fatally, in
    /// **every** build configuration: an `os.Logger` fault (so a Release
    /// build on a real device surfaces the violation in the console instead
    /// of hiding it) plus `GameScene.onSceneInvariantViolation`. Returns the
    /// violations so a caller can react.
    ///
    /// This is the whole of the Release enforcement path, and it is
    /// deliberately free of `#if DEBUG`: a shipped build audits the same
    /// graph, by the same rule, as a Debug test run.
    @discardableResult
    func reportSceneInvariantViolations() -> [String] {
        let violations = sceneInvariantViolations()
        guard !violations.isEmpty else { return [] }

        let summary = violations.joined(separator: "; ")
        Self.invariantLog.fault("Scene invariant violated: \(summary, privacy: .public)")
        onSceneInvariantViolation?(violations)
        return violations
    }

    /// The audit entry point every `GameScene` call site uses: reports the
    /// violations in all configurations (see
    /// `reportSceneInvariantViolations()`) and, in DEBUG only, additionally
    /// trips an `assert` so a violation fails the suite / breaks in the
    /// debugger at the offending mount rather than scrolling past in a log.
    ///
    /// Called at the moments the scene graph *changes* - screen mounted,
    /// ground plane mounted, scene presented - plus once per dispatched
    /// touch, all of which are user-paced. It walks the whole world subtree
    /// (thousands of ground nodes once a run is streaming), so it must never
    /// be called from `update(_:)`: a future story that dispatches touches
    /// per frame (a thumbstick drag, `CYBERPUN-17-7`) should route through
    /// `routeTouch(at:)` directly instead of re-auditing every frame.
    @discardableResult
    func enforceSceneInvariants(file: StaticString = #file, line: UInt = #line) -> [String] {
        let violations = reportSceneInvariantViolations()
        #if DEBUG
        assert(
            violations.isEmpty,
            "Scene invariant violated: " + violations.joined(separator: "; "),
            file: file,
            line: line
        )
        #endif
        return violations
    }
}
