# journey-auto-fire-weapons evidence -- SECOND FRAME NOT YET CAPTURED

This bundle is incomplete on purpose. It holds one frame, not the two the
journey produces.

`01-swarm-in-weapon-range.jpg` as previously committed here was byte-for-byte
identical to `00-weapon-overlay-on-player.jpg` (both carried git blob SHA
`55aaeb78dcad6cf478e5342666439a27babb0acf`; git blobs are content-addressed, so
identical SHA means identical bytes), as caught in review on PR #45. It was one
capture committed twice, not a second capture. It has been removed rather than
left in place, following the same call made on `CYBERPUN-17-11-t4` after PR #39:
an unusable bundle that looks like a complete one is worse than an absent one,
because it invites a reviewer to record the gate as evidenced when it is only
asserted.

Two pixel-identical frames 20s apart in a live scene with a walking swarm and a
bobbing-pickup world is not plausible, so the cause is a capture/copy slip in
the bundling step rather than a real second capture.

## Why the surviving frame was kept

`00-weapon-overlay-on-player.jpg` is a genuine gameplay capture, and the claim
it is reviewed for -- the weapon overlay composited on the player, which
`WeaponOverlayRenderer` mounts at construction with no visibility gate, so it is
present from the very first gameplay frame -- is reviewable from those bytes
whichever of the two capture points produced them. Which one that was cannot be
determined from the bundle, since the duplicate destroyed the distinction.

What is *not* evidenced is frame 01's claim: the swarm having crossed the
~1,056-point off-screen gap and settled on `RaccoonSeekBehavior`'s
`contactStandoffPoints` ring (~17 points, well inside
`WeaponTier.handgun.rangeTiles` = 5 tiles = 480 screen points). That is
auto-fire's target precondition and the single most load-bearing piece of
runtime evidence for this story, because a probe-driven run can never show a
bullet, muzzle flash or hit puff: AC1 gates fire on movement and the probe's
iOS step vocabulary has no press-drag-release verb, so the thumbstick never
leaves its dead zone. See the journey's `demonstrates` before reading a
bullet-free frame as a missing feature.

## What must be captured before the gate can be reviewed

Re-run the `auto-fire-weapons` journey
(`.mothership/journeys/auto-fire-weapons.json`) with the runtime probe and
commit the two *distinct* frames it produces:

| file | step | reviewed for |
| --- | --- | --- |
| `00-weapon-overlay-on-player.jpg` | `screenshot` label `weapon-overlay-on-player`, ~PLAY+30s | the player carrying a drawn gun -- a small, high-contrast detail composited on a 36x40pt body at 1x, so zoom into the player rather than scanning the whole frame |
| `01-swarm-in-weapon-range.jpg` | `screenshot` label `swarm-in-weapon-range`, ~PLAY+50s | raccoons closed onto the standoff ring around the player, i.e. inside `WeaponTier.handgun.rangeTiles` -- auto-fire's target precondition |

Verify the two files differ from one another before committing them.

Owner: the CYBERPUN-17-9-t4 probe run. This README is removed by whoever
commits the real second frame.
