# Understory — implementation plan (for review)

Companion to `docs/presets/UNDERSTORY_DESIGN.md`. Written 2026-10-01. Every increment opens with
the `preset-session` skill (and `shader-authoring` before any `.metal` edit) and closes with the
`closeout` skill. Commits use `[UND.n] <component>: <description>`. Nothing is pushed without Matt's
"yes, push", and then only to a branch with a PR.

## Locked decisions (Matt, 2026-10-01)

- **Source:** *flexi - fractal seafood*, the swaying fern frond. *Ferny ernie* was considered and
  set aside.
- **A new scene, not a faithful uplift.** Flexi's frond mechanism is kept verbatim; the scene adds
  more fronds and music-tied motion. The swimming creature and the goo background are dropped.
- **Shimmer pattern:** one frond per beat, stepping through a set of fronds each bar, downbeat on a
  larger lead frond, repeating so the listener learns it (design §4.3).
- **Vocals play a role, but not Gossamer's.** Chosen role: vocal phrases unfurl foreground
  fiddleheads (design §4.4).
- **Colour:** psychedelic, not a realistic fern (design §4.5).

- **Composition (Matt, 2026-10-01, §10-3):** a field of ferns, open fronds and fiddleheads at mixed
  coil stages, dark ground between them (design §4.1). Not a blanket.

Still open, with defaults: design §10 (name, no-beat tracks, instrumental fiddleheads).

**Status (2026-10-01):** UND.0 ✅ · UND.1 built, awaiting Matt's GO / NO-GO (design §12).

## Roadmap at a glance

| Increment | What | Retires risk | Gate to proceed |
|---|---|---|---|
| **UND.0** | Reference lock + harness first | — | Source motion-gated; refs curated; persistent-staged harness runs at silence |
| **UND.1** | **Look-spike:** one frond, Flexi verbatim | Port fidelity | **Matt GO / NO-GO** on motion-gated frames vs the source (concept-gate artifact 4) |
| **UND.2** | The bed: 12-tile atlas, layout, wind | Atlas seams/resolution (level 3) | Matt review of a field render; Release perf measured |
| **UND.3** | Colour + path-length stamp + trails | Stamp coordinate (level 3) | Stamp verified still + sequence; palette on harmony |
| **UND.4** | Shimmer sequencer | Beat footprint, cold start | Replay log shows correct order; 0.00 flashes/s |
| **UND.5** | Fiddleheads + vocals | κ coil look; vocal route | Routes green on vocal + instrumental fixtures |
| **UND.6** | M7 tuning rounds | Feel | Matt M7 PASS |
| **UND.7** | Certification | — | All §4 NEW_PRESET_CHECKLIST gates green |

Cut-line: UND.1–UND.4 is a complete scene (bed + wind + colour + shimmer). UND.5 can be deferred
without breaking anything; until then the fiddleheads simply aren't in the layout.

## Increment detail

### UND.0 — Reference lock + harness first

1. **Source oracle.** Render *flexi - fractal seafood* through `tools/milkdrop-render/` from the
   `butterchurn-presets@2.4.7` converted JSON (design §3, sha256 recorded). Use the three tempo
   fixtures, 12 s each. Films stay outside git (D-211). Run `Scripts/motion_gate.sh` on the frames
   and record the verdict, which is concept-gate artifact 2 made formal.
2. **Visual references** (`docs/VISUAL_REFERENCES/understory/`, from `_TEMPLATE/README_LIGHTWEIGHT.md`).
   Slots: (01) the source oracle still, frond structure; (02) a real fiddlehead uncoiling, the coil
   target; (03) a dense fern bed seen from low, the overlap and depth composition; (04) a psychedelic
   palette anchor, e.g. UV-fluorescent subject or a butterchurn built-in whose palette Matt likes;
   (05–06) anti-references: a realistic green fern, the textbook Barnsley fern. Wikimedia sourcing
   with licence rows, force-added per the post-2026-08-25 process. AI images are allowed only in an
   anti slot (D-065). **Matt reviews the set.**
3. **Harness first** (PRESET_SESSION_CHECKLIST Part 2). Adapt `PersistentStagedPathHarnessTemplate`
   to a 3-stage `fronds → bed → present` stub. Show the persistent pair is reachable from a test and
   that 60 frames at silence are non-black and finite, before any shader work.
4. **Sidecar skeleton:** `certified: false`, `rubric_profile: lightweight`, `passes: ["staged"]`,
   `inspired_by` (design §3), empty-but-declared `audio_routes` to be filled per increment.

**Evidence:** motion-gate verdict on the source; reference README; harness green.

### UND.1 — Look-spike: one frond, verbatim (GO / NO-GO)

- `fronds` stage: Flexi's three maps, seed and −0.015 fade, verbatim, full-screen (no tiles yet).
- CPU `UnderstoryField` with **one** frond: Flexi's two springs at 60 Hz substeps, drive =
  `bass_dev − treb_dev`. Re-fit the 0.2 drive gain by measuring the deviation range on the fixtures,
  then the coefficients are frozen.
- `present`: a flat single colour on a dark ground. Colour comes later.
- **Show Matt:** a side-by-side film of the Uzume frond and the butterchurn oracle on the same audio,
  plus `motion_gate.sh` sampled frames and a motion verdict. The question: *is this the frond, and
  does it sway the way you remember?*
- **NO-GO** if the port cannot match the source's whip in motion after one fix round. Stop and
  re-scope with Matt; do not tune into a spiral.

### UND.2 — The bed: atlas, layout, wind

- Split `fronds` into 12 tiles; per-tile maps from `buffer(6)`; sampling clamped to the tile.
- Seeded layout (design §4.1): three layers, roots below the frame, fanned headings, jitter, no
  symmetry (FA #44). Re-seed at track change.
- Wind: delayed drive per frond (`x_i / v_wind`) + ±15% stiffness jitter.
- `bed` composite: back → front painter's order, bounding-box reject, flat per-layer tints for now.
- **Decide on renders:** tile resolution (uniform vs larger front tiles, design §5.4); whether
  mirrored back-layer twins read as copies.
- **Measure:** Release frame time at 1080p (and 4K once) → `complexity_cost`.
- **If seams or softness kill it:** stop and bring the analytic-frond fallback (design §5.1) to Matt
  as a decision; don't silently switch mechanisms.

### UND.3 — Colour, path-length stamp, trails

- G-channel frame stamp (design §5.3). Verify on a still (the coordinate increases monotonically base
  → tip and into leaflets) and on a sequence (stable, no speckle at map overlaps) **before** anything
  reads it.
- Psychedelic palette along path length, per-frond offsets, layer dimming, palette rotation on
  `tonal_phase_fifths`, ground tied to the complement.
- `bed` becomes persistent: `max(bed, prev·decay)`, with decay from `arousal`.
- Routes added to `audio_routes`; `RouteCoverageTests` green for wind, palette and trails.
- `Scripts/compare_render.sh understory` + a verdict table against the curated refs.

### UND.4 — Shimmer sequencer

- CPU sequencer: beat = `beat_phase01` wrap, downbeat = `bar_phase01` wrap, set size =
  `beats_per_bar`; lead frond on 1, middle-layer set on 2…N, the set rotates every 4 bars.
- Shimmer band in `bed` driven by path length (design §4.3). Speed and width tuned by eye on renders.
- Grid-trust gate (design §6.1): no shimmer until `bar_phase01` has wrapped and 4 s have elapsed. No
  grid: the default fallback (drum-energy peaks, ≥ 0.35 s apart, random frond) unless Matt chose
  otherwise.
- **Evidence:** a `PresetSessionReplay` log of (beat time, frond index) checked against the grid;
  frames extracted at beat times; photosensitivity measured at 0.00 flashes/s.

### UND.5 — Fiddleheads + vocals

- Curl bias κ on the two foreground fiddleheads; pick κ_max from coil renders against ref 02.
- `unfurl` from `vocals_energy_rel` with the D-019 gate, attack ~1.5 s, release ~5 s.
- **Evidence:** route fires on a vocal fixture; the fiddleheads stay coiled on an instrumental one.
  Both captured on the local-file and the live path (the live path lags ~2.5 s, AUDIO_CONTRACT §2.3).

### UND.6 — M7 tuning

Live review on real music with a `clean` chain-health verdict. After each round, write one sentence:
*what I now believe about why this scene is failing.* If it doesn't change between rounds, stop and
re-scope.

### UND.7 — Certification

NEW_PRESET_CHECKLIST §4: Matt's M7, `certified: true`, `FidelityRubricTests.certifiedPresets`,
photosensitivity multi-pass measurement + `MultiPassFlashHarnessTests` render function,
`OrchestratorCertifiedFilterTests`. A 10-minute soak with the non-finite watchdog silent.
`docs/CREDITS.md` row for Flexi.

## Sequencing, cut-lines, risk

- **Biggest risk: UND.2.** A bed of independent feedback fronds has no reference anywhere. It is
  placed before any colour or audio work so a failure costs one increment, not five.
- **Second risk: UND.3's stamp.** If it speckles, the fallback is a per-tile analytic path-length
  estimate (distance along the main stem from the CPU-known frond curve). Coarser for leaflets but
  sufficient for the shimmer.
- **First production persistent stage.** UND.0's harness and the watchdog soak exist to catch the
  failures a diagnostic-only feature hasn't met yet.
- **Engine additions:** none planned. A fixed-size stage target is the only candidate (design §5.4),
  and it is brought to Matt before it is built.

## Documentation write-backs

Per design §11, at each increment's closeout, not batched at the end.

## To proceed

Matt: confirm or change the four defaults in design §10. UND.0 can start either way, since none of
them affect it.
