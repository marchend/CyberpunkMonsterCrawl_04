# journey-pickup-spawn evidence -- NOT YET CAPTURED

This directory is intentionally empty of frames.

The bundle previously committed here (`00-menu.jpg`, `01-pickup-spawned.jpg`,
`02-pickup-lifecycle.jpg`) was three byte-for-byte copies of a single image
(identical blob SHA `3a0300b8...`), as caught in review on PR #61. This is the
third time this has happened on this story: the `-t4` bundle was three copies
of one frame (blob `16bbc2ad...`, caught on PR #39) and the `-t5` bundle was
three copies of another (blob `4ba621bd...`, caught on PR #60) -- see
`../../CYBERPUN-17-11-t4/journey-pickup-spawn/README.md` and
`../../CYBERPUN-17-11-t5/journey-pickup-spawn/README.md`.

To answer the review question directly: **those three files were not genuine
captures.** They are an artifact of how the bundle was assembled, not three
moments of a run -- three identical images cannot simultaneously show a menu, a
freshly spawned pickup and that same pickup ~6s later. The probe runs behind
this task reported the app process **gone**, so there were no distinct
spawned/lifecycle frames in existence to attach.

The product gate for CYBERPUN-17-11 is *human/vision review of the two gameplay
screenshots* -- "pickups are visible in normal play: first spawn <=10s,
lifetime >=15s, icons legible at a glance". Copies of one image cannot evidence
that gate no matter which frame they are copies of, and a bundle that *looks*
populated is worse than an absent one: it invites a reviewer to record the gate
as evidenced when it is only asserted. That is the same failure
`JourneyManifestTests` exists to prevent one level up ("an empty rooftop reads
as feature missing"), so the files have been removed rather than left in place.

## Why the run produced no usable frames

The probe run behind this bundle reported the app process **gone** at ~12s past
PLAY and again at ~18s past PLAY -- both landing shortly after `PickupKind`'s
frozen 8s first-spawn delay fires, i.e. right around when the first `Pickup` is
created and the first `PickupNode` is mounted. The journey did not complete, so
there were no distinct gameplay frames to commit.

Two independent static audits (`-t5`, `-t6`) of `PickupManager`/`PickupNode`/
`PickupKind`/`AtlasSheet.pickups`/`DepthBanding`/`GameScene`'s pickup wiring/
`RaccoonSeekBehavior`'s diversion path found no reachable crash site, so the
crash is **still unidentified** and `-t6` does not claim to fix it. What `-t6`
landed instead is a bisection in the probe's own vocabulary: the post-PLAY
waits in `.mothership/journeys/pickup-spawn.json` are split so `assert_running`
brackets the 8s delay (`wait 4` -> `assert_running` -> `wait 4` ->
`assert_running` -> `wait 4`), which narrows what the *next* "process gone"
report can say. It does not name a frame. No in-app crash-capture harness was
re-added; that path was already tried and closed out as un-owned scaffolding on
`CYBERPUN-17-10`.

## What must be captured before the gate can be reviewed

Re-run the `pickup-spawn` journey (`.mothership/journeys/pickup-spawn.json`)
with the runtime probe and commit the three *distinct* frames it produces:

| file | step | reviewed for |
| --- | --- | --- |
| `00-menu.jpg` | `screenshot` label `menu` | title screen, PLAY located |
| `01-pickup-spawned.jpg` | `screenshot` label `pickup-spawned`, ~PLAY+12s | a bobbing med-kit / garbage-can icon over an accent-tinted pad on a street tile, depth-sorted against nearby buildings |
| `02-pickup-lifecycle.jpg` | `screenshot` label `pickup-lifecycle`, ~PLAY+18s | the same pickup still present and still bobbing ~6s later (or a cleared pad if it was collected in between). NOT recurrence/replacement -- no second spawn is possible before ~PLAY+33s |

Verify the three files differ from one another before committing them. If the
run again ends with the process gone, say so plainly here and record which
`assert_running` checkpoint was the last to pass -- that is what the new
bisection buys. A named crashing checkpoint is real evidence, an honest "not
captured" is a usable record, and duplicated frames are neither.

Owner: the CYBERPUN-17-11-t6 probe run. This README is removed by whoever
commits the real frames.
