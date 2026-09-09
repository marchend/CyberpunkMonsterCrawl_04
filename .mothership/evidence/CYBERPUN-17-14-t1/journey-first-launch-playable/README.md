# journey-first-launch-playable evidence -- NO FRAMES CAPTURED YET

This bundle is deliberately empty of frames. It holds this note and nothing
else, because the three JPGs previously committed here were not three
captures.

`00-gate1-menu.jpg`, `01-gate1-gameplay-running.jpg` and
`02-gate1-button-responded.jpg` all carried the same git blob SHA
(`a5e0d08b6e736d2c3bb508dc4098ecde3fc9b34a`). Git blobs are content-addressed,
so an identical SHA means byte-identical content: one image committed three
times under three gate-numbered names claiming three different states (title
screen, running `.gameplay`, post-tap). Caught in review on PR #64.

Both readings of that are blocking for gate 1, and neither is evidence of a
pass:

- if the frames were not produced by a real probe run, they are fabricated
  evidence under gate-numbered filenames -- the exact thing this PR's own
  `docs/evidence/README.md` argues against one section earlier when it
  explains why no `.mov`/`.png` placeholder was committed; or
- if a probe run did produce them, it captured the same frame at all three
  steps, which means the app never visibly advanced from the menu through
  PLAY. That is gate 1 *failing*, and the frames would be the proof of
  failure, not of success.

They have been deleted rather than left in place, following the call already
recorded for `CYBERPUN-17-9-t4` after PR #45 (and `CYBERPUN-17-11-t4` after
PR #39): an unusable bundle that looks like a complete one is worse than an
absent one, because it invites a reviewer to record the gate as evidenced
when it is only asserted. Nothing was kept, because unlike PR #45's case
there is no way to tell which of the three states -- if any -- the single
surviving image actually showed.

## What must be captured before gate 1 can be reviewed

Re-run `.mothership/journeys/first-launch-playable.json` with the runtime
probe against a real build and commit the three *distinct* frames it
produces:

| file | step | reviewed for |
| --- | --- | --- |
| `00-gate1-menu.jpg` | `screenshot` label `gate1-menu`, ~launch+4s | the title screen reachable on first launch, with a PLAY button and no scaffolding overlay, smoke-test label or placeholder title anywhere on it |
| `01-gate1-gameplay-running.jpg` | `screenshot` label `gate1-gameplay-running`, ~PLAY+3s | a real running `.gameplay` scene -- ground lattice, buildings, player actor, floating thumbstick, HUD -- not a menu and not a placeholder |
| `02-gate1-button-responded.jpg` | `screenshot` label `gate1-button-responded`, after the tap on the HUD's bottom-right ability button | the same gameplay screen still foregrounded and rendering after the press, i.e. the button was accepted without a crash or hang |

**Verify the three files differ from one another byte-for-byte before
committing them** (`git hash-object` on each, or `shasum`): the filenames
cannot be trusted to tell you what a frame shows, and this is the second time
in this repo a duplicate-blob bundle reached review.

The other half of gate 1 -- "the stick moves the player" -- is not capturable
by the probe at all (its step vocabulary has no drag/hold verb, so the
thumbstick never leaves its dead zone) and stays machine-verified by
`ThumbstickMovementSeamTests`; see the journey's own `demonstrates` field.

Owner: the CYBERPUN-17-14-t1 probe run. This README is removed by whoever
commits the three real frames.
