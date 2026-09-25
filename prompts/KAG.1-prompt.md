# Increment KAG.1 — Kagura clip bake + data resource (infrastructure increment)

**Objective.** After this session the Renderer target ships Kagura's dance clips as a data resource:
- `Sources/Renderer/Resources/Kagura/` holds `kagura_clips.bin`, `kagura_clips.json` and `SHA256SUMS`;
- a checked-in script re-creates them byte-for-byte from the CMU motion-capture database;
- a Swift loader decodes them, and tests pin their contents;
- `docs/CREDITS.md` carries CMU's requested acknowledgement.

**No dancer geometry, shader, sidecar or registry entry.** This increment builds and proves the data
surface that KAG.2 consumes. Kagura is the first scene to ship a non-shader data file, which is why this
increment ships alone (infrastructure never ships bundled with a scene).

Why and what: `docs/presets/KAGURA_DESIGN.md` §4 (what ships, where, and why Renderer) and §5 (the
pulse-index map). The source of every constant is the spike, `docs/presets/kagura_spike/kagura.py`, whose
numbers are recorded in `docs/presets/kagura_spike/README.md`.

## Skills to invoke

- `closeout`, at the end: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.
- **Do NOT** invoke `preset-session` or `shader-authoring`. No `.metal` file, no sidecar and no GPU code
  are written here.

## Read first (in order)

1. `docs/presets/KAGURA_DESIGN.md` §4, §5 and the §11 KAG.1 row. This is the scope boundary.
2. `docs/presets/kagura_spike/kagura.py`, these functions: `parse_asf`, `parse_amc`, `load_trial` (FK
   and the `SUBJECT_FPS` upsampling), `JOINTS15` / `point_lights` (including `@a-b` windows),
   `_contacts`, `beat_events` (the `hipyaw`, `wrists` and `gesture` pulses), `face_camera`,
   `dance_profile` (vigor), and the constants `FAMILIES` / `CLIP_PULSE` / `PULSE_LEVELS` / `DANCES`.
3. `docs/presets/kagura_spike/README.md`: the §0 **erratum** (the CMU frame-rate trap), and the clip
   tables in §5, §7 and §8 (the expected pulse rates and vigor).
4. `UzumeEngine/Package.swift`: the `Renderer` target and its existing `.copy("Resources/Fonts")`.
5. `UzumeEngine/Sources/Renderer/Dashboard/DashboardFontLoader.swift`, the Renderer resource-loading
   precedent via `Bundle.module`.
6. `docs/CREDITS.md`, for the entry format.
7. `docs/ARCHITECTURE.md` §Module Map (locate it with `grep -n "^## "`). Every new Swift file needs a row,
   and `DocIntegrityTests` enforces it.

## Pre-flight invariants (each failure stops the session)

- **Base branch.**
  - If PR hoaxpoet/uzume#268 is merged, branch `kag-1` from local `main`.
  - Otherwise branch `kag-1` from `origin/spike/kag-0`.
  - Either way, `grep -n "Renderer/Resources/Kagura" docs/presets/KAGURA_DESIGN.md` must hit. If it does
    not, STOP.
- **Tooling.** `python3` with numpy and scipy is available. On Matt's Mac mini the spike venv
  `~/Documents/uzume_spikes/kagura/.venv` has both. Otherwise create a venv **outside the repo**. Never
  add Python dependencies to the repo.
- **Source data.** `curl -sI http://mocap.cs.cmu.edu/faqs.php` returns 200. If it does not, the trials
  already cached in `~/Documents/uzume_spikes/kagura/mocap/` may be used **only** after their checksums
  are recorded (task 1). If neither is available, STOP and ask Matt.
- **Baseline.** `Scripts/closeout_evidence.sh` is green at the base commit. Known flake:
  `PlayheadAnalysisClockTests` "stalled playhead" fails only under full-suite load (109 s against 4 s
  isolated, 2026-09-24). If it fails, re-run it isolated and note it; do not "fix" it here.

## Tasks

1. **`tools/kagura/bake_clips.py` — port the spike, don't rewrite it** (FA #73 discipline applies to our
   own working code too).
   - Carry `parse_asf`, `parse_amc`, the FK in `load_trial`, `JOINTS15`, the pulse detectors, `face_camera`
     and the vigor measure over **verbatim**, apart from mechanical changes.
   - Add a **per-subject frame-rate table**: 15, 18, 20, 143 → 120 fps, plus 05 for the sway clip. The
     script **refuses any subject not in the table**. The 60 fps salsa trap is why.
   - The eleven clips are exactly `FAMILIES` for `twist`, `cabbage`, `chicken`, `macarena`, `egyptian` and
     `sway` in the spike.
   - Order of work, per clip:
     1. Cut the window.
     2. Detect pulse events **on the native 120 fps data**.
     3. Compute vigor, the pulse period and the allowed levels. Twist excludes ×½ (`PULSE_LEVELS`).
     4. Apply `face_camera` and centre on the mean pelvis floor position.
     5. **Only then** resample the positions to 60 fps.
     6. Build the pulse-index map: clip time as a PCHIP through the pulse events, 64 samples per pulse,
        float32.
   - Write `kagura_clips.bin`:
     - joints as little-endian **float16**, `[frame][15][xyz]`, metres, y up;
     - then the float32 pulse maps.
   - Write `kagura_clips.json`:
     - per clip: id, dance, fps, frame count, byte offsets and lengths, pulse kind, pulse events (s), pulse
       period (s), allowed levels, vigor (m/s), and the facing yaw applied;
     - global: joint order, units, a source and credit string, the script version, and the CMU trial
       SHA-256s.
   - **Deterministic:** sorted keys, no timestamps, fixed float formatting.
   - Modes:
     - `--download <cache>` fetches the trials to a cache **outside the repo** and verifies them against a
       checked-in `tools/kagura/cmu_sources.sha256`;
     - `--check` prints a per-clip table of pulse rate, interval CV and vigor.

   **Done-when:**
   - two consecutive runs produce byte-identical `.bin` and `.json`;
   - the total is ≤ 0.5 MB;
   - `--check` reproduces the spike's per-clip pulse rates (README §5, §7, §8) within ±2 per minute, and its
     vigor within ±0.03 m/s.

2. **The resource.**
   - Put the baked files and `SHA256SUMS` in `UzumeEngine/Sources/Renderer/Resources/Kagura/`.
   - Add `.copy("Resources/Kagura")` to the Renderer target in `Package.swift`.

   **Done-when:** `swift build --package-path UzumeEngine` succeeds, and the files resolve through
   Renderer's `Bundle.module` at runtime (task 4 proves it).

3. **The Swift loader** (in Renderer, e.g. `Sources/Renderer/Geometry/Kagura/KaguraClipLibrary.swift`).
   - It is `Sendable` and decodes the manifest and binary once. Errors are thrown, never force-unwrapped
     (SwiftLint `force_*` rules are errors).
   - API:
     - clips by dance;
     - per-clip metadata;
     - `pose(at clipTime:)`, linear interpolation across frames into 15 × `SIMD3<Float>`;
     - `clipTime(atPulse u:)`, linear lookup in the pulse map;
     - the sway clip.
   - `///` doc comments on all public API, and `// MARK: -` dividers.

   **Done-when:** it compiles under Swift 6 strict concurrency with no warnings (warnings are errors).

4. **Tests: `KaguraClipLibraryTests`** (engine test target). They run against the real bundled resource;
   nothing is synthetic.
   - All 11 clips decode, with 15 joints at 60 fps.
   - `SHA256SUMS` matches the bundled files.
   - Every pulse map is strictly monotone.
   - Every clip's mean hip line sits within ±2° of the common three-quarter target.
   - The minimum ankle height per clip is within ±2 cm of 0 (feet on the floor).
   - Each clip's pulse rate is within ±2 per minute of its manifest value.
   - Twist clips list no ×½ level.

   **Done-when:** `swift test --package-path UzumeEngine --filter KaguraClipLibrary` passes.

5. **Docs.**
   - `docs/CREDITS.md`: a new entry for the CMU Graphics Lab Motion Capture Database with:
     - the FAQ's permission sentence, verbatim: *"The motion capture data may be copied, modified, or
       redistributed without permission."*
     - the requested acknowledgement, verbatim: "The data used in this project was obtained from
       mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217."
     - the list of trials used, and a note that only derived 15-joint tracks ship.
   - `docs/ARCHITECTURE.md` §Module Map: rows for every new Swift file.
   - `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`: a new capability row, *bundled non-shader scene data
     resource (Renderer)*, citing the files.
   - `docs/ENGINEERING_PLAN.md`: flip the KAG.1 row to ✅ with the date and evidence.

   **Done-when:** `swift test --package-path UzumeEngine --filter DocIntegrityTests` passes.

6. **Closeout** (see below).

## Do NOT

- Do not write `KaguraDancer`, any `.metal` file, a sidecar, a `ParticleGeometryRegistry` or
  `StatefulRuntimeRegistry` entry, or any `VisualizerEngine` wiring. That is KAG.2.
- Do not commit raw ASF/AMC files, or any file over 1 MB. Do not use Git LFS (banned for `*.bin`,
  CLEAN.5.8) or a Release asset. The resource is small and tracked.
- Do not add or change clips, windows, pulse detectors or level rules. They are Matt's decided library
  (KAGURA_DESIGN §4). In particular, no salsa, Lindy, Russian (`90_*`), `141_12`, `143_34` or `90_31`.
- Do not touch D-154 thresholds or `assessBeatIrregularity`. The Superstition false positive is its own
  task.
- Do not put the resource in the Presets target. Renderer cannot read it there (KAGURA_DESIGN §4).
- Do not push without Matt's explicit "yes, push". When approved, push the branch and open a PR. **Never
  push to `main`.**

## Verification

```bash
python3 tools/kagura/bake_clips.py --check
```
```bash
swift test --package-path UzumeEngine --filter KaguraClipLibrary
```
```bash
swift test --package-path UzumeEngine --filter DocIntegrityTests
```
```bash
swiftlint lint --strict --config .swiftlint.yml
```
```bash
Scripts/closeout_evidence.sh
```
```bash
git status --short
```

The bake's byte-identity check is two runs to a temporary output directory followed by `cmp` of each
output file.

## Commits (local; small, one per step)

- `[KAG.1] tools: bake_clips.py — port of the KAG.0 loader, per-subject fps table, deterministic output`
- `[KAG.1] Renderer: Kagura clip resource + Package.swift copy rule`
- `[KAG.1] Renderer: KaguraClipLibrary loader`
- `[KAG.1] tests: KaguraClipLibraryTests`
- `[KAG.1] docs: CREDITS (CMU), Module Map, capability registry, EP row`

## Closeout

Invoke `closeout`: the 8-part report with the verbatim `closeout_evidence.sh` block as §2. Add:
- the bake's byte-identity proof: the SHA-256 of the output from two runs;
- the `--check` table next to the spike's expected values;
- the resource size.

State explicitly that nothing here is visually verifiable (no scene yet).

## DECISION-NEEDED

None. This is an infrastructure increment, and every product call it depends on is already recorded
(KAGURA_DESIGN §4, §6, §7).
