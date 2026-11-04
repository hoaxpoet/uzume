# Increment VQ.2b — Energetic Flyby on HDR: the light that clips today shines, the rest stays Kali's (preset + engine increment)

**Objective.** After this session, Energetic Flyby on an HDR display shows its hottest light above SDR white, and
everything else looks as it does today:

- **On HDR, only the light that clips today goes brighter.** Kali's glow sums past white in places (the fragment
  `saturate`s it before output). On an HDR display that clipped light shines, up to 4× SDR white (D-267). Every
  pixel that is not clipped today looks the same as on SDR.
- **On SDR, nothing changes.** The certified picture (EFB.3, Matt's "Kali's colour") is the oracle. Goldens do not
  move.
- **Flashes stay safe.** Energetic Flyby's worst-case regional flash train sits **at** the limit today (3.00/s vs 3).
  HDR may not add a single flash at either anchor (SDR white, the display's peak).
- **30 fps holds.** The scene runs at native resolution, capped at 30 fps (Matt, EFB.1). The finish's cost fits in
  that budget on the M2 Pro at the LG's 4K.

**Why now.** VQ.2 built HDR output (D-267). VQ.2a gave it its first scene and fixed the curve: below graded 1.0, HDR
equals SDR (D-268). Energetic Flyby is the second consumer named in the VQ.2 prompt. It is the scene whose look is
most about light ("lit from inside", neon rods), and today its brightest light is cut off at the same white as a
menu bar.

**What is already true** (verified 2026-11-04 against `main` at b3a86a0b):

- Energetic Flyby is a `direct` scene with **no `finish` block** (legacy: its own 8-bit pixels). Its fragment ends
  `o.color = efb_srgb_to_linear(saturate(col))`: Kali's colour is display-referred, and `saturate` is the clip
  (`EnergeticFlyby.metal`, the fragment's last lines; the glow is composed in `efb_march`).
- `finish.hdr` only takes effect in **cinematic** mode. The cinematic finish applies the Lottes display transform
  and a grade. Lottes is **not** identity below 1.0, so moving Energetic Flyby to cinematic as it stands would
  change its SDR look. VQ.1c accepted a new look for Ferrofluid Ocean (Matt approved it). Energetic Flyby gets no
  new look on SDR.
- `FinishSpec` has `mode`, `bloom`, `grade`, `lut`, `hdr`, and no way to say "this scene is already
  display-referred". Task 2 decides how the scene's light enters the finish. That is an engineering choice: make it
  and record why.
- The shipped flash gate for this scene is `MultiPassFlashHarnessTests.energeticFlybyIsFlashSafe`. It ticks the
  real `EnergeticFlybyState`. The single-pass photosensitivity harness skips the scene (it binds a zeroed slot 6).
- The offline HDR replay exists (VQ.2a): `REPLAY_HDR=<headroom>` on `SessionDrivenMultiPassReplay` writes SDR|HDR
  10-bit PQ side-by-sides, an over-white mask and flash reports at both anchors (RUNBOOK §VQ.2). It was built and
  exercised on a ray-march scene. **Whether it reaches the finish's HDR branch on a `direct` scene is unverified.**

## Matt's decisions so far

- EFB.1: **no upscaling for this scene, ever** (stretch kept, EFB.4 option B); **30 fps** accepted; **Kali's colour**
  (the steady glow matches Kali's average, 1.25); **downbeat = colour turn only** (any brightness flare broke the
  regional flash limit).
- VQ.2 (D-267): highlights up to 4× SDR white; no ninth of the screen averages above SDR white; HDR on by default.
- VQ.2a (D-268): below graded 1.0, HDR equals SDR.

## DECISION-NEEDED (asked at task 3, after task 1's measurement)

**What should shine on an HDR display?**

- **A. Everything that clips today.** The light rods, the bright inner glow of the shells, the spheres' hottest
  spots: wherever Kali's light runs past white, it runs on to up to 4×. This is closest to "lit from inside" and
  gives the most HDR. Large glowing areas are held at white by the cap, so bright passages can look flatter than
  their small highlights.
- **B. The light rods only.** The rods thrown by the spinning spheres become hot neon lines. The tunnel and its
  glow stay exactly as today. This is the smallest change and the lowest flash risk.
- **C. The spheres only.** The spiked sphere cluster you follow gets the extra brightness. The tunnel and rods stay
  as today.

**Recommendation:** A if task 1 shows the clipped light is small and scattered (a few percent of the picture) and it
passes the flash gate. Otherwise B. **Default if no reply:** B. It changes the least, and the flash margin is zero.

Ask it once, in words, quoting task 1's numbers: the share of the picture that clips, and where (rods, shells,
spheres). Do not open images in Matt's view to ask it (memory: don't iterate renders in Matt's view).

## Skills to invoke

- `preset-session`: before any `.metal` or sidecar edit (this changes a certified scene).
- `shader-authoring`: before GPU code.
- `closeout`: at the end.

## Read first (in order)

1. `docs/presets/ENERGETIC_FLYBY_DESIGN.md`: §5 Photosensitivity, §7 Cost (the regional limit at 3.00/s, why no
   downbeat flare, Kali's average glow) and §10 (decisions taken).
2. `docs/VISUAL_REFERENCES/energetic_flyby/README.md`: `03_lighting_neon_glow`, `05_anti_whole_frame_whiteout`.
3. `docs/DECISIONS.md`: D-267, D-268, and D-263's EFB.4 amendment (via the §Index).
4. `prompts/VQ.2-prompt.md`: the closing consumer list (VQ.2a, VQ.2b).
5. `UzumeEngine/Sources/Presets/Shaders/EnergeticFlyby.metal`: `efb_march` (glow composition, the white-out fix)
   and the fragment's output.
6. `UzumeEngine/Sources/Renderer/FinishingStage.swift` + `Shaders/FinishingStage.metal`: `finish_tone`,
   `displayTransform`, the regional cap.
7. `UzumeEngine/Sources/Shared/FinishSpec.swift`.
8. `UzumeEngine/Tests/UzumeEngineTests/Renderer/MultiPassFlashHarnessTests.swift` (`energeticFlybyIsFlashSafe`),
   `EnergeticFlybyRenderTests.swift`.
9. `UzumeEngine/Tests/UzumeEngineTests/Presets/SessionDrivenMultiPassReplay.swift` (`REPLAY_HDR`), RUNBOOK §VQ.2.

## Pre-flight invariants (each failure stops the session)

- VQ.2a (#373) is on `origin/main`. Work on branch `vq-2b`, cut from an up-to-date `main`.
- `Scripts/closeout_evidence.sh` is green at the base.
- `Scripts/link_fixtures.sh` has run if this is a worktree.
- Record the baseline:
  - Energetic Flyby's `PresetRegressionTests` dHash values;
  - `energeticFlybyIsFlashSafe` (flashes/s whole, regional, red);
  - a 1080p and a tier-1-capped 4K oracle frame of today's legacy output, at a fixed drive.
  This is the "SDR did not change" oracle.

## Tasks

1. **Measure what clips today.** Instrument the fragment's pre-`saturate` colour (test-only path or harness
   readback; nothing shipped) and replay the three real-audio route fixtures (`so_what`, `there_there`,
   `love_rehab`) at 1920×1080, 600 frames each. Report per track:
   - the share of pixels with any channel > 1;
   - p99.9 of the brightest channel;
   - where the clipped light comes from: rods (`h.rod`), glow (`h.glow`), surfaces.

   Write a mask per sampled frame.
   **Done-when:** the table exists in the closeout draft, and the masks have been looked at by you, not by Matt.

2. **Get the scene's light into the finish without changing SDR.** Move Energetic Flyby to the cinematic finish so
   that, on SDR, the finished image equals today's legacy output. Hold it to the oracle: the GPU's sRGB store
   rounding is the only allowed difference (VQ.2 measured ≤ 1 code, D-267). Keep the over-1 part of Kali's colour
   (what `saturate` removes today) as scene light above the HDR knee, so the finish's HDR ramp (D-268) is the only
   thing that shows it.
   - Choose the mechanism. Candidates:
     - a finish option for display-referred scenes (no Lottes, no grade below 1.0);
     - writing the inverse of the SDR curve from the fragment.
   - Record why you chose it. Note the inverse's trap: display values above the knee's image would brighten on HDR,
     which breaks "the rest stays".
   - No bloom (`bloom.strength` 0). The stretch stays bilinear (no spatial, no temporal; EFB.4 / Matt).
   - Keep the EFB.4 depth/motion/reactive outputs byte-identical on the plain path.

   **Done-when:**
   - `PresetRegressionTests` dHash unchanged and the oracle within 1 code at both sizes, with headroom 1;
   - `FinishFormatMatchTests` passes for the scene under `MTL_DEBUG_LAYER=1`;
   - `energeticFlybyIsFlashSafe` is unchanged from the baseline.

3. **Ask Matt the DECISION-NEEDED question** with task 1's numbers. **Stop and wait for his answer** (or apply the
   default if he says to go on without one).

4. **Shape what shines, per Matt's answer.** Limit the light above the knee to the chosen sources: A all, B rods
   (`h.rod`), C spheres. Light outside the choice is clipped at today's white, as now.
   **Done-when:** the replay with `REPLAY_HDR=4` on the three fixtures (1080p, 600 frames) shows all of these:
   - dark and mid areas identical SDR vs HDR (mean luma below the knee unchanged; report the measure you use);
   - the share above white and the p99.9;
   - largest ninth ≤ 1;
   - flash at both anchors no worse than the baseline;
   - masks that show only the chosen sources.

5. **Flash gate, HDR.** Run `energeticFlybyIsFlashSafe` on the cinematic path at headroom 1, 4 and 16, against SDR
   white and against the display's peak (extend the test to carry headroom; its worst-case train is the gate).
   **Done-when:**
   - flashes/s at every headroom and anchor ≤ the baseline;
   - regional ≤ 3.00 everywhere.

   **If any arm adds a flash, stop and report.** Do not dim the glow, add a brightness limit, or change the energy
   coupling to buy margin without Matt's decision. That would change the scene's look, and its flash margin is zero
   by his EFB.1 call.

6. **Cost and 30 fps.**
   - Release, M2 Pro, `.private` targets, GPU saturated: measure the finish at the scene's render size → the 4K
     drawable, SDR and HDR.
   - Live Release app on the LG, HDR on, scene pinned, fullscreen 16:9 (check `RENDER_TARGET`: a near-square window
     costs ~1.5×): 45 s clean window.

   **Done-when:**
   - live 30.0 fps held with HDR on and off;
   - frames past 33 ms reported against EFB.2's baseline (3.0 %);
   - memory (the `.rgba16Float` frame target at render size) stays under the 858 MiB ceiling.

7. **Matt's look on the LG.**
   - Converge offline first.
   - Then show ONE side-by-side: a PQ HEIC, SDR left and HDR right, 1:1 on the 4K, opened in Preview with macOS HDR
     on for the LG.
   - Then a live look with a **Developer ID** build (Apple-Dev builds loop on Screen Recording). The scene moves:
     its HDR is judged in motion, not from the still alone.

   **Done-when:** Matt's words are recorded. Until he has seen it live, the status is "pending live M7".

8. **Docs.**
   - A D-number for the display-referred route into the finish (assigned at run time from the tree; D-269 if free).
   - ARCHITECTURE §HDR Output (the second adopter and the mechanism).
   - SHADER_CRAFT §17 if the sidecar gains a field.
   - `docs/presets/ENERGETIC_FLYBY_DESIGN.md` and the references README (a VQ.2b round).
   - ENGINEERING_PLAN:
     - a VQ.2b row;
     - VQ.2a's row moved to merged #373 (b3a86a0b) — it still says "built on branch `vq-2a`".
   - RENDER_CAPABILITY_REGISTRY: the HDR row's consumers.
   - `HDROutputTests`' pinned adopter list.

## Do NOT

- **SDR look.** Do not change Energetic Flyby's SDR picture: no grade, no bloom, no new tone curve on SDR. Kali's
  colour is Matt's call (EFB.1), and the certified build is what he approved.
- **Upscaling.** No spatial or temporal upscaling, no reconstruction re-pitch (EFB.4 option B, D-263 amendment).
- **Brightness motion.** No downbeat brightness flare, and no change to the glow or energy coupling (EFB.1: flash
  margin zero).
- **Ray-march cost cuts.** Do not cut the march's depth or step count to pay for the finish (EFB.1: "blurry and
  pixelated").
- **Other scenes.** No other scene opts into HDR. Do not change the HDR curve (D-268) or the cap (D-267). If the
  mechanism in task 2 is a new finish option, every existing scene stays byte-identical.
- **Frame-rate cap.** Do not lift the 30 fps cap. Frame generation is VQ.4a.
- **Pushing.** Do not push.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine --filter PresetRegression
swift test --package-path UzumeEngine --filter FidelityRubric
swift test --package-path UzumeEngine --filter RouteCoverage
swift test --package-path UzumeEngine --filter MultiPassFlash
swift test --package-path UzumeEngine --filter EnergeticFlyby
swift test --package-path UzumeEngine --filter HDR
swift test --package-path UzumeEngine --filter FinishingStage
MTL_DEBUG_LAYER=1 swift test --package-path UzumeEngine --filter FinishFormatMatch
swift test --package-path UzumeEngine --filter FinishLegacyOracle
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
Scripts/closeout_evidence.sh
```

Plus `Scripts/compare_render.sh "Energetic Flyby"` (D-181 still sheet + verdict table) and `Scripts/motion_gate.sh`
(D-195) before any tuning commit, and the `REPLAY_HDR=4` replay on the three fixtures.

## Commit message templates

- `[VQ.2b] Tests: measure the light Energetic Flyby clips today`
- `[VQ.2b] Renderer: display-referred scenes into the cinematic finish, SDR unchanged`
- `[VQ.2b] Energetic Flyby: cinematic finish, finish.hdr, over-white light from <Matt's choice>`
- `[VQ.2b] Tests: Energetic Flyby flash gate at HDR headrooms, both anchors`
- `[VQ.2b] docs: D-number, design doc, architecture, registry, plan`

Local commits only. Push only on Matt's explicit "yes, push", to the `vq-2b` branch with a PR, never to `main`.

## Closeout

Invoke the `closeout` skill and produce the 8-part report, with the verbatim `Scripts/closeout_evidence.sh` block
as §2. Add the following:

- task 1's clip table (share, p99.9, source split per track);
- the mechanism chosen in task 2 and why; the SDR oracle result at both sizes;
- Matt's DECISION-NEEDED answer, quoted;
- the HDR replay table (three tracks) and the flash table (headroom 1/4/16 × both anchors, against the baseline);
- the cost table and the live LG run (fps, frames past 33 ms, `RENDER_TARGET`);
- Matt's words after the side-by-side and the live look.
