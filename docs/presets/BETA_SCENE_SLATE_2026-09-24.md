# The beta slate: 25 → 50 scenes

**Date:** 2026-09-24 · **Seat:** design (Claude.ai) · **Status:** v2 — §00 carries Matt's decisions and the Oct 15 plan; §§0–7 are the v1 analysis they rest on. This plan says which
moving sources to take through `preset-concept`, and in what order. **No slate entry has cleared the gate
yet.** Each one names its proven moving source and a draft three-sentence story (gate artifact 3). Artifacts
2 and 4 (the source watched in motion, then a motion-gated look spike) are the first step of every entry,
and nothing in this document replaces them.

---

## 00. Matt's answers (2026-09-24, 14:22) and the October 15 plan — READ THIS FIRST

**Decisions recorded.** These still need D-numbers from a doc session.

| # | Decision | Matt, verbatim |
|---|---|---|
| 1 | **D-119 is retired as a rule.** Originals are preferred over Milkdrop-inspired scenes, as many as possible. | *"D-119 shouldn't be a rule. We want more original presets than ports of Milkdrop. I want as many original presets as possible."* |
| 2 | NC-SA ports are allowed, each file marked, capped at about 3, with a clean-room replacement listed for each. The Aurora Veil header gets its license notice. | *"Agree with your recommendation: B."* No commercial distribution is planned. |
| 3 | **Remove Plasma. Keep Waveform** (it stays uncertified as the launch default and does not count toward the target). | *"Remove Plasma, keep Waveform. I will likely remove Waveform later."* |
| 4 | Tier-2-first flagships are allowed. | *"Yes"* |
| 5 | **This programme supersedes Phase PR** (the 2026-09-04 remediation). | *"This work trumps the 2026-09-04 work."* |
| 6 | 50 is a goal, not a floor. The quality bar governs. | *"50 is a target … not a strict floor"*; *"I just don't want things to look cheap and amateurish."* |

**Beta: October 15 (21 calendar days from today).** The slate below was costed at 9–14 weeks for 25
scenes. **50 certified by October 15 is not achievable at the quality bar.** The honest target:

- **New-scene cutoff: Sun Oct 11** (last M7). Oct 12–14 is the whole-roster soak on the test playlist, plus
  plan and orchestrator checks, with no new scenes.
- **Attempt 11 originals in 3 parallel lanes. Expect 8–10 to certify**, which puts the beta roster at
  **about 33–35 certified**. 50 remains the post-beta goal, and the rest of the slate continues after
  October 15 at the same cadence.
- **Milkdrop Lane E is out of the beta window.** Per decision 1, it is emergency backfill only, and only if
  Matt asks for it.

**Selection rule for the window.** Every entry needs a source with *readable code or analytic maths* (a
fast port, not a from-footage build), low engine work, and no dependency on the parked downbeat work
(BUG-065 / D-206). That keeps five entries for after the beta:

| Entry | What it needs first |
|---|---|
| Kagura | a motion-capture pipeline |
| Supernova | build detection plus volumetric flash safety |
| Mandelbulb | a clean-room ray-march with a Kleinian Froth history |
| Laser Haze | a source (it has none yet) |
| Goldengrove | a painterly grind, and its source is prose |

| Lane | Order (stop the lane's current entry at a failed gate or a second failed M7, then start the next) | Why this order |
|---|---|---|
| **1 · musical-intelligence** (overlay / `point`) | **Fireflies → Pendulums → Harmonograph** | Fireflies has the highest conviction and a public-domain source. Pendulums is analytic maths. Harmonograph is last because of the Rosette precedent. |
| **2 · physical, direct fragment** | **Drumhead → Rain on Glass → Pool → Rubens' Tube** | The fastest ports (MIT, NC-SA single shader, MIT). Rubens' Tube has no code source, so it goes last. |
| **3 · simulation / compute** | **Sumi → Physarum Species → Galaxy → Photosphere** | Sumi and Physarum have certified engines under or beside them (the Filigree engine, Alfvén's solver). |
| backup | **Lantern** | Starts in whichever lane frees up first. |

**Revision 2026-09-24 14:38 — Matt: *"Kagura and Goldengrove should be developed."*** Both join the
window as their own lanes. To hold Matt's review load at roughly 30 live looks, **Rubens' Tube, Photosphere
and Lantern leave the window** and become the first post-beta entries.

| Lane | Order | Honest read for Oct 11 |
|---|---|---|
| **4 · Kagura** | KAG.0 spike → design doc → build | **Plausible.** Point-lights are cheap to render. The risks are whether the retimed capture reads as dancing, and beat-grid quality. |
| **5 · Goldengrove** | GG.0 spike (growth timing only) → only then look work | **Unlikely to certify by Oct 11.** Matt **shelved** it on 2026-06-01 (`GOLDENGROVE_PLAN.md` banner): *"Do not revive without a fundamentally stronger, signal-grounded musical hook."* The proposed hook is new since then. **On the local-file path the whole track is analysed before playback, so the bloom can be *scheduled* to arrive with the song's measured peak**; streaming falls back to the live `spectral_level_rise` / `spectral_section_ratio` envelope, which did not exist in June. GG.0 tests that hook on cheap geometry before any painterly work. Hero fidelity still needs the mesh G-buffer path, which was deleted at RECON.15. |

**Session prompts for the first wave:** `prompts/BETA.0-prompt.md`, `prompts/KAG.0-prompt.md`,
`prompts/GG.0-prompt.md`, `prompts/FF.0-prompt.md`, `prompts/DH.0-prompt.md`, `prompts/SUMI.0-prompt.md`.
All six can run in parallel worktrees. Every spike ends in a hard stop with frames for Matt. The design doc
(this seat) and then the build increments follow a spike only after it passes.

**Day-0, done in parallel with the first spikes. No new infrastructure is built for the window.**
- **Plasma removal increment.** Scene, sidecar, tests, docs and roster counts.
- **Test playlist: approved by Matt 2026-09-24.** Ten songs from his library, written to
  `tools/data/beta_test_playlist.m3u` with what-each-tests in `docs/presets/BETA_TEST_PLAYLIST.md`
  (BETA.0 task 5). Local-file playback is the M7 path. Do one streaming pass per scene on Matt's Spotify
  mirror of the same ten before it certifies.
- **The rewatch bar (§2) is applied by hand in the window.**
  - R2 and R3 run through `compare_render.sh` and `motion_gate.sh` on two contrasting playlist tracks.
  - Mechanising the R1 decoy lift is post-beta.
  - Per-pass GPU timing is also post-beta, since no heavy flagship is in the window.
- **Fireflies pre-check.** Confirm that a per-track beat-regularity or grid-confidence value can reach the
  GPU. D-154's `assessBeatIrregularity` computes one on the CPU. If it cannot reach the GPU, that is a
  one-float infrastructure increment, and it lands before the scene (infrastructure never ships bundled
  with a scene).

**Matt's review time is the real constraint.** 11 attempts × (1 look spike + up to 2 M7s) is about 30 live
looks in 17 days. Batch them into one daily sitting of about 3 scenes on the test playlist.

---

## 0. The recommendation in five lines

1. **Win on musical intelligence and finish, not on count.** Phosphor launched on the Mac App Store in April
   2026 with 149 scenes at $4.99. It uses the same stack (Apple Silicon, Metal, Core Audio process tap).
   Uzume cannot win on volume. It can win on scenes where a viewer can *see* the stems, the harmony and the
   song's structure, which no live competitor exposes.
2. **Fill the empty registers, not the crowded ones.** Three orchestrator families have no scene
   (supernova, drawing, dancer) and five have one (sparkle, reaction, volumetric, waveform, fractal). Hypnotic
   feedback already has 8 scenes, and it is also the market's most over-served look.
3. **Every new scene must be the first real consumer of something.** That means a signal the roster ignores
   (tension, consonance, meter, phrase, beat-grid confidence, near-silence, stems as independent actors) or a
   render capability with no consumer (light shafts, caustics, orbit camera, the `point` primitive, a
   production `staged` scene).
4. **Spend the GPU.** 20 of the 25 certified scenes declare ≤ 2.5 ms on Tier 2, against a 16 ms budget.
   Six slate entries are deliberate Apple Silicon flagships.
5. **Add a rewatch bar before anything is built** (§2). *"Movie on a loop"* (Filigree) and *"mesmerizing
   but kinda boring"* (Floret) are the two failure notes that most apply to a 50-scene library. The bar
   exists to catch both, and part of it can be measured.

---

## 1. Where the roster stands (measured from the sidecars, 2026-09-24)

**25 certified. Production uncertified: Plasma, Waveform** (Waveform is still the launch default, per PR.9).

| Family | Certified scenes | Count |
|---|---|---|
| hypnotic | Alfvén, Aurora Veil, Dragon Bloom, Fata Morgana, Floret, Glaze, Meniscus, Nacre | **8** |
| particles | Filigree, Mitosis, Cytokinesis, Murmuration, Nebula, Witchlight | **6** |
| geometric | Cymatic Resonance, Ferrofluid Ocean, Lumen Mosaic, Volumetric Lithograph | 4 |
| painterly | Ricercar, Skein | 2 |
| fractal / sparkle / reaction / volumetric / waveform | Fractal Tree / Gossamer / Membrane / Nimbus / Stave | 1 each |
| **supernova / drawing / dancer** | none | **0** |

**Signals nobody reads, or only one scene reads.**
- `tonal_tension` and `tonal_phase_thirds`: 0 scenes.
- `tonal_consonance`: Nacre, as a saturation gate only.
- `beats_per_bar`: Ferrofluid Ocean only.
- `sectionIndex`: Skein and Witchlight.
- Instrument-family activity: Ricercar only.
- `near_silent01`, `pulse_regional_blend01` beyond FFO, and `spectral_surge`: none or almost none.
- Vocal pitch is present only 4.5 % of the time, so it can only ever be garnish.
- **No scene makes the four stems into four separately visible actors.** The competitive research found no
  live product that does this either.

**Render capability with no consumer.**
- Light shafts, caustics, the orbit camera and the overlay `point` primitive have zero consumers.
- `staged` has no production scene since Arachne left (D-246).
- Mesh shaders have one consumer (Fractal Tree).
- Compute has huge headroom: Physarum runs 1 M agents in ≈ 0.55 ms.

**What Matt's review says "fun to watch" is.** From the 2026-09-04 notes:
- Cymatic Resonance: *"One of the best to watch. Wish there were more presets like this one."*
- Fractal Tree: *"it just dances along with the music pretty convincingly."*
- Ferrofluid Ocean: *"Brilliant sync."*
- Nimbus: *"people … think the ball has a personality."*
- Murmuration: *"Beautiful."*

What they share is a nameable subject that visibly *does* something, where the viewer can point at the
musical moment that caused it. Some also have a character.

---

## 2. The rewatch bar (proposed addition to the concept gate)

A scene earns a place in a 50-scene library only if its 10th viewing differs from its 1st. Every entry
below answers five questions. Two of them can be measured.

| # | Question | Failure it catches | How to check |
|---|---|---|---|
| R1 | **Legible:** could a viewer point at the moment the music caused? | "not apparent" sync (Fata Morgana, Ricercar) | **Decoy lift (measurable).** Run the QG.3 coupling metric against the true audio and against a decoy (the same session's audio time-shifted by half a bar, plus a different track). The scene must couple measurably better to the truth. This generalises the quarter-cycle decoy Faraday's round 3 already used. |
| R2 | **Per-track identity:** do two different songs produce visibly different scenes? | "movie on a loop" (Filigree) | **Two-song sheet (measurable).** Render the same scene over two contrasting tracks (e.g. *Low* side 2 vs. a four-on-the-floor track) side by side. If the contact sheets are interchangeable, it fails. |
| R3 | **Arc:** does the scene have a beginning, middle and end across a song? | "kinda boring" (Floret) | Minute 1 vs. minute 4 of the same track, side by side. |
| R4 | **Source of novelty:** what guarantees it does not repeat? | "uniform speed" (Mitosis) | State one: emergent simulation, harmony-generated form, song-structure state machine, or character. |
| R5 | **Restraint:** does it stay calm when the music is calm, with no jitter or flash? | "very jittery" (Plasma) | The existing D-157 / D-164 flash and luminance gates plus the motion gate. |

R1 and R2 cost one increment of harness work (Wave 0) and then run for free on every scene, existing ones
included.

---

## 3. What the market says (condensed; sources at the end)

- **Phosphor** (Little Knife Labs, April 2026): $4.99, Apple Silicon only, the same Core Audio process tap,
  **149 scenes**. Named scenes include Tunnel, Nebula, Supernova, Kaleido, Oscilloscope, Terrain FFT and VFD
  bars. It has a rules-based "director" that switches on bass, onsets and tempo. It has no pre-analysis, no
  stems, no harmony and no session planning. **It is the direct Mac competitor, and it owns the crowded
  registers.**
- **Synesthesia**: $199–$399, about 80–100 scenes, the quality high-water mark. Its audio vocabulary is 5
  bands × level/hits/presence/time, plus BPM. **No stems, no key, no structure.**
- **projectM / MilkDrop / NestDrop**: huge libraries. The loudest complaint is that most presets are broken
  or noise, so the valued artefact is curation. Cream of the Crop keeps about 19 % of about 52 k presets, and
  its 11 folders are Uzume's family taxonomy.
- **Over-served everywhere:** feedback glowsticks, tunnels, kaleidoscopes, spectrum bars and oscilloscopes,
  starfields and particle nebulae, CRT and retro looks.
- **Under-served:** physical materials (ink, smoke, glass, caustics), calm naturalistic second-screen scenes,
  true volumetric light and lasers, and figures or dancers. Stem- and structure-aware visuals exist today
  only in *offline* music-video generators.

**Implication.** Build none of the over-served looks unless it is clearly the best of its kind. Point the
new scenes at the under-served registers, each wired to something only Uzume knows about the music.

---

## 4. The slate: 25 primary entries in five lanes

**Legend.**
- *Source:* the proven moving artefact that gate artifact 1 will point at, with its license as verified on
  2026-09-24.
- *Cost:* declared Tier-2 target.
- **FLAGSHIP:** an Apple Silicon showcase with a Tier-2 target of 6–12 ms, degrading on Tier 1 through the
  governor ladder.

### Lane A — Instruments you can see (the moat)

**A1 · Physarum Species** · particles · compute · FLAGSHIP (millions of agents)
- **See:** four colonies of slime-mould, each a different colour and morphology, spreading across the frame.
- **Move:** the colonies grow, starve, invade and retreat. At section boundaries every colony's growth rules
  morph (interpolated) to a new parameter regime.
- **Music:** each stem *is* a species. **Stem energy sets how much food that species gets**, so the colony
  that is winning territory is the instrument carrying the song.
- *Rewatch:* emergent. Every song leaves a different map.
- *Source:* Sage Jenson, *36 Points* (CC BY-NC-SA; the parameter sets are her creative work, so tune our
  own), on Filigree's certified agent engine.
- *Risk:* too close to Filigree. Kill it if a side-by-side with Filigree reads as the same scene.
- *Note:* stems lag ≈ 2.5 s on streaming, which is fine here because food is an envelope, not a transient.

**A2 · Sumi** (suminagashi, floating-ink marbling) · painterly · `staged` persistent (the first production
`staged` scene since Arachne; fall back to compute if the per-stage iteration cap bites) · FLAGSHIP (2048² dye)
- **See:** ink rings floating on still water, then combed into marbled paper.
- **Move:** drops land and bloom outward, and a slow current stirs them. At section boundaries a comb is
  drawn through the whole surface. At the end of the track the paper lifts and the water is clean.
- **Music:** **each full-mix onset drops a ring of ink whose colour is the stem dominating at that moment**
  (e.g. drums sumi-black, bass indigo, vocals vermilion, other ochre).
- *Rewatch:* emergent, and each track leaves its own print.
- *Source:* PavelDoGreat, WebGL-Fluid-Simulation (**MIT**; its `splat()` injection maps directly to onsets),
  and MarinovM03/suminagashi (**MIT**; subtractive ink and combing).
- *Risk:* the whole surface settles to mush (filter test 1 of the equation-candidates doc). Dissipation plus
  the comb must keep it legible.
- *Note:* on streaming the ink colour lags about a bar (the ≈ 2.5 s stem lag). The drop itself is on time,
  because it comes from the full-mix onset.

**A3 · Kagura** (a point-light dancer; the Uzume myth *is* a dance) · **dancer** (empty family) · particles
plus the `point` primitive
- **See:** about 15 glowing points on black that the eye instantly reads as a person dancing (Johansson
  biological motion), with light-painted trails.
- **Move:** real dance motion capture, time-warped to the song's tempo and changed at phrase boundaries.
- **Music:** **steps land on the cached beat grid** (Fractal Tree's gait precedent). Energy chooses how big
  the dancing is. Vocals lift the arms.
- *Rewatch:* character (the Nimbus effect), and per-track style from tempo and mood.
- *Source:* CMU Graphics Lab Motion Capture Database (shippable inside a product, not resellable, credit
  requested; AIST and Motorica are research-only). BioMotionLab walker as the look reference.
- *Risk:* people spot bad human motion instantly, and it depends on beat-grid quality (BUG-065 is parked).
  The rendering asks almost nothing, because the realism comes from the capture data. `requires_regular_beat`.

**A4 · Lantern** · volumetric · the first light-shaft consumer
- **See:** shafts of light through a slatted window into a dark, hazy room, with dust motes drifting.
- **Move:** slats sway, motes eddy, and the haze slowly thickens.
- **Music:** **the vocal stem is the light.** Beam intensity follows vocal energy: when the singer enters,
  the room lights up.
- *Rewatch:* arc; verses and instrumental passages look different.
- *Source:* three-good-godrays (**zlib**) for the scattering, and footage of real sunbeams through dust for
  motion.
- *Risk:* on instrumental tracks it is dim by design. The planner needs vocal-stem affinity so it only picks
  Lantern for sung material.

**A5 · Harmonograph** · **drawing** (empty family) · mv_warp `marks` overlay (Stave/Skein precedent)
- **See:** a luminous pen tracing a decaying pendulum figure on dark paper.
- **Move:** each figure draws itself over roughly a phrase and fades as the next one starts.
- **Music:** **harmony decides whether the figure closes.** Consonant passages draw closed rosettes on
  simple ratios (2:1, 3:2, 4:3); rising `tonal_tension` pushes the ratio toward complex intervals, so the
  pen wanders and never closes until the music resolves.
- *Rewatch:* harmony-generated form; a chord progression is literally legible as a sequence of figures.
- *Source:* evoluteur/harmonograph (**MIT**; pendulum figures for ten musical intervals) and m1el/woscope
  (**MIT**; the analytic phosphor-beam line).
- *Risk:* **Rosette died in this lane** (D-224, a harmony-driven Whitney figure). What differs is that the
  pen visibly *draws*, so change is shown as an act rather than a morph. Tension also runs near-flat on 2 of
  3 route fixtures. Kill it if the look spike reads as Rosette.
- *Note:* it is the only consumer of tension anywhere in the roster.

### Lane B — Physical phenomena (Cymatic Resonance's lineage, the look Matt asked for more of)

**B1 · Drumhead** · geometric · direct plus post
- **See:** a circular drumhead, or a dish of water under a ring light, holding ring-and-spoke nodal
  patterns. It is a circle, not Cymatic's square.
- **Move:** patterns snap between modes and sand re-settles.
- **Music:** **harmony chooses the pattern.** The circle-of-fifths position sets the number of spokes, so a
  key change visibly re-draws the figure. Brightness sets the number of rings, and a kick makes the sand jump.
- *Rewatch:* harmony-generated form, directly answering *"I want to see more variation of the patterns."*
- *Source:* LuisReinoso/vibracion (**MIT**; live-audio circular Bessel modes) and evoluteur/cymatics
  (**MIT**).
- *Risk:* reads as a re-skin of Cymatic. Faraday retired on the *image* (D-204), so this stays with linear
  modes and a crisp nodal set and does not revive the Faraday PDE.

**B2 · Pendulums** (the pendulum wave) · geometric · direct
- **See:** a row of 15–24 pendulums of graded lengths.
- **Move:** the row falls through travelling waves, splits into twos and threes, dissolves into chaos, then
  snaps back into one line.
- **Music:** **the realignment period is locked to the phrase.** The pendulums line up again exactly on the
  downbeat of the next 8- or 16-bar phrase, so the song's structure becomes the payoff moment.
- *Rewatch:* the resolution lands on real phrase boundaries, which differ from song to song.
- *Source:* the Harvard Natural Sciences Lecture Demonstrations "Pendulum Waves" (the canonical real
  phenomenon; the maths is analytic).
- *Risk:* needs a stable grid; `requires_regular_beat` hard-excludes it on irregular tracks (D-154). Kill it
  if the realignment reads as a timer rather than as the phrase.
- *Note:* it is also the natural home for `beats_per_bar`: pendulum groups sized to the meter.

**B3 · Rubens' Tube** · waveform (replaces the Waveform scene's family slot) · direct plus post
- **See:** a horizontal brass tube in a dark room, with a row of flames along its top.
- **Move:** the flames form a standing wave. Nodes stay low, antinodes leap.
- **Music:** **the flames are the bass line made physical.** The dominant low-frequency bin sets the
  wavelength, so a new bass note visibly re-spaces the peaks, and loudness sets flame height.
- *Rewatch:* legible physics; every bass line draws its own flame pattern.
- *Source:* real-phenomenon footage (e.g. Yuri Suzuki's Rubens-tube pieces). The flame rendering uses Xor's
  published turbulence technique; his code licensing is mixed, so re-implement the technique rather than
  copy his code.
- *Risk:* fire fidelity. Kill it if the flames read as a bar graph.

**B4 · Pool** · geometric · direct or staged
- **See:** looking down into a sunlit swimming pool, with a moving caustic net on the tiles.
- **Move:** swells cross the surface and the net tightens and loosens.
- **Music:** **the bass is the swell.** Sustained low energy drives the wave height, so the light net
  brightens and knots in bass-heavy passages. A kick drops a pebble ripple.
- *Rewatch:* calm and naturalistic, built for the second screen.
- *Source:* Evan Wallace, WebGL Water (**MIT**; swap its tile and cubemap textures, whose licenses are
  unknown).
- *Risk:* water scenes are already crowded (Meniscus, Membrane, FFO, Fata Morgana). It stays in only if the
  sunlit-tile caustics are distinctive at M7; otherwise it goes to the bench.
- *Note:* it is the first caustics consumer.

**B5 · Photosphere** · reaction · compute (reuses Alfvén's projection solver)
- **See:** the surface of a star, a seething carpet of convection granules.
- **Move:** cells well up, split and sink, and never settle (the spiral-defect-chaos regime).
- **Music:** **energy is the heat.** Arousal and energy set the Rayleigh number, so quiet music gives lazy
  rolls and loud music a violent boil.
- *Rewatch:* emergent, never settles (it passes the equation-candidates filter test 1).
- *Source:* VisualPDE "Thermal convection" (**MIT**). Solver reuse from ALFVEN.1.
- *Risk:* texture rather than subject (filter test 3). The frame must read as *a sun*, with limb darkening
  and curvature, not as noise.

### Lane C — Apple Silicon flagships

**C1 · Galaxy** · particles · compute plus the orbit camera (its first consumer) · FLAGSHIP (2–4 M stars)
- **See:** a spiral galaxy with dust lanes and pink star-forming knots, seen at a slowly changing angle.
- **Move:** the arms rotate as a density wave and the camera inclines between sections.
- **Music:** **the bass envelope is the density wave.** Arms gather and brighten in bass-heavy passages.
  Vocals ignite star-forming regions along the arms.
- *Rewatch:* camera and arm structure change per section, and the palette per track.
- *Source:* beltoforion, Galaxy-Renderer (**BSD-2**; density-wave theory).
- *Risk:* the register overlaps Nebula and starfields in general. Kill it if it reads as a screensaver
  (it fails R1).

**C2 · Supernova** · **supernova** (empty family) · ray-march volumetric · FLAGSHIP
- **See:** a star.
- **Move:** through a build it contracts and heats. At the drop it bounces and throws off a volumetric
  shockwave shell, and the remnant keeps expanding for the rest of the song.
- **Music:** **the build is the collapse and the drop is the explosion.** `spectral_level_rise` and
  `spectral_surge` time the contraction, and the section boundary plus the bass surge fire the bounce.
- *Rewatch:* a song-structure state machine, so each track gets its own number and timing of detonations.
- *Source:* Duke's volumetric nebula and remnant shaders (CC BY-NC-SA; use them as look references and
  clean-room the implementation).
- *Risk:* flash safety. The detonation must be expansion, not a white frame (D-157, D-164). It also depends
  on build detection, which runs on pre-AGC fields.

**C3 · Mandelbulb** · fractal · ray-march, static camera · FLAGSHIP
- **See:** the Mandelbulb, lit like sculpture.
- **Move:** it breathes. The fractal power slowly morphs, so lobes grow, fold and bloom.
- **Music:** **sustained bass drives the morph.** Long bass swells unfold the form, and the fifths position
  shifts the orbit-trap palette.
- *Rewatch:* each song's bass contour sculpts a different sequence of forms.
- *Source:* Inigo Quilez, "Mandelbulb - derivative" (Shadertoy ltfSWn) as the look target. **Its license
  header is unread, and some iq shaders carry a restrictive header**, so implement the public distance
  estimator clean-room.
- *Risk:* the Kleinian Froth and Fractal Fly-By history (D-200, D-201). The static camera removes the
  Fly-By failure. Faithfulness to iq's look removes the Froth failure, or the scene dies at the look spike.

**C4 · Laser Haze** · volumetric · ray-march participating media · FLAGSHIP
- **See:** a concert laser show: thin coloured beams fanning through thick haze.
- **Move:** beams sweep, fan, tunnel and freeze, choreographed by the bar.
- **Music:** **the beat grid is the lighting desk.** Cues change on bar and phrase boundaries, drum energy
  sets sweep speed, and bass pumps the haze.
- *Rewatch:* choreography varies with structure. It is built for peak sections and listening parties
  (Product Spec use case 2).
- *Source:* **incomplete.** SebH "VolumetricIntegration" (Shadertoy XlBSRz) for the technique, plus real
  laser-show footage for motion. It needs one proven moving shader before gate artifact 1 is satisfied.
- *Risk:* flash safety (keep beams thin and luminance steady), and the source gap above.

### Lane D — Calm second-screen scenes

**D1 · Fireflies** · sparkle · particles plus the `point` primitive · **highest conviction on the slate**
- **See:** a dusk meadow full of fireflies.
- **Move:** at first they blink at random. Gradually, pulled by one another, they fall into unison. Waves
  of flashes sweep the swarm before it locks.
- **Music:** **the swarm finds the beat.** Coupling strength follows beat-grid confidence, so rhythmically
  clear music entrains them into flashing on the beat and rubato or ambient music leaves them free.
- *Rewatch:* an entrainment arc on every track.
- *Source:* Nicky Case, *Fireflies* (**public domain**; the pulse-coupled "nudge the clock" model), plus
  footage of real synchronous fireflies.
- *Risk:* the flashes must be tiny and the global luminance steady (D-157); each firefly is a point, not a
  frame flash. Kuramoto Chimera died as per-pixel TV snow; discrete points solve that rendering problem.
- *Why it matters:* the cold-start phase problem **becomes the feature**. They *should* be incoherent at the
  top of a track.

**D2 · Rain on Glass** · volumetric/ambient · direct
- **See:** a rain-streaked window at night, the city blurred into bokeh behind it.
- **Move:** drops land, bead, then run and clear trails through the fog.
- **Music:** **percussion is the rain.** Full-mix onsets land drops, so busy music makes a downpour and
  sparse music a drizzle. Harmony tints the city lights.
- *Rewatch:* calm, with a per-track palette. When the music goes near-silent (`near_silent01`, currently
  unread), the glass fogs over and waits.
- *Source:* BigWings, "Heartfelt" (Shadertoy ltffzl, **CC BY-NC-SA**).
- *Risk:* licensing only (see §7). The look is proven.

**D3 · Goldengrove** · fractal · mesh shader (Fractal Tree's engine)
- **See:** the back-lit golden-hour tree (existing concept doc; 14 curated references).
- **Move:** it grows, blooms at the song's peak and sheds leaves at the turns. The season follows mood.
- **Music:** **the song's loudness arc grows the tree.** Level-rise and section-ratio fields drive growth
  toward the peak.
- *Rewatch:* a whole life per song.
- *Source:* **incomplete.** The concept predates the gate and is prose-originated, which is the gate's own
  kill tell. It needs a watched moving source: a time-lapse or an existing growth shader, plus the Fractal
  Tree growth mechanic as proof.
- *Risk:* painterly fidelity (Matt's warnings). Keep it only if the look spike lands.

### Lane E — Milkdrop-inspired uplifts (7 of 7 certified so far, the lowest-risk lane)

These are Matt's unused top-ten picks from `MILKDROP_UPLIFT_PICKS.md`; all exist in the butterchurn built-in
set. **Proposed D-121 divergence axis for every one: the feature stack.** The original reacts to
bass/mid/treble; Uzume's version reacts to stems, harmony or structure. That is the required divergence, and
it is also the product differentiator.

| # | Source preset | Register (from the picks doc) | Family target |
|---|---|---|---|
| E1 | Rovastar + Loadus + Geiss, *FractalDrop (Triple Mix)* | particle or fractal burst | supernova or fractal |
| E2 | Flexi, *alien fish pond* | organic | TBD at gate |
| E3 | Geiss, *Spiral Artifact* | whirl or spiral: the psychedelic-geometry ask, through a proven source | hypnotic |
| E4 | Martin, *liquid arrows* | radial liquid arrows | TBD |
| E5 | _Geiss, *Artifact 01* | | TBD |
| E6 | _Mig_085 | blue spiral swirl | TBD |
| E7 | suksma, *heretical crosscut playpen* | | TBD |
| E8 | **Eye-test slot:** one family-gap built-in Matt picks from a fresh render | | drawing, supernova or dancer |

Candidates to render for E8: *Star Nova v7b*, Zylot *Paint Spill*, Flexi *predator-prey-spirals*,
*pogo cubes vs. tokamak vs. game of life*, TonyMilkdrop *Magellan's Nebula*, Geiss *Cauldron – painterly 2*.
Geiss *Reaction Diffusion 2* is deliberately excluded: it overlaps Mitosis, Membrane and Photosphere.

### Coverage after the slate (if all 25 land)

- **Every family except `transition` would have at least one scene, and most at least two.** Drawing gets Harmonograph, plus an
  E8 pick if Matt chooses one.
- **Hypnotic** grows only through Lane E.
- **Signals gaining a first structural consumer:**
  - tension and consonance as form: Harmonograph
  - fifths as *form* rather than hue: Drumhead, Mandelbulb
  - meter and phrase: Pendulums
  - beat-grid confidence: Fireflies
  - loudness arc and build: Supernova, Goldengrove
  - near-silence: Rain
  - stems as actors: Physarum Species, Sumi
  - vocal-as-light: Lantern
  - spectrum-as-physics: Rubens' Tube
- **Render capabilities gaining a first consumer:** light shafts (Lantern, Laser Haze), caustics (Pool),
  orbit camera (Galaxy), `point` (Fireflies, Kagura), production `staged` (Sumi), and a second mesh scene
  (Goldengrove).

---

## 5. Bench: promote when a primary entry dies

Attrition on originated concepts has been heavy. Ten have been retired since June (Drift Motes, Glass
Brutalist, Kinetic Sculpture, Truchet Loom, Kleinian Froth, Fractal Fly-By, Faraday, Rosette, Root Choir,
Arachne), while faithful ports have certified reliably. **Plan on 5–8 of the 25 dying**, and promote from
here, ports first:

1. Remaining Lane E renders (item E8's list). These are the first backfill, because the port lane has the
   best record.
2. **Pool** moves here if it proves too close to Meniscus.
3. **Star Nest** (Kali; **MIT**, a rare permissive Shadertoy classic): a volumetric starfield flythrough.
   The register is over-served, but the port is cheap and proven.
4. **Storm** (nimitz *Protean Clouds*, CC BY-NC-SA): a volumetric cloud flight with bounded lightning.
5. **Bioluminescent Shore**: waves break on the bar, and agitation lights the water blue.
6. **Poincaré Bloom** (PG.5, designed but unbuilt): hyperbolic tiling with per-stem Möbius flow.
7. **Lichtenberg**: per-strike dielectric breakdown. No permissive source exists yet.
8. **Jellyfish**: a bloom pulsing on the beat. Character, but no source yet.
9. A **Droste / Tunnel** via EvilJim *Tunnel of Light* (a D-107 hybrid). Over-served; last resort.

---

## 6. Sequencing and the funnel

**Wave 0: process only, no scenes (about 1 week).**
- W0.1 Mechanise R1 decoy lift and R2 two-song sheet on the QG.3 coupling harness and `compare_render.sh`.
- W0.2 Per-pass GPU timing. The registry lists it as missing, and `frame_gpu_ms` floors at about 15.3 ms,
  so the flagships cannot be priced without it.
- W0.3 A **beta test playlist**: about 10 local FLACs spanning 4/4 electronic with drops, hip-hop, rock,
  swung jazz, rubato classical, a 3/4 or 5/4 track, ambient, sung ballad, metal, and *Low*. The same list
  also gets a streaming pass, for the ≈ 2.5 s stem lag.
- W0.4 Re-render the Lane E picks and the E8 candidates through `tools/milkdrop-render` on real music, so
  Matt can eyeball them.

**Wave 1: the high-hit-rate lane.** E1–E8, Fireflies, Drumhead, Sumi, Galaxy, Harmonograph (MIT/BSD ports
and public domain).

**Wave 2: phenomenon scenes.** Pendulums, Rubens' Tube, Rain on Glass, Pool, Photosphere, Lantern, Physarum
Species.

**Wave 3: high risk, high reward.** Kagura, Supernova, Mandelbulb, Laser Haze, Goldengrove.

**Per-entry funnel.** Each step stops the entry if it fails.
1. `preset-concept` gate: artifacts 1–4, with the look spike shown to Matt. Budget: one session.
2. Musical-role sentence, reference set, temporal contract, and a design doc if the scene is non-trivial.
3. Maquette, then the rewatch bar (R1–R5) on the test playlist.
4. M7: two rounds maximum after the maquette (the PHYS escalation rule). A third round needs a changed
   "why it is failing" sentence.

**Throughput, estimated from the record rather than known.**

| Kind of scene | Examples from the record | Time |
|---|---|---|
| Faithful ports | Nacre, Floret, Glaze, Filigree | 1–3 days each |
| Native scenes | Meniscus (≈ 3 days, 11 increments), Stave (≈ 8 days), Witchlight (10 increments) | 3–10 days |
| Hero scenes | Ferrofluid Ocean (dozens of rounds) | weeks |

- Serial rough total: 8 × 2.5 + 12 × 6 + 5 × 15 ≈ **165 session-days**.
- With 2–3 parallel worktree lanes that is ≈ **9–14 weeks**.
- **The real bottleneck is Matt's live M7 time:** about 25 scenes × about 3 reviews ≈ 75 live watches.
  Batching them to about 3 scenes per sitting on the test playlist is the lever.

---

## 7. Decisions needed

**DECISION-NEEDED 1: the Milkdrop share of the beta.**
- D-119 wants ≥ 50 % inspired at steady state. On a 50-scene roster that means 18 of the next 25.
- The slate has 8, which gives 15 / 50 = 30 %.
- Option A, follow D-119: more of the library would be feedback-warp looks, the register Phosphor and
  projectM already saturate.
- Option B, 8 now, with D-119 re-scoped to post-beta: the library leads with what only Uzume can do.
- **Recommendation: B**, using unused Lane E renders as the first backfill for attrition.
- *Default if no reply:* B.

**DECISION-NEEDED 2: licensing posture for ports.**
- ShareAlike means a port of a CC BY-NC-SA shader is itself CC BY-NC-SA. It cannot be relicensed MIT, and
  it breaks the day Uzume charges money. This already applies to `AuroraVeil.metal`, whose header credits
  nimitz but carries no BY-NC-SA notice. This is not legal advice; it needs one check.
- Option A: MIT, BSD, zlib and public-domain sources only. That drops Rain on Glass and the
  Duke-referenced Supernova look, and makes Physarum Species tune its own regimes.
- Option B: allow NC-SA ports, each file marked, with a clean-room replacement listed for each.
- **Recommendation: B, capped at 3 scenes**, plus fixing Aurora Veil's header now.
- *Default:* B.

**DECISION-NEEDED 3: Plasma and Waveform.**
- **Recommendation:** make a certified scene the launch default (Aurora Veil or Nimbus; both are calm, cheap
  and non-black at silence), then remove both. Neither counts toward 50.
- Rubens' Tube takes over the waveform family's "signal made physical" role.
- *Default:* this.

**DECISION-NEEDED 4: Tier-2-first flagships.**
- Should six scenes be allowed to target 6–12 ms on M3+ and step down, or be excluded, on M1/M2 through
  `complexity_cost`?
- **Recommendation: yes.** That is what "push Apple Silicon" means in practice, and the governor ladder
  already exists.
- *Default:* yes.

---

## Sources

- Competitors:
  - https://getphosphor.com/
  - https://littleknife.dev/blog/2026/04/29/introducing-phosphor/
  - https://synesthesia.live/pricing
  - https://app.synesthesia.live/docs/ssf/audio_uniforms.html
  - https://github.com/projectM-visualizer/presets-cream-of-the-crop
  - https://steamcommunity.com/app/1358800/discussions/0/601905389490948044/
- Ports and physics sources:
  - https://github.com/PavelDoGreat/WebGL-Fluid-Simulation
  - https://github.com/MarinovM03/suminagashi
  - https://github.com/evanw/webgl-water
  - https://github.com/LuisReinoso/vibracion
  - https://github.com/evoluteur/cymatics
  - https://github.com/evoluteur/harmonograph
  - https://github.com/m1el/woscope
  - https://github.com/beltoforion/Galaxy-Renderer
  - https://github.com/Pecnut/visual-pde
  - https://github.com/Ameobea/three-good-godrays
  - https://ncase.me/fireflies/
  - https://sciencedemonstrations.fas.harvard.edu/presentations/pendulum-waves
  - http://mocap.cs.cmu.edu/faqs.php
  - https://www.sagejenson.com/36points/
  - https://mini.gmshaders.com/p/turbulence
- Shadertoy IDs confirmed through search results (shadertoy.com itself was blocked): ltffzl (Heartfelt),
  3l23Rh (Protean clouds), ltfSWn (Mandelbulb - derivative), MsVXWW (Dusty nebula 4), XlfGRj (Star Nest),
  XlBSRz (VolumetricIntegration).
