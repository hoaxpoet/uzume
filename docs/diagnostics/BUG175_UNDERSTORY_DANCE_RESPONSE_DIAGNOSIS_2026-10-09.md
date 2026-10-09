# BUG-175 — Understory “Dance Yrself Clean” response diagnosis

**Date:** 2026-10-09

**Severity:** P1

**Domain:** `preset.fidelity` / `dsp.stem`

**Failure class:** `pipeline-wiring`

**Status:** Diagnosed; no fix code in this increment

## Expected behavior

Understory should make the arrangement’s energy legible by opening into a
recognizable fern as sustained full-band energy rises. The quiet state may retain
a fiddlehead curl, but the rachis, alternating pinnae and recursive pinnules must
remain identifiable. Bass/treble balance should bend the frond, dense continuous
sound should sustain local pinna motion, and beats should send a bounded light
along the branching path.

For “Dance Yrself Clean”, the full-band section must be more open and at least as
visibly active as the preceding sparse section. It must not close or become less
animated merely because a deviation follower has adapted to the louder passage.

## Actual behavior

Matt’s live review: the fern remains mostly curled; after the full band enters it
moves less than during the bass-led opening; its closed-biased silhouette reads as
an irradiated, struggling plant rather than a fern. The preset is not viable in
this state.

An exact offline replay of the shipped `UnderstoryState` equations against the
captured feature/stem rows confirms the inversion:

| Window | Mean curl (1 = coiled) | Mean ruffle | Mean abs. bend | Spectral surge | Waveform occupancy |
|---|---:|---:|---:|---:|---:|
| 120–180 s, before full band | 0.600 | 0.262 | 0.04386 | 0.387 | 0.027 |
| 210–270 s, full band | 0.763 | 0.126 | 0.01570 | 0.827 | 0.076 |

The energetic section therefore becomes **27% more coiled**, loses **52%** of
its ruffle state and loses **64%** of its bend magnitude, while the two recorded
full-mix density/arrival primitives rise strongly.

Fifteen-second bins show the same direction rather than a boundary artifact. From
210–300 s, curl generally occupies 0.67–0.88 while mean ruffle stays 0.10–0.14
and mean absolute bend stays about 0.015–0.017. The session’s first 180 seconds
regularly reach curl 0.27–0.75, ruffle 0.25–0.31 and bend 0.039–0.056.

## Reproduction

1. Build the preserved Understory worktree and pin Understory.
2. Run `/Users/Shared/memrepro/01 Dance Yrself Clean.mp3` through
   `Scripts/memrepro.sh` so the P0 memory watchdog remains active.
3. Compare the sparse 120–180 s window with the full-band 210–270 s window.
4. Observe that the later window is more tightly curled and has less geometric
   motion despite the audible increase in arrangement energy.

**Minimum reproducer:** replay the matching rows from the retained session through
`UnderstoryState`; no new live capture is required for diagnosis.

## Session artifacts

- Session: `/Users/braesidebandit/Documents/uzume_sessions/2026-10-09T14-36-34Z`
- Track SHA-256:
  `0e1dc8f765bf204b3e47cb5d60a335d8e20c0df15f371ddf8ed8b609d82312b7`
- Chain health: `clean`; peak −5.7 dBFS; 48 kHz; no full-scale run.
- `features.csv`: 17,820 data rows through 297.4 s.
- `stems.csv`: 17,820 aligned data rows.
- The state replay uses the production constants and update order from
  `UnderstoryState.step`, at the captured 60 Hz row cadence.

## Root cause

The routing contract structurally suppresses the fern during sustained energetic
music:

1. Curl is controlled only by `vocalsEnergyRel`. Instrumental or low-relative-
   vocal passages target `curl = 0.92`, regardless of full-band energy. In the
   compared windows, mean `vocalsEnergyRel` falls 0.005→−0.019, so the energetic
   section explicitly commands closure.
2. Pinna ruffle reads `drumsEnergyDev`. Deviation is high when the drum level
   changes and falls as the tracker adapts to a sustained section. Its mean drops
   0.232→0.085 across the same windows.
3. Bend reads `bassDev − trebDev`, another deviation pair. Mean absolute bend
   consequently falls after the arrangement settles even though the music remains
   energetic.
4. The reset/default curl of 0.85 and no-vocal target of 0.92 devote most runtime
   to a pose that hides the approved fern anatomy.

This is `pipeline-wiring`, not insufficient gain: multiplying the existing routes
would strengthen the same wrong relationship. The recorded alternatives already
carry the missing musical fact. `spectralSurge` means “the mix arrived and holds”
and rises 0.387→0.827; `waveformOccupancy` measures how much of the spectrum is
active and rises 0.027→0.076. The fix increment must replay and calibrate those
semantics before changing the live preset.

## Verification criteria written before the fix

- [ ] A recorded-session state replay covers all 17,820 aligned rows and reports
      per-15-second curl, local-motion and bend summaries.
- [ ] On “Dance Yrself Clean”, mean curl in 210–270 s is at least 0.25 lower than
      in 120–180 s and is no greater than 0.30.
- [ ] The sustained local-motion output in 210–270 s is not lower than in
      120–180 s; short accents may exceed it but may not define its baseline.
- [ ] Silence/reset remains non-black and partially curled, but a production-path
      still at the resting value passes the reference traits: traceable rachis,
      at least six pinnae and legible recursive pinnules.
- [ ] Route-isolation tests prove one primitive/timescale per visual layer and the
      sidecar manifest exactly matches the state reads.
- [ ] A production-path replay of the real session has zero >3× motion spikes and
      yields sampled frames before and after the full-band entrance for reference
      comparison.
- [ ] Manual check at normal speed and volume: the full-band entrance visibly
      opens and energizes the fern; it reads immediately as a fern throughout;
      the plant never appears to struggle or collapse as the arrangement grows.

**Manual validation required:** Yes. Automated replay can prove direction, range
and continuity, but only Matt can approve the musical feel and fern read.

## Fix scope

Replace the vocal-only posture mapping and deviation-only sustained-motion mapping;
do not merely increase their gains. Preserve the accepted forward-kinematic uncurl,
source-registered open endpoint, recursive detail, bounded beat-path light and
BUG-176 resource constraints. Validate by recorded replay before requesting another
live run.
