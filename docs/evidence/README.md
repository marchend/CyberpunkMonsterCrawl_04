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
