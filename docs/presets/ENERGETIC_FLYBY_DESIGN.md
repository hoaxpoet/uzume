# Energetic Flyby — Design (working name)

**Status:** EFB.0 design record, 2026-10-19 (design seat). `certified: false` until EFB.3.
**Working name.** "Energetic Flyby" is Kali's title for the source. Matt names the scene before certification;
until then the slug is `energetic_flyby` and the increment prefix is `EFB`.
**Source:** Kali, *[Inércia 2022] Energetic Flyby*, Shadertoy `csjGDD`, live-coded at Inércia Shader Royale
2022 (4th place). Single image pass, ~3.2 KB, no textures, no buffers.
**Spike:** `docs/presets/energetic_flyby_spike/` (verbatim transcription, the music build, the drivers, the
blind A/B record).

---

## 0. How this concept was chosen (the preset-concept gate)

Matt's direction, 2026-10-19, verbatim and in order:

- *"I want more kaleidoscope / impossible geometry / mesmerizing presets."*
- *"The fractal fern preset is the closest to what I'm looking for."* Then: natural form is not required ("we
  already have too many natural forms"), the camera must move, and *"you are being much too literal."*
- *"I need strong connection between the music and visuals that can be easily perceived."* Stems are not
  required *"due to the poor performance of stem separation."*
- *"What I need first and foremost is astonishing visuals."*
- After a scout of ~325 recent Shadertoy pieces and the Revision 2023–2026 top entries: *"only energetic flyby
  has high-definition graphics and vibrant colors."*

| Gate artifact | Where |
|---|---|
| 1. A watched moving source | Shadertoy `csjGDD`, watched live in Matt's Chrome (2026-10-19) |
| 2. The look verified in motion | Spike `README.md` §2: the verbatim transcription renders identically; four reference frames (`docs/VISUAL_REFERENCES/energetic_flyby/01–04`) are taken from it |
| 3. The three-sentence story | §2 below |
| 4. A running look-spike, motion-gated, shown | Spike §3: three rounds of 20 s music renders shown to Matt; round 3 passed his blind A/B |

Three-part concept bar (`PRESET_SESSION_CHECKLIST.md` Part 2):
1. **Iconic subject at fidelity:** the subject *is* the source, ported verbatim (Aurora Veil precedent, D-185).
2. **Clear musical role:** §2.
3. **Infrastructure-feasible:** a `direct` single-pass fragment with a CPU state buffer at slot 6, the Nimbus
   pattern (`bindNimbusRuntime`). No new render capability. Cost is the open risk (§7).

## 1. The scene

A camera flies continuously down a twisting tunnel of glassy, perforated shells lit from inside by neon
streaks, following a cluster of spiked, slowly spinning spheres that throw light rods through the tunnel. The
shell walls carry Kali's animated fractal texture; the ambient tunnel light comes from the same march's glow
accumulation. Nothing in the look is Uzume's: every surface, colour and light is Kali's.

## 2. The story (gate artifact 3) and the musical role

- **See:** a flight through glassy, perforated shells lit from inside, led by a cluster of spiked spheres.
- **Move:** one continuous flight with no cuts, banking a quarter turn every two bars, rushing in busy passages
  and drifting in quiet ones.
- **Music:** each downbeat bursts the light from the sphere cluster and turns its colour; the bass spins the
  spheres; the song's energy sets the flight speed.

**Musical-role sentence.** *The downbeat is the event: on each "one" the sphere cluster's light bursts and its
colour turns, so the bar line is something you watch arrive; between downbeats the flight's speed follows the
song's energy and the bass spins the spheres.*

## 3. Temporal contract (visual layer × audio primitive × timescale) — FA #67 check

| Visual layer | Primitive (CPU, `EnergeticFlybyState`) | Timescale | Notes |
|---|---|---|---|
| Sphere-cluster light: burst intensity **and** colour turn (one layer, one event) | downbeat = `barPhase01` wrap on the cached grid; a 0.35× echo when `barPhase01·beatsPerBar` crosses 2 (beat 3 in 4/4) | bar | Replaces Kali's `so = fract(sin(time)*123.456)`, a pseudo-random per-frame flicker. Burst decay 0.35 s, echo decay 0.20 s; colour turn +0.7 rad eased over 0.25 s |
| Camera bank (quarter turn, alternating direction) | every second downbeat | 2 bars | Shares the downbeat primitive with the burst at a **different timescale**; this is the only shared primitive and it is deliberate |
| Flight speed + glow floor | energy = `spectralFlux`, self-normalised against its own running mean (Fiddlehead's `squash` pattern), 0.6 s smoothing | phrase / section | FA #31: never an absolute threshold on an AGC-normalised value |
| Sphere spin rate | `bassDev` (positive part), fast attack 30 ms / release 300 ms, self-normalised | beat-to-bar | |

**Not used, deliberately:**
- **Every-beat pulses.** Round 1–2 of the spike pulsed glow and speed on every beat; on Love Rehab Matt could not
  tell the in-sync clip from the half-beat-shifted one and preferred the shifted one. On four-on-the-floor
  music an every-beat pulse slid half a beat lands on the off-beat hi-hats and still looks rhythmic. The
  downbeat is the discriminating event.
- **Stems.** Matt, 2026-10-19: not required "due to the poor performance of stem separation." The Inari stop
  record (stem bleed) agrees.
- **Raw live onsets** (Audio Data Hierarchy layer 4).

## 4. Camera (Matt's call, 2026-10-19)

*"I don't like the hard cuts in each clip — it's not a smooth, continuous display of the camera motion, the
camera / fly-through resets a few times over 20 seconds."* Kali's original parks the camera every 5 s
(`if (mod(time,10.)>5.) from = path(floor(t/4.+.5)*4.)`), which reads as a jump cut and a reset. **The scene has
no holds and no cuts.** The camera rides `path(travel)` continuously; `travel` is integrated on the CPU from the
energy-driven speed, so it never jumps. The bar-line move is the quarter-turn bank (§3), eased over 1 s.

## 5. Photosensitivity (D-157, D-164) — what changes from the spike

The spike's burst brightened the glow term everywhere (`glo *= (base + so·1.5)`), so it moved the **whole-frame**
luminance: round 3 max Δ frame-mean luma 0.168 per frame, 7 frames > 0.1 in 20 s on There There. The scene must:

- **Bound the burst's footprint:** the burst brightens the light that comes *from the sphere cluster* (the `br`
  rod/sphere glow term, `g += .1/(.1+br*13.)`), not the tunnel light (`li`) or the whole glow sum. The tunnel
  stays at its energy-driven floor.
- **Keep global luminance steady on the beat:** gate the measured result, not the intent: 0.00 flashes/s on
  the flash harness's worst-case train, regional ≤ 3/s, red 0.00 (BR.20 v2), and report max Δ frame-mean luma.
- **Fix the one-frame white-out** found in spike round 2 (frame 487, `05_anti_whole_frame_whiteout.jpg`). When a
  spinning rod sweeps through the camera, `g` saturates for every ray in that frame. The spike's fix: evaluate
  the rods at the camera position at the top of `march` (`br` at `from`), and scale the glow by
  `mix(0.3, 1, smoothstep(0, 0.2, brCam))`. It took that frame from 0.706 to ≈ 0.40 frame-mean against neighbours
  0.27–0.34, with a small global dimming. EFB.1 may keep it or find a better one, but must measure it.

## 6. Silence, cold start, no grid

- **Silence (D-037):** the flight continues at the speed floor; the tunnel light (`li`) and the fractal texture
  keep the frame non-black. No bursts (no downbeats at silence on the local path; on streaming, the stopped grid).
- **No grid / beat-irregular tracks:** no downbeat events, so no bursts and no banks; speed, glow floor and spin
  still follow the music. The scene stays watchable; it is not excluded (`requires_regular_beat` is **not** set).
  Whether it should be is an M7 call.
- **Cold start (CAPABILITY_REGISTRY/BEAT_SYNC §Cold-Start Phase Contract):** the grid's phase may be wrong at
  track start, so early bursts may land off the "one". No cold-start suppression is designed in; M7 decides
  whether one is needed.
- **Per-track reset:** energy and bass normalisers, burst envelopes and the bank angle reset in
  `resetPerTrackPresetState`. Travel and hue are **not** reset (a track change must not snap the camera or the
  palette).

## 7. Cost (open risk)

The march is 200 steps; every `de` evaluates three `coso` sphere systems. Shadertoy ran it smoothly in Matt's
Chrome on his Mac, but Uzume's budget is 60 fps at 1080p with headroom. D-254 allows a Tier-2-first flagship at
6–12 ms. EFB.1 measures Release GPU time at 1080p and 4K on the dev Mac, and uses `setDirectRenderScale` (Nimbus
renders at 0.5×) only if needed; Kali's look has fine edges, so the render scale is a fidelity trade-off that
goes to Matt with frames. `complexity_cost` is set from the measurement.

## 8. Licence (D-252)

Kali's source carries no licence header, so Shadertoy's default terms apply: **CC BY-NC-SA 3.0**. The port is
the second NC-SA scene after Aurora Veil, inside D-252's cap of about three. Obligations:

- `EnergeticFlyby.metal` carries Kali's credit, the Shadertoy URL and the CC BY-NC-SA 3.0 notice, in the Aurora
  Veil header pattern;
- a `docs/CREDITS.md` entry in the nimitz/Aurora Veil format;
- **clean-room replacement (D-252 requires one named):** a flythrough authored from the published fold-tunnel
  technique (abs-fold domain repetition along a sine path, spheres with radial spikes, glow accumulation in the
  march), written without reference to Kali's code. Built only if Kali objects to the port.
- **Uzume stays free (Matt, 2026-10-19: free forever),** so the non-commercial condition is met for the life of
  the product. Matt is asking Kali for his blessing anyway (2026-10-19).

## 9. Increment plan

| ID | What | Gate |
|---|---|---|
| EFB.0 | This doc, the reference folder, the spike folder, the EFB.1 prompt (design seat) | Committed before EFB.1 starts |
| EFB.1 | Faithful port + `EnergeticFlybyState` music drivers + photosensitivity fix + wiring (uncertified) + harness + Release timing | Stop for Matt's live look (local beta playlist + one streaming pass) |
| EFB.2 | M7 rounds (two maximum, the PHYS escalation rule) | Matt's M7 |
| EFB.3 | Certification: `audio_routes` green, flash-safe measured, frame budget, soak, NEW_PRESET_CHECKLIST §4 | Matt's sign-off |

## 10. Decisions taken in the design seat (defaults; Matt may override)

- **The downbeat under the brightness rule.** Default **A**: the light bursts from the sphere cluster only and
  the tunnel stays steady; the colour turn carries the rest. (B, colour-only with no brightness change, is the
  fallback if A fails the flash gate.)
- **Family:** `fractal`. The scene is a ray-marched fold-domain flythrough, not a feedback warp, so it does not
  belong in `hypnotic` (already 8 scenes). The fractal family has one certified scene, Fractal Tree.
- **Rubric profile:** `full`.
