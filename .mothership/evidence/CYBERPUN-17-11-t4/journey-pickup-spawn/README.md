# journey-pickup-spawn evidence -- NOT YET CAPTURED

This directory is intentionally empty of frames.

The bundle previously committed here (`00-menu.jpg`, `01-pickup-spawned.jpg`,
`02-pickup-lifecycle.jpg`) was three byte-for-byte copies of a single image
(identical blob SHA `16bbc2ad...`), as caught in review on PR #39. The gate for
CYBERPUN-17-11 is *human/vision review of the two gameplay screenshots*, so
three copies of one frame cannot evidence it -- and if the duplicated frame was
the menu capture, no committed frame showed a pickup at all. Those files have
been removed rather than left in place, because an unusable bundle that looks
like a complete one is worse than an absent one: it invites a reviewer to
record the gate as evidenced when it is only asserted.

## What must be captured before the gate can be reviewed

Re-run the `pickup-spawn` journey (`.mothership/journeys/pickup-spawn.json`)
with the runtime probe and commit the three *distinct* frames it produces:

| file | step | reviewed for |
| --- | --- | --- |
| `00-menu.jpg` | `screenshot` label `menu` | title screen, PLAY located |
| `01-pickup-spawned.jpg` | `screenshot` label `pickup-spawned`, ~PLAY+12s | a bobbing med-kit / garbage-can icon over an accent-tinted pad on a street tile, depth-sorted against nearby buildings |
| `02-pickup-lifecycle.jpg` | `screenshot` label `pickup-lifecycle`, ~PLAY+18s | the same pickup still present and still bobbing ~6s later (or a cleared pad if it was collected in between). NOT recurrence/replacement -- no second spawn is possible before ~PLAY+33s |

Verify the three files differ from one another before committing them.

Owner: the CYBERPUN-17-11-t4 probe run. This README is removed by whoever
commits the real frames.
