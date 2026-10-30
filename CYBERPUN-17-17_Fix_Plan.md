# CYBERPUN-17-17 Fix Plan

## Title
AccessibleSKViewTests break whenever the test suite grows — make the AX hit-test fixtures hermetic

## Symptom
Six `AccessibleSKViewTests` tests fail on unrelated branches whenever new, unrelated test
content is added elsewhere in the suite (e.g. CYBERPUN-17-9's combat-only branch,
CYBERPUN-17-11's pickups-engine branch), while the identical base tree verifies green.
The tests assert accessibility elements by **object identity**, which is deliberate and must
not be weakened.

## Root cause (best evidence available from code review)
`AccessibleSKView.swift`, `SceneAccessibilityContainerView`, and `GameScene`'s accessibility
walk (`accessibleUINodes()`, `accessibilityFrameInScene(for:)`) were reviewed in full and
contain **no static/global mutable state**: no singletons, no class-level caches keyed on
anything AX-related, no `UserDefaults` usage on these paths. `AccessibleSKViewTests` already
builds a **fresh** `GameScene` / `AccessibleSKView` / `SceneAccessibilityContainerView` per
test method (`makeMenuScene()`, `makePresentedView()`), and `tearDown()` releases the
retaining ivars (`hostView`, `containerView`).

Given `project.yml` sets `parallelizable: false`, the whole test target runs **serially in one
process**. The most plausible remaining mechanism, consistent with every observed symptom, is
**process-level residue from SpriteKit's per-view update/render scheduling**:

- `tearDown()` nils `hostView`/`containerView` but never explicitly pauses or detaches the
  view that was presented during the test. Whether that view's `CADisplayLink`/update-loop
  participation actually stops *synchronously* at that point, or only once ARC's `deinit`
  chain happens to run, is left unspecified.
- The file's own extensive comments document a previously-hit race in exactly this area
  (`presentScene(_:)` clearing a pause set, requiring a pause-before-*and*-after fix that
  "failed across all 22 tests in this file" once under CI load) — i.e. this class of race is
  known to exist and to be load-sensitive.
- As more unrelated test classes elsewhere in the suite construct and discard their own
  `SKView`/`SKScene` instances, the number of overlapping in-flight SpriteKit view lifecycles
  handled within the single shared test process grows, which plausibly widens the same
  "mid-tick" race window rather than eliminating it — explaining why the **same six tests**,
  and no others, fail specifically when the suite grows, without needing any shared identity
  object to literally leak between test instances.

This is a **hermeticity/timing gap in the test fixture's teardown**, not a logic bug in the
production AX code. No production file exhibited state that would need a new reset seam, so
none is planned (adding one speculatively would be unjustified, since no shared/static state
was found).

## Planned changes
Bounded to a single file: `CyberpunkMonsterCrawlTests/AccessibleSKViewTests.swift`.

1. **Harden `tearDown()`.** Before releasing `hostView`/`containerView`, explicitly pause the
   presented `AccessibleSKView` (`isPaused = true`) and remove it (and its container sibling)
   from the host view's hierarchy. This forces SpriteKit's update scheduling for that instance
   to stop synchronously at the end of every test, rather than relying on ARC deallocation
   timing — removing that test's contribution to accumulated background render/update load for
   every test that runs after it, regardless of what other unrelated test classes do in
   between.

2. **Add the composition regression test the ticket's acceptance criteria call for.** A new
   test method that, in one deterministic test body:
   - constructs and discards a bare, unrelated `SKView` + `SKScene` (mirroring the shape of
     what broke CYBERPUN-17-9 / CYBERPUN-17-11 — an unrelated test class constructing scene
     content with zero AX-related files involved), then
   - immediately builds a fresh menu scene/view via the existing helpers and performs one of
     the current AX identity assertions (equivalent to
     `test_accessibilityHitTest_atThePublishedPlayFrameCentre_returnsThatElement`'s core
     assertion: hit-testing the published PLAY frame's centre returns that very element by
     `===` identity).

   This pins, independent of actual suite ordering/composition, that constructing-and-discarding
   an unrelated `SKView`/scene cannot corrupt the AX hit-test family's identity results —
   satisfying the acceptance criterion directly instead of relying on incidental suite
   composition to exercise it.

No changes are planned to `AccessibleSKView.swift`, `SceneAccessibilityContainerView`, or any
other production file. The identity assertions in the existing six tests are left untouched
and unweakened, per the ticket's explicit instruction.

## Tests
- New regression test (composition-pinning) added as described above.
- Full `AccessibleSKViewTests` file re-verified to confirm all existing six tests plus the new
  test pass together.
- No other test suites are expected to be affected, since the change is confined to one test
  file's fixture teardown and one new test.

## Acceptance criteria mapping
- "Full suite green with the AX family passing regardless of suite composition" →
  addressed by the hardened, synchronous `tearDown()` (removes cross-test residue from
  SpriteKit's update scheduling).
- "The suite stays green on a tree that adds a new unrelated test class which constructs an
  SKView/scene" → directly pinned by the new composition regression test, which reproduces
  that exact shape deterministically inside `AccessibleSKViewTests` itself.

## Explicitly out of scope
- No changes to production accessibility code (`AccessibleSKView.swift`,
  `SceneAccessibilityContainerView`) — no shared/static state was found there that needed a
  reset seam.
- No weakening of the object-identity assertions (`===`) in the existing six tests.
- No changes to `PLAN.md` (this document is a standalone ticket-scoped plan).
