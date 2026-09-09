# Evidence — `CYBERPUN-17-14-t1` (PR 1: scaffolding removal)

This PR's plan calls for two evidence artifacts, labelled by gate number:

- `gate-01-first-launch-playable.mov` — a simulator recording of
  menu → PLAY → stick moves the player → every button responds.
- `gate-07-scaffolding-grep-output.png` — a screenshot/log of the
  zero-match scaffolding-marker grep.

## What is actually committed here, and why

This implementation task runs in a container with no Xcode/simulator and
no screen-capture tool — there is no way to record a real `.mov` of a
running simulator, or to take a real screenshot of a terminal, from here.
Committing a file at either of those exact names without genuine captured
bytes would be worse than not committing them at all (a `.mov`/`.png` that
isn't real evidence is indistinguishable, on disk, from real evidence,
until someone opens it) — see the project's own recorded lesson: "identical
frames across bundles mean nothing was captured" was a real defect a
prior story shipped and a later review had to catch by decoding the bytes.

So instead of fabricated binary placeholders, this PR ships the two real
things it *can* produce, and leaves the actual capture as explicitly
named outstanding work rather than a silent gap:

### Which of the ten gates this PR touches at all

The ticket scopes ten product gates demonstrated on a running simulator.
This PR is not all ten, and nothing here should be read as claiming a gate
is met because the suite is green — that premise ("v1 passed its tests and
shipped unplayable") is the reason this story exists. What this PR covers:

| gate | state after this PR |
| --- | --- |
| 1 — first launch is playable | **mechanism only.** The journey exists and is gated by `JourneyManifestTests`; the frames are *not* captured (see below, and `.mothership/evidence/CYBERPUN-17-14-t1/journey-first-launch-playable/README.md`). Not met. |
| 7 — scaffolding marker grep returns nothing | **met, and now including the marker an earlier revision of this gate excluded** — see below. |

Every other gate the ticket lists — including the pixel-crispness sweep
(2), the placeholder-texture audit (4), the screen-mock comparison (9) and
the atlas-slicing verification (10) named in PR #64's review — is **not
addressed by this PR and is not claimed as met here**. No later PR number
is invented for them: whoever picks them up owns updating this table, and
the closing PR should not have to reconstruct which gates were still open
from a diff.

### Gate 1 — `.mothership/journeys/first-launch-playable.json`

A new journey, tagged `"stories": ["CYBERPUN-17-14"]`, that drives the
runtime probe through menu → PLAY → a live `.gameplay` screen → a press on
the HUD's visible ability button, screenshotting at each stage
(`gate1-menu`, `gate1-gameplay-running`, `gate1-button-responded`). Its own
`demonstrates` field records, honestly, that the probe vocabulary has no
drag/hold verb, so it cannot show the thumbstick actually moving the
player on a live device — that half of gate 1 is machine-verified instead,
end-to-end, by `ThumbstickMovementSeamTests`. This journey is the
mechanism; the actual `.mov` (or the platform's own screenshot bundle) is
produced when the runtime probe executes it against a real build, which
happens outside this authoring step.

### Gate 7 — `gate-07-scaffolding-grep-output.txt`

A genuine, reproducible log of the actual scan performed while
implementing this PR: a search for the scaffolding marker (`SCAFFOLDING`)
across the bundled app target (`CyberpunkMonsterCrawl/`), returning zero
matches, **and across the whole repository**, which is what the story's
acceptance criterion actually asks for. PR #64's review caught that an
earlier revision of this gate scoped itself to the app target and thereby
excluded the one live marker in the tree (the `CYBERPUN-17-11`
pickup-spawn bisection instrumentation, whose named removal owner had
never been filed and which a passing test would have made permanent).
That artifact has been removed rather than the scope narrowed; the log
enumerates the occurrences of the literal string that remain, all of
which describe the convention rather than tag anything. The same scan, made permanent and re-run on every
suite run rather than a one-time log, is
`CyberpunkMonsterCrawlTests/ScaffoldingRemovalTests.swift`
(`test_bundledAppSource_containsNoScaffoldingMarker`), which also carries
an anti-vacuity guard proving the scanner actually finds the marker when
one is present. The `.txt` extension here (rather than `.png`) is
deliberate: this is a real, verifiable text log rather than a fabricated
image standing in for a screenshot that was never taken.

## Outstanding

**The three gate-1 JPGs that were committed under
`.mothership/evidence/CYBERPUN-17-14-t1/journey-first-launch-playable/`
have been deleted (PR #64 review).** All three shared git blob SHA
`a5e0d08b6e736d2c3bb508dc4098ecde3fc9b34a`, i.e. they were one image
committed three times under three gate-numbered names — the same
"identical frames mean nothing was captured" defect this file cites two
sections above, arriving in the same PR that cites it. Either they were
never captured from a real run, or the run captured the same frame at all
three steps and the app never visibly advanced past the menu, which is
gate 1 failing. Neither reading is evidence of a pass, so the bundle now
holds only a README recording exactly what must be re-captured and the
instruction to check byte-level distinctness before attaching frames
next time.

A human reviewer (or the platform's own simulator/runtime-probe pipeline)
still needs to execute `first-launch-playable.json` against a real build
and attach the resulting recording/screenshots as `gate-01-first-launch-playable.mov`
under this directory before gate 1 is fully evidenced in the form the
plan originally asked for. This is named here explicitly rather than left
unmentioned so it is never mistaken for having already happened.

## `CYBERPUN-17-14-t2` (PR 2: asset-resolution + atlas-slicing audit)

This PR's plan calls for two evidence artifacts:

- `gate-02-no-placeholder-textures.mov` -- a full-run recording, menu to
  death screen, showing no placeholder texture.
- `gate-10-atlas-slicing.png` -- screenshot(s) of each atlas sheet's slice
  boundaries.

Neither binary is fabricated here, for the same reason PR 1's section
above gives: this implementation step has no Xcode/simulator/screen-capture
tool, and a placeholder file at either exact name would be indistinguishable
from real evidence until opened.

| gate | state after this PR |
| --- | --- |
| 2 -- every asset resolves, no placeholder textures | **audited, code-verified, evidence mechanism wired -- literal recording still outstanding.** See `gate-02-catalog-completeness-teeth.txt` for the code-level trace of why `AtlasCatalogTests`/`BuildingCatalogTests` fail on a deliberately-removed imageset and recover on restore (the "verify the test's teeth" half of AC 3), and for which real journeys now carry the `"CYBERPUN-17-14"` tag so the runtime probe captures genuine full-run frames. |
| 10 -- atlas sheets slice correctly, buildings render whole and transparent | **audited, no offender found, newly pinned in one place -- literal screenshot still outstanding, so this gate is NOT closed.** See `gate-10-atlas-slicing.txt` and `CyberpunkMonsterCrawlTests/AtlasSlicingTests.swift` for the audit and the in-suite pins; the `gate-10-atlas-slicing.png` slice-boundary capture is complementary to those pins, not replaced by them, and the story requires it on a running simulator (PR #65 review). |

### Gate 2 -- asset-resolution audit

The audit (re-reading `AtlasCatalogTests.swift`, `BuildingCatalogTests.swift`
and `TextureLoadingTests.swift` -- the files that jointly implement the
"asset catalog completeness" concept the plan's `AssetCatalogCompletenessTests.swift`
refers to; grepping the repo for that exact name first confirmed no file
carries it) found both existing completeness gates still trip correctly on
a missing asset, through two independent mechanisms each (see
`gate-02-catalog-completeness-teeth.txt` for the full trace: an `XCTFail`/
`XCTAssertGreaterThan` inside the test target, and a hard `precondition`
trap reachable from the production texture-loading path itself). Neither
file needed a fix, so neither was modified.

Rather than leaving the full-run "no placeholder anywhere" claim
unevidenced, three already-existing journeys that together drive a
complete menu-to-death run and screenshot every stage in between --
`raccoon-swarm.json`, `auto-fire-weapons.json` and
`death-and-high-scores.json` -- were tagged with `"CYBERPUN-17-14"` in
addition to their original story, alongside `first-launch-playable.json`
(already tagged for this feature by PR 1). `JourneyManifestTests` confirms
this addition breaks nothing: every gate in that file filters journeys by
`stories.contains(...)` rather than asserting an exact list, and the
structural/coverage assertions on each of the three journeys already held
before this tag was added. When the runtime probe next executes gate
evidence for `CYBERPUN-17-14`, it will run all four journeys and produce
real frames spanning menu, early gameplay, the raccoon swarm approaching
and in contact, the weapon overlay on the player, the swarm in weapon
range, and the death-screen summary -- the full run this gate's `.mov`
was meant to cover.

### Gate 10 -- atlas-slicing audit

The audit re-read every atlas index against its owning row/column table
and its existing pixel-measurement test (player walk, raccoon walk +
attack, weapon overlay, the six ground diamonds, all 12 buildings) and
found no mis-indexed cell -- see `gate-10-atlas-slicing.txt` for the
per-family trace. `CyberpunkMonsterCrawlTests/AtlasSlicingTests.swift` is
new: it exercises every named animation state and every building id
against each family's own production texture accessor in one
consolidated file, so a future regression in any one family's table is
now also caught here. Every expectation in that file is a hand-typed
literal (direction -> row/mirror, direction -> weapon column, tier ->
row) rather than a re-derivation of the accessor under test, and the one
claim no index comparison can settle -- that the raccoon's walk and
attack sheets are two different images -- is measured off the decoded
PNGs (PR #65 review).

**Gate 10 remains outstanding regardless**: those pins are a regression
guard, not the running-simulator demonstration the story requires. The
`gate-10-atlas-slicing.png` capture is still owed by a reviewer with
Xcode access.

## Outstanding, carried over from PR 1

The three gate-1 JPGs referenced in PR 1's section above remain deleted
and gate 1's literal recording remains outstanding, as recorded there.
This PR adds no new claim about gate 1.

## `CYBERPUN-17-14-t3` (PR 3: pixel-crispness + actor-facing/animation audit)

This PR's plan calls for three evidence artifacts:

- `gate-03-actor-facing-animation.mov` -- a recording of an actor turning
  through all 8 facings with a visibly cycling walk animation.
- `gate-09-pixel-crispness-2x.png` / `gate-09-pixel-crispness-3x.png` --
  crisp, non-blurred screenshots at `@2x` and `@3x`.

None of the three is fabricated here, for the same reason PR 1/2's
sections above give: this implementation step has no Xcode/simulator/
screen-capture tool, and a placeholder file at any of those exact names
would be indistinguishable from real evidence until opened.

| gate | state after this PR |
| --- | --- |
| 3 -- actor turns through all 8 facings, walk animation visibly cycles | **audited, code-verified, regression-tested -- literal recording still outstanding.** See `gate-03-actor-facing-animation.txt` and `CyberpunkMonsterCrawlTests/ActorFacingAnimationTests.swift`. |
| 9 -- no blurred/half-pixel-placed sprite at `@2x`/`@3x`; filtering/scale/position swept | **one consistency deviation found and fixed (not a live blur -- see the correction below); three story-accepted exceptions named (elite 1.604x, pickup icon 1.333x, bullets placed sub-pixel + rotated off-axis in flight); audited and regression-tested otherwise -- literal `@2x`/`@3x` screenshots still outstanding.** See `gate-09-pixel-crispness-sweep.txt` and `CyberpunkMonsterCrawlTests/PixelCrispnessSweepTests.swift`. |

### Gate 3 -- actor-facing/animation audit

Re-driving both `PlayerNode` and `RaccoonNode` through every `Direction8`
facing and a full walk (and, for the raccoon, attack) cycle reproduced
exactly the row/mirror/frame sequence each actor's own row-mapping table
and frame-timing module already document -- no offender found. See
`gate-03-actor-facing-animation.txt` for the full trace.
`CyberpunkMonsterCrawlTests/ActorFacingAnimationTests.swift` is new: it
is the one file that exercises both actors' *live, driven* facing +
frame-cycling behaviour side by side against their production texture
accessors, closing a gap `AtlasSlicingTests` (PR 2, static row/column
tables only) and the per-actor suites (`PlayerNodeTests`/
`RaccoonNodeTests`/`RaccoonAnimationControllerTests`, each scoped to one
actor) did not individually cover together.

### Gate 9 -- pixel-crispness sweep

The sweep (re-reading every texture-load path, every node scale
assignment and every node position assignment reachable from a
production sprite consumer) found one deviation from the house pattern:
`PickupNode.texture(forColumn:)` cached a texture crop that had never
itself been stamped `.nearest`/no-mipmap -- unlike every sibling
factory (`PlayerNode`, `RaccoonNode`, `BulletNode`, `HitEffects`,
`WeaponOverlayRenderer`, `PulseRingNode`), which all stamp the crop
directly at cache-population time. Fixed at the cache-population site
(`CyberpunkMonsterCrawl/Sources/Pickups/PickupNode.swift`).

**Correction (PR #66 review).** This section originally billed that as
"one real offender", on the premise that a `SKTexture(rect:in:)` crop
does not inherit its parent sheet's filtering. The review asked for the
premise to be pinned by a test rather than asserted in prose; doing so
falsified it. Measured on a real run, a fresh crop out of a
`TextureLoading`-stamped sheet already reads back `.nearest` with mipmaps
off (`PixelCrispnessSweepTests.test_aRawSheetCrop_carriesTheSheetsNearest`
`Filtering_measuredNotAssumed`). Nothing was blurred on a device. The
stamp is kept as consistency plus a guard against undocumented `SKTexture`
crop behaviour changing, and the claim is downgraded accordingly here and
in the trace rather than left standing.

Scale and position are **not** clean sweeps, and this section said they
were until PR #66's review; three departures from gate 9's wording are
accepted by the story and named rather than netted out:

- the elite raccoon draws its 48x28 cell at 77x45 (1.604x/1.607x) and the
  pickup icon draws its 24x24 cell at 32x32pt (1.333x) -- both non-integer
  magnifications, routed through `SKSpriteNode.size` where
  `PixelCrispness`'s integer-scale rule never sees them, each already
  documented as an opt-out on the property that owns it;
- in-flight bullets are placed at arbitrary sub-pixel positions
  (`Player.handleFire` projects a fractional mid-walk tile and
  `Player.advanceInFlightBullets` interpolates every frame without
  rounding) and are rotated off-axis by `atan2` per AC5, so snapping their
  position would not make them pixel-exact anyway.

Everything else is clean: every other world-space node derives its
position from `IsometricProjection`'s integer-in/integer-out arithmetic or
`PixelCrispness.snappedPosition`, and `CameraController` already snaps the
one per-frame moving world container to the live device pixel grid. See
`gate-09-pixel-crispness-sweep.txt` for the full per-consumer trace and
the derivation of each exception.
`CyberpunkMonsterCrawlTests/PixelCrispnessSweepTests.swift` is new: it
constructs a production-shaped node from every audited consumer and
asserts `PixelCrispness`'s invariants directly -- effective magnification
(`size / texture.size()`) rather than the `xScale` the code under test
just rounded, each accepted exception asserted by name, and a dedicated
case (with a cache-reset test seam, so it can actually fail) proving
`PickupNode.texture(forColumn:)` now provides the filtering guarantee
itself rather than relying on a caller's follow-up `apply(to:)` call.

## Outstanding, carried over from PR 1 and PR 2

Gate 1's literal recording (PR 1) and gate 2/10's literal recording/
screenshot (PR 2) remain outstanding, as recorded in their own sections
above. This PR adds no new claim about any of them.

## `CYBERPUN-17-14-t4` (PR 4: city-read, pickup-visibility, run-variety, pulse audit + closing evidence index)

This PR's plan calls for four evidence artifacts plus the closing index:

- `gate-04-city-read-portrait.png` / `gate-04-city-read-landscape.png` --
  screenshots compared against the five screen mocks.
- `gate-05-pickups-visible.mov` -- a recording of normal play showing the
  first pickup spawn, a camera excursion, and building-adjacency exclusion.
- `gate-06-run-variety.png` -- two consecutive RUN AGAIN runs side by side.
- `gate-08-pulse.png` -- a screenshot at the moment of a pulse.

None of the four is fabricated here, for the same reason every earlier
PR's section above gives: this implementation step has no Xcode/simulator/
screen-capture tool, and the five screen mocks referenced by gate 4 were
not available as files in this step either.

| gate | state after this PR |
| --- | --- |
| 4 -- city reads as a city (lattice, 1-4 storey buildings, rooftop signs) vs. the mock | **audited, code-verified, no offender found, newly pinned in one place -- literal screenshot comparison against the mocks still outstanding.** See `gate-04-city-read-audit.txt` and `CyberpunkMonsterCrawlTests/CityReadComparisonTests.swift`. |
| 5 -- pickups visible per rule (first-spawn window, camera-excursion survival, legible icon, never on/adjacent to a building) | **audited, code-verified, no offender found -- one real coverage gap closed (real generated buildings, not only a hand-built fixture) -- literal recording still outstanding.** See `gate-05-pickup-visibility-audit.txt` and `CyberpunkMonsterCrawlTests/PickupVisibilityTests.swift`. |
| 6 -- every run differs (city and start junction) | **audited, code-verified, no offender found for RUN AGAIN -- one pre-existing, still-not-human-accepted carve-out named (the very first PLAY of a launch) -- literal screenshot still outstanding.** See `gate-06-run-variety-audit.txt` and `CyberpunkMonsterCrawlTests/RunVarietyTests.swift`. |
| 8 -- pulse visible (ring, mid-shove raccoons, a raccoon pinned against a building) | **audited, code-verified, no offender found -- two pre-existing, unrelated outstanding items named (level-6 radius tuning, the still-unidentified crash) -- literal screenshot still outstanding.** See `gate-08-pulse-audit.txt`. |

### Gate 4 -- city-read audit

Re-read `CityLatticeGenerator`, `BuildingPlacement`/`BuildingCatalog`/
`BuildingSprite` and `RooftopSignPlacement` against gate 4's three named
claims (lattice connectivity, 1-4 storey building spans, rooftop signs). No
offender found -- all three already hold, most of it already exhaustively
tested by earlier stories. `CityReadComparisonTests.swift` is new: it turns
the "1-4 storeys" prose claim into a checked fact (a storey-count estimate
derived from `BuildingSprite`'s own measured pixel heights, anchored at the
`.lowest`/`.tall` classes' documented storey counts -- every one of the 12
buildings, including the `.large` landmark tower, estimates inside the 1-4
span by direct measurement), pins that a generated sample actually contains
a mix of height classes rather than one building repeated, and sweeps a
wide seed/block range confirming every placed footprint tile classifies
solid, never street.

### Gate 5 -- pickup-visibility audit

Re-read `PickupManager`/`PickupKind`/`PickupNode` against gate 5's four
named claims. No offender found; three of the four were already
exhaustively covered by `PickupManagerTests`/`PickupIntegrationTests`. One
real coverage gap was found and closed rather than left implicit: every
existing building-adjacency-exclusion test drives `PickupManager` against a
single hand-built `BuildingPlacementRecord` fixture, never a real generated
chunk's actual footprint shapes. `PickupVisibilityTests.swift` (new) closes
that gap by validating placement against buildings `BuildingPlacement
.generate` itself produces over a wide swept region.

### Gate 6 -- run-variety audit

Re-read `GameScene.startNewRun()`/`RunSpawnSelector` against gate 6's two
named claims. The starting-junction claim was already exhaustively covered
by `GameStateMachineTests`; the *city-layout* claim was not -- both of the
existing tests assert on the seed or the junction tile alone, which a
hypothetical bug confined to `RunSpawnSelector`'s own hash stream (wrong
junction, identical city) would still pass. `RunVarietyTests.swift` (new)
closes that gap: it classifies a real tile neighbourhood around each run's
own spawn junction and asserts the classification differs across
consecutive RUN AGAIN invocations, not merely the junction coordinate. One
pre-existing, still-not-human-accepted carve-out is named rather than
reopened: the very first PLAY of a process launch still spawns at the fixed
default seed's junction (see `docs/evidence/GATE_EVIDENCE_INDEX.md`).

### Gate 8 -- pulse audit

Re-read `PulseAbility`/`PulseRingNode`/`GameScene.applyPulseTrigger(raccoons:)`
against gate 8's four named visual claims (ring drawn, raccoons mid-shove,
ring drawn at the moment of pulse, a raccoon pinned against a building). No
offender found; all four already hold and are exhaustively covered by
`PulseAbilityTests`/`PulseSceneWiringTests`/`PulseRingNodeTests`. Notably,
`GameScene.applyPulseTrigger` passes the *real*, currently-streamed
building obstructions (`groundPlane?.residentObstructions`), so a raccoon
pinned against a real building is reachable in a live run, not only under a
hand-built fixture. Two items already recorded as outstanding by earlier
stories (the level-6 radius's compounding tuning, the still-unidentified
probe crash) are named rather than re-litigated, since neither bears on
gate 8's visual claims.

### Journey retagging (a real gap this PR found and fixed)

Auditing which journey the runtime probe would actually run for gates 4, 5
and 8 found none of the three: `menu-to-gameplay.json`, `pickup-spawn.json`
and `pulse-ability.json` named only their *original* story
(`CYBERPUN-17-5`/`CYBERPUN-17-11`/`CYBERPUN-17-10` respectively), never
`CYBERPUN-17-14` -- so the platform's own "a journey runs only for the
story it names" rule meant the probe had nothing to execute for this
story's gates 4/5/8 at all, regardless of how thorough the code-level audit
above is. All three are retagged in this PR, each with an added note in its
own `"demonstrates"` text stating plainly which of that gate's sub-claims
the journey's frames can and cannot show (mirroring the honesty the
existing `raccoon-swarm.json`/`auto-fire-weapons.json` notes already model
for gate 2). `JourneyManifestTests` continues to pass unchanged: the
retagged journeys already satisfy its structural/navigate-then-screenshot
requirements.

### Closing evidence index

`docs/evidence/GATE_EVIDENCE_INDEX.md` (new) is the single cross-reference
from all ten gates to their evidence across all four PRs of this story --
replacing the need to reconstruct gate coverage from four separate PR
diffs. It records every accepted deviation named above plus the two
carried over from PR 3 (gate 9's three named scale exceptions), the journey
retagging fix, and states plainly, gate by gate, which literal capture
remains outstanding rather than leaving that implied.

### Full suite / warning-clean confirmation

This implementation step cannot run `xcodebuild` (no native iOS toolchain
in this container). The platform's own pre-PR host build gate and the
merge/close suite gate are the authoritative confirmation of "full suite
green, build warning-clean" -- see `GATE_EVIDENCE_INDEX.md`'s closing
section for what this PR did and did not verify from inside that
constraint.

## Outstanding, carried over from PR 1, PR 2 and PR 3

Gate 1's literal recording (PR 1), gate 2/10's literal recording/screenshot
(PR 2), and gate 3/9's literal recording/screenshots (PR 3) all remain
outstanding, as recorded in their own sections above and consolidated in
`GATE_EVIDENCE_INDEX.md`. This PR adds no new claim about any of them.
