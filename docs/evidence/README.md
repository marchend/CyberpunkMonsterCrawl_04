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
implementing this PR: a full-tree search for the scaffolding marker
(`SCAFFOLDING`) confined to the bundled app target (`CyberpunkMonsterCrawl/`),
returning zero matches. The same scan, made permanent and re-run on every
suite run rather than a one-time log, is
`CyberpunkMonsterCrawlTests/ScaffoldingRemovalTests.swift`
(`test_bundledAppSource_containsNoScaffoldingMarker`), which also carries
an anti-vacuity guard proving the scanner actually finds the marker when
one is present. The `.txt` extension here (rather than `.png`) is
deliberate: this is a real, verifiable text log rather than a fabricated
image standing in for a screenshot that was never taken.

## Outstanding

A human reviewer (or the platform's own simulator/runtime-probe pipeline)
still needs to execute `first-launch-playable.json` against a real build
and attach the resulting recording/screenshots as `gate-01-first-launch-playable.mov`
under this directory before gate 1 is fully evidenced in the form the
plan originally asked for. This is named here explicitly rather than left
unmentioned so it is never mistaken for having already happened.
