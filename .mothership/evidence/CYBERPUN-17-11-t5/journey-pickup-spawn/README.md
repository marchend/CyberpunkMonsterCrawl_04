# journey-pickup-spawn evidence -- NOT YET CAPTURED

This directory is intentionally empty of frames.

The bundle previously committed here (`00-menu.jpg`, `01-pickup-spawned.jpg`,
`02-pickup-lifecycle.jpg`) was three byte-for-byte copies of a single image
(identical blob SHA `4ba621bd...`), as caught in review on PR #60. This is the
second time this has happened on this story -- the `-t4` bundle was three
copies of one frame too (blob `16bbc2ad...`, caught on PR #39, see
`../../CYBERPUN-17-11-t4/journey-pickup-spawn/README.md`).

The product gate for CYBERPUN-17-11 is *human/vision review of the two
gameplay screenshots* -- "pickups are visible in normal play: first spawn
<=10s, lifetime >=15s, icons legible at a glance". Three copies of one image
cannot show the menu, a spawned pickup and that pickup's lifecycle
simultaneously, so the bundle could not evidence the gate no matter which
frame it was a copy of.

Those files have been removed rather than left in place, because an unusable
bundle that looks like a complete one is worse than an absent one: it invites
a reviewer to record the gate as evidenced when it is only asserted.

## Why the run produced no usable frames

The probe run behind this bundle reported the app process **gone** at step 6
(~12s past PLAY) and again at step 9 (~18s past PLAY) -- both landing shortly
after `PickupKind`'s frozen 8s first-spawn delay fires, i.e. right around when
the first `Pickup` is created and the first `PickupNode` is mounted. The
journey did not complete, so there were no distinct gameplay frames to commit.
Stating that plainly here is the honest record; attaching placeholder frames
was not.

The `CrashDiagnostics` harness this PR carried was meant to close that gap by
persisting a symbolicated backtrace to `last-crash.log`, but it shipped inert:
nothing ever called `install()`, so no signal disposition was replaced and no
report could ever be written (raised on PR #60 review). It has been **removed**
from the tree rather than wired up, because `CYBERPUN-17-11` is at its final
task and the close-out gate does not let this story's own temporary
investigation code survive it -- the same close-out `CYBERPUN-17-10-t6`
performed on the identical harness. The production file, its test suite and the
`AppDelegate` call site are all gone.

So the crash is **still unidentified**, and the next probe run will again
report "process gone" with no frame named. Closing it needs a symbolicated
crash log / device output from a real run, plus a root-cause ticket that has
never been filed -- filing it is a human call and no ID is invented here.
Whoever picks this up must file that ticket *first*, so the instrumentation it
needs has an owner outside this story and does not land as un-owned scaffolding
again.

## What must be captured before the gate can be reviewed

Re-run the `pickup-spawn` journey (`.mothership/journeys/pickup-spawn.json`)
with the runtime probe and commit the three *distinct* frames it produces:

| file | step | reviewed for |
| --- | --- | --- |
| `00-menu.jpg` | `screenshot` label `menu` | title screen, PLAY located |
| `01-pickup-spawned.jpg` | `screenshot` label `pickup-spawned`, ~PLAY+12s | a bobbing med-kit / garbage-can icon over an accent-tinted pad on a street tile, depth-sorted against nearby buildings |
| `02-pickup-lifecycle.jpg` | `screenshot` label `pickup-lifecycle`, ~PLAY+18s | the same pickup still present and still bobbing ~6s later (or a cleared pad if it was collected in between). NOT recurrence/replacement -- no second spawn is possible before ~PLAY+33s |

Verify the three files differ from one another before committing them. If the
run again ends with the process gone, say so plainly here and record what the
run actually produced -- a named crashing frame is real evidence, an honest
"not captured" is a usable record, and duplicated frames are neither.

Owner: the CYBERPUN-17-11-t5 probe run. This README is removed by whoever
commits the real frames.
