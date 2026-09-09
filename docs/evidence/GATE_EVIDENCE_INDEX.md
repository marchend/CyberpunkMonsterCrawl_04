# Gate evidence index -- `CYBERPUN-17-14`

The design brief's ten product gates are ship criteria, demonstrated on a
running simulator with a screenshot or recording attached to the closing
PR -- green unit tests alone do not satisfy them (`CYBERPUN-17-14`'s own
"Why" section). This file is the single cross-reference from each of the
ten gates to its evidence, across all four PRs of this story. It replaces
having to reconstruct "which gates are covered" from four separate PR
diffs or `docs/evidence/README.md`'s own per-PR narrative (kept, not
duplicated here -- see that file for the full audit trace and review
history behind each entry below).

**Every entry below distinguishes two different things, and conflating
them is exactly the failure this story exists to prevent:** an in-suite
regression test / code-level audit (which this implementation step, run in
a container with no Xcode/simulator/screen-capture tool, can produce) is
**not** the running-simulator screenshot/recording the story's acceptance
criteria require. Where the literal named evidence file does not exist,
that is stated plainly rather than left implied by a similarly-named `.txt`
sitting next to where it should be.

## Index

| Gate | Claim | Code-level evidence | Literal capture | State |
| --- | --- | --- | --- | --- |
| 1 | First-launch playable: menu -> PLAY -> stick moves the player -> every button responds | `.mothership/journeys/first-launch-playable.json` (tagged), `JourneyManifestTests`, `ThumbstickMovementSeamTests` | `gate-01-first-launch-playable.mov` -- **not captured** (PR 1; three fabricated JPGs found duplicated and deleted, see `docs/evidence/README.md`'s PR 1 section) | Mechanism only |
| 2 | Every asset resolves -- no placeholder textures anywhere in a full run | `gate-02-catalog-completeness-teeth.txt`, `AtlasCatalogTests`, `BuildingCatalogTests`, `TextureLoadingTests`; four journeys tagged `CYBERPUN-17-14` for full menu-to-death coverage | `gate-02-no-placeholder-textures.mov` -- **not captured** | Audited, no offender |
| 3 | Actors face and animate their movement -- all 8 facings, walk frames cycling | `gate-03-actor-facing-animation.txt`, `ActorFacingAnimationTests` | `gate-03-actor-facing-animation.mov` -- **not captured** | Audited, no offender |
| 4 | The city reads as a city -- lattice, whole buildings spanning 1-4 storeys, rooftop signs, compared to the mock | `gate-04-city-read-audit.txt`, `CityReadComparisonTests` (new, PR 4), `CityLatticeGeneratorTests`, `ConnectivityTests`, `BuildingCatalogTests`, `RooftopSignPlacementTests`; `.mothership/journeys/menu-to-gameplay.json` **retagged this PR** (previously named only `CYBERPUN-17-5` -- the runtime probe had nothing to run for this gate at all) | `gate-04-city-read-portrait.png`, `gate-04-city-read-landscape.png` -- **not captured**; the five screen mocks were not available as files in this implementation step either, so no pixel-level side-by-side comparison against them was possible here | Audited, no offender; no accepted deviation needed (see gate-04 trace) |
| 5 | Pickups visible in normal play -- first spawn within the window, surviving a camera excursion, icons legible, never on/adjacent to a building | `gate-05-pickup-visibility-audit.txt`, `PickupVisibilityTests` (new, PR 4), `PickupManagerTests`, `PickupIntegrationTests`; `.mothership/journeys/pickup-spawn.json` **retagged this PR** (previously named only `CYBERPUN-17-11`) | `gate-05-pickups-visible.mov` -- **not captured** | Audited, no offender |
| 6 | Every run differs -- two consecutive RUN AGAIN runs with different cities and start junctions | `gate-06-run-variety-audit.txt`, `RunVarietyTests` (new, PR 4), `GameStateMachineTests`; `.mothership/journeys/death-and-high-scores.json` (already tagged `CYBERPUN-17-14` for gate 2) now takes a **city frame in each of its two consecutive runs** -- `gate-06-run-variety-run-1-city` right after PLAY and `gate-06-run-variety-run-2-city` right after the RUN AGAIN tap, added on PR #67 review | `gate-06-run-variety.png` -- **not captured**; the two journey frames above are what the runtime probe now produces for this gate, and the outstanding literal capture is a human/probe review of that pair side by side | Audited, no offender for RUN AGAIN; **accepted carve-out, still not human-accepted** (see below) |
| 7 | No scaffolding ships -- grep for `// SCAFFOLDING:` returns nothing | `gate-07-scaffolding-grep-output.txt` (a real, reproducible zero-match grep log), `ScaffoldingRemovalTests` (the same scan, made permanent) | N/A -- a grep log *is* the literal evidence this gate asks for | **Met** |
| 8 | The pulse works and is visible -- ring drawn, raccoons mid-shove, a raccoon pinned against a building | `gate-08-pulse-audit.txt`, `PulseAbilityTests`, `PulseSceneWiringTests`, `PulseRingNodeTests`; `.mothership/journeys/pulse-ability.json` **retagged this PR** (previously named only `CYBERPUN-17-10` -- the runtime probe had nothing to run for this gate at all) | `gate-08-pulse.png` -- **not captured**; even once run, that journey's own text records it cannot reliably catch the ring/mid-shove/pin frames (no raccoon guaranteed in range, ring's play window shorter than screenshot round-trip latency) -- a genuine capture needs a raccoon in range near a building at press time, which no journey in the tree currently stages | Audited, no offender; two pre-existing outstanding items unrelated to the visual claim (see below) |
| 9 | Pixel art crisp on `@2x` and `@3x` | `gate-09-pixel-crispness-sweep.txt`, `PixelCrispnessSweepTests` | `gate-09-pixel-crispness-2x.png`, `gate-09-pixel-crispness-3x.png` -- **not captured** | Audited; one real defect found and fixed (PR 3, `PickupNode` texture filtering); three named accepted exceptions (see below) |
| 10 | Atlas sheets slice correctly, buildings render whole and transparent | `gate-10-atlas-slicing.txt`, `AtlasSlicingTests` | `gate-10-atlas-slicing.png` -- **not captured** | Audited, no offender |

## Journey retagging fix (this PR)

Before this PR, the runtime probe's own rule -- "the gate only runs a
journey for the story it names" (`.mothership/journeys/*.json`'s own
convention, enforced by `JourneyManifestTests`) -- meant gates 4, 5 and 8
had **no journey tagged `CYBERPUN-17-14` at all**: `menu-to-gameplay.json`
named only `CYBERPUN-17-5`, `pickup-spawn.json` only `CYBERPUN-17-11`, and
`pulse-ability.json` only `CYBERPUN-17-10`. Even with every code-level audit
above finding no offender, the platform's own runtime-probe pipeline would
have had nothing to execute for this story's gates 4/5/8 when processing
this closing PR -- silently falling back to a launch-only capture, the
exact gap `JourneyManifestTests`' own header names as the `CYBERPUN-17-9`
precedent ("nothing on screen... while every unit test was green"). All
three journeys are retagged with `CYBERPUN-17-14` in this PR (mirroring the
retagging PR 2 already did for `raccoon-swarm.json`/`auto-fire-weapons.json`
for gate 2), and each journey's own `"demonstrates"` text now states
explicitly which of gate 4/5/8's sub-claims that journey's frames can and
cannot show -- see each `.json` file's own added note. `JourneyManifestTests
.test_aJourneyExistsForCYBERPUN1714sFirstLaunchGate_andCapturesAfterNavigating`
already covers every journey tagged `CYBERPUN-17-14` (all three retagged
journeys navigate then screenshot afterward, so this gate continues to
pass), and `test_everyJourney_carriesTheFieldsTheProbeAndTheReviewerBothNeed`
covers the retagged files' structural shape unconditionally.

**Gate 6 had the same defect and is fixed the same way (PR #67 review).**
It was the one gate in the table above deferred with a reason that pointed
at this PR itself ("authoring a new journey was not in this PR's file
list") -- a deferral with no owner, on the story's closing PR. It needed no
new journey: `death-and-high-scores.json` already carries the
`CYBERPUN-17-14` tag (for gate 2) and is the only journey in the tree that
taps RUN AGAIN and drives a second full run, but every frame it captured
was a death screen or the high-scores table, so the probe still produced
nothing gate 6 could be reviewed from. It now takes one gameplay city frame
in each of its two consecutive runs -- `gate-06-run-variety-run-1-city`
immediately after PLAY and `gate-06-run-variety-run-2-city` immediately
after the RUN AGAIN tap, both at the same moment of their own run (the
first gameplay frame, camera on that run's own spawn junction) so the
comparison is like-for-like. That journey's own `"demonstrates"` text now
states what the pair is reviewed for (a visibly different city and starting
junction; two identical frames *are* the gate-6 failure) and what it cannot
show (the seed value, hence not "every future run differs" -- that half
stays with `RunVarietyTests`/`GameStateMachineTests`). Both new steps sit
before the journey's existing floor waits, so
`test_theDeathJourneysWaitForElementSteps_areBackstoppedByADerivedFloorWait`
still sees the same contiguous `wait` runs immediately preceding each
`wait_for_element`.

## Why no `.mov`/`.png`/`.jpg` is fabricated here

Every PR of this story runs in a container with no Xcode, no simulator and
no screen-capture tool. A binary file committed at one of the exact names
above without genuine captured bytes would be worse than not committing it
at all -- indistinguishable, on disk, from real evidence until someone
opens it. `docs/evidence/README.md`'s PR 1 section records the concrete
cost of getting this wrong: three JPGs sharing one git blob SHA, i.e. one
capture committed three times under three gate-numbered names, which had
to be found and deleted on review. Every gate above whose literal capture
is "not captured" is real, named, outstanding work for a human or the
platform's runtime-probe pipeline -- not a gap papered over by a
placeholder.

## Accepted deviations and outstanding items, by gate

- **Gate 6** -- the very first PLAY of a process launch still reaches
  `.gameplay` through the seed-neutral `stateMachine.transition(to:)`, not
  `startNewRun()`, so a player who launches, plays one run, dies and
  force-quits gets the identical city and starting junction on every fresh
  launch. This is a pre-existing, explicitly recorded product question
  (the `CYBERPUN-17-13` entry in AGENT.md/CLAUDE.md), raised on PR #51 and
  **still not accepted or rejected by a human** as of this PR. Gate 6's
  literal wording ("every run differs... two consecutive RUN AGAIN runs")
  is about RUN AGAIN specifically, which this PR's audit confirms holds
  (including the city-layout claim, not just the junction); the
  first-launch carve-out is named here rather than silently left for a
  future reader to rediscover, and this PR neither resolves nor reopens it.

- **Gate 8** -- two items recorded by earlier stories, unrelated to the
  four visual claims gate 8 asks about and unchanged by this PR's audit:
  the level-6 pulse radius bonus ships *compounding* (1.5625x, not additive
  1.5x) pending a human tuning call, and a crash the runtime probe twice
  reported near this ability remains genuinely unidentified (recorded in
  the `CYBERPUN-17-10` entry in AGENT.md/CLAUDE.md; filing that root-cause
  ticket is a precondition for closing that story, not this one).

- **Gate 9** -- three named accepted exceptions to the whole-integer-scale
  rule, all pre-existing and unchanged by this PR: the elite raccoon's
  48x28 cell drawn at 77x45 (1.604x/1.607x), the pickup icon's 24x24 cell
  drawn at 32x32pt (1.333x), and in-flight bullets placed at arbitrary
  sub-pixel positions and rotated off-axis by `atan2` (both routed through
  `SKSpriteNode.size`/free rotation rather than `PixelCrispness`'s
  whole-integer-scale/whole-point-position rule). See
  `gate-09-pixel-crispness-sweep.txt` for the full derivation of each.

- **Gates 1-5, 8, 10** -- no accepted deviation beyond the literal-capture
  gap above; every code-level claim this implementation step could check
  held with no offender found.

## Scaffolding

A grep for `// SCAFFOLDING:` across the whole repository returns zero
matches as of this PR (`gate-07-scaffolding-grep-output.txt`,
`ScaffoldingRemovalTests`). No new scaffolding was introduced by PR 4.

## Full test suite / warning-clean confirmation

This implementation step runs in a container with no native iOS toolchain
(no Xcode, no `xcodebuild`, no simulator) -- `code_run_tests` reports a
skip here, which is **not** a pass and is not treated as one. The genuine
gate for this repository is the platform's pre-PR host build (a real
macOS build host that runs `xcodegen generate` + `xcodebuild` against this
tree before the PR opens) and the merge/close suite gate that re-runs the
whole suite on every merge and close. Those gates -- not this file -- are
the authoritative "full suite green, build warning-clean" confirmation;
this file cannot honestly claim that confirmation from inside a container
that never compiled the tree. What this PR did verify from inside that
constraint: every new/changed Swift file was re-read for the project's own
known compile hazards (unbraced Unicode escapes, `Set` over a
non-`Hashable` type, exhaustive `switch`es, correct SDK/API call shapes)
before being committed, and every new test file follows the existing
suite's own patterns (fixture construction, `WorldSeed`/`BlockCoordinate`/
`TileCoordinate` usage) rather than inventing new call shapes.
