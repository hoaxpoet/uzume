# Vocabulary — scene vs. preset

Written at VOCAB.1. Two jobs: state the rule a contributor and a maintainer
both work under today, and make the deeper rename (Option C) cheap to scope
later without re-reading the engine.

---

## 1. The rule

**What a person reads says *scene*. Code and data say `preset`.**

"Scene" is the word on uzume.io, in this repo's guides, and on screen in the
app — Matt's direction is that there is no per-audience vocabulary, so the
contributor call to action ("Write a scene") and the app's Settings panel use
the same noun. Code identifiers, type names, file paths, module names and JSON
keys were deliberately left saying `preset`; see §3–§5 for why that is one
increment rather than a sweep.

Three standing exceptions, which are not drift:

1. **Milkdrop's *preset* is Milkdrop's word.** Its visualizers, its packs, its
   licence posture and takedown path keep it. `docs/CREDITS.md` deliberately
   reads "Uzume scene | Source Milkdrop preset" in one table row — that row is
   the distinction, not an oversight.
2. **Verbatim quotes are never rewritten.** `PRESET_SESSION_CHECKLIST.md` §44
   quotes Matt saying "the preset's design"; it stays as said.
3. **Names of things are not prose.** A heading cited by cross-reference
   (RUNBOOK §Certifying a preset), a CLI placeholder (`compare_render.sh
   <preset>`), a path, an identifier.

Adopted at VOCAB.1: `CONTRIBUTING.md`, `README.md`, `docs/GLOSSARY.md`,
`docs/CREDITS.md`, `docs/UX_SPEC.md`, `docs/PRESET_SESSION_CHECKLIST.md`,
`docs/presets/YOUR_FIRST_PRESET.md`, `docs/presets/NEW_PRESET_CHECKLIST.md`,
and `UzumeApp/en.lproj/Localizable.strings`.

**Not yet adopted** — living maintainer references that still say `preset` in
prose. These are a follow-on prose sweep, independent of Option C, and are
listed here so nobody rediscovers them (occurrence counts, `git grep -Ioi`):

| Doc | Occurrences |
|---|---|
| `docs/ARCHITECTURE.md` | 374 |
| `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` | 312 |
| `docs/SHADER_CRAFT.md` | 231 |
| `docs/QUALITY/KNOWN_ISSUES.md` | 200 |
| `docs/CAPABILITY_REGISTRY/PRESETS.md` | 188 |
| `docs/RUNBOOK.md` | 30 |
| `CLAUDE.md` | 27 |
| `docs/PUBLISHING.md` | 5 |

**Deliberately frozen, not a sweep target:** append-only records —
`DECISIONS*.md`, `ENGINEERING_PLAN*.md`, `RELEASE_NOTES_DEV*.md`,
`KNOWN_ISSUES_HISTORY.md`, `prompts/`, `docs/prompts/`, `archive/`,
`docs/diagnostics/`, `docs/reviews/`, and the per-scene design docs under
`docs/presets/`. They record what was written when it was written; rewriting
them would falsify the record.

---

## 2. Inventory (VOCAB.1, whole tree)

**20,364** occurrences of "preset" across tracked files, by group:

| Group | What | Size | In scope at VOCAB.1 |
|---|---|---|---|
| (a) | Prose a human reads — docs, comments | 13,156 in `*.md`; 2,326 Swift comment lines | Contributor path only (§1) |
| (b) | Strings the app displays | 9 values in `Localizable.strings` + 1 DEBUG toast | ✅ all |
| (c) | Code identifiers, type names, file paths | 6,678 in `*.swift`, 253 in `*.metal`, 128 in `*.sh`/`*.py`/`*.js`, 25 in `project.pbxproj`; 315 tracked paths | ❌ Option C |
| (d) | Data — JSON keys, values, directory names | 31 sidecars; **0 keys** contain "preset" | ❌ Option C |

---

## 3. Group (c) — code identifiers and paths

**40 declared type names** (`git grep -E '(class|struct|enum|protocol|actor|typealias) +[A-Za-z0-9_]*[Pp]reset'`):

> DefaultPresetScorer, FakePreset, FakePresetPublisher,
> FrameBudgetManagerResetOnPresetChangeTests, LoadedPreset,
> PlannedPresetSegment, PresetAcceptanceTests, PresetCategory,
> PresetCategoryBlocklistPicker, PresetCertificationStore,
> PresetContrastCertificationTests, PresetDescriptor, PresetDisplay,
> PresetFixtureContext, PresetFrameBudgetTests, PresetHashes,
> PresetHistoryEntry, PresetLoader, PresetLoaderCompileFailureTest,
> PresetLoaderSidecarTests, PresetOverride, PresetRegressionTests,
> PresetScoreBreakdown, PresetScorerAdaptationTests, PresetScorerTests,
> PresetScoringContext, PresetScoringContextExtensionTests,
> PresetScoringContextProvider, PresetScoringContextProviderTests,
> PresetSessionReplay, PresetSidecarKeyGateTests, PresetSignaling,
> PresetSignalingDefaults, PresetSignalingTests, PresetStage,
> PresetStageDecodeTests, PresetTestError, PresetVisualReviewTests,
> StagedPresetBufferBindingTests, TrackChangePresetResetRegressionTests

**Directories and modules** (315 tracked paths contain "preset"):

| Path | Note |
|---|---|
| `UzumeEngine/Sources/Presets/` | SPM target **named `Presets`** (`Package.swift:70`) — **161 files `import Presets`**; the module name is also the resource-bundle name |
| `UzumeEngine/Sources/Presets/Shaders/` | 63 files — **the sidecar directory the website globs** (§4) |
| `UzumeEngine/Sources/PresetSessionReplay/` | 14 files, a diagnostic CLI target |
| `UzumeEngine/Sources/Presets/Certification/` | 5 files |
| `UzumeEngine/Tests/UzumeEngineTests/Presets/` | 62 files |
| `docs/presets/` | 46 files, cross-linked from README/CONTRIBUTING |
| `.claude/skills/preset-session/`, `.claude/skills/preset-concept/` | skill names, referenced by name from `CLAUDE.md` and by each skill's own `description:` trigger text |

**Other identifier surfaces:** `UzumeApp/Views/Settings/VisualsSettingsSection.swift`
(localization *keys* `settings.visuals.presets.title`,
`settings.visuals.show_uncertified_presets.*`),
`UzumeApp/VisualizerEngine+Presets.swift` (`applyPreset`),
`UzumeApp/Services/PresetScoringContextProvider.swift`.

---

## 4. Group (d) — data

**No sidecar key contains "preset".** The keys are `name`, `family`,
`certified`, `passes`, `audio_routes`, `rubric_profile`, `inspired_by`, … The
data-side exposure is not key names; it is three other things:

1. **The directory** `UzumeEngine/Sources/Presets/Shaders/*.json`.
2. **The `name` *value***, which is load-bearing twice over — see §4.1.
3. **`"preset_fragment"`**, the hardcoded default Metal fragment entry point
   (`PresetDescriptor.swift:635`), used by `Nebula`, `Plasma` and `Waveform`
   and by every hot-reloaded scene that omits `fragment_function`.

### 4.1 The cross-repo contract — what uzume.io reads

`hoaxpoet/uzume-site`'s `Scripts/generate_presets.py` generates the site's
`presets` content collection from this repo. **Treat all of the following as
public API.**

| The site depends on | Exactly what |
|---|---|
| Path glob | `UzumeEngine/Sources/Presets/Shaders/*.json`, read relative to an app-repo checkout (default `~/Documents/Projects/uzume`) |
| Keys read | `name`, `author`, `description`, `family`, `certified`, plus `inspired_by` when present |
| The join key | `slugify(sidecar["name"])` — **there is no `slug` key in any sidecar.** The slug is derived from the `name` *value*, and is joined against `src/data/media.json` and `Scripts/preset_captions.json` on the site side |
| `certified` | still gates what ships; the site stopped *saying* "certified" in copy, the field is unaffected |

Consequences worth stating plainly:

- **Changing any scene's `name` value silently orphans its website entry** —
  its footage and its caption are keyed by the old slug. This is true today,
  independent of Option C.
- The generator names its output collection `presets` and its captions file
  `preset_captions.json`. Those are site-side names; renaming them is the
  website's half of Option C, not this repo's.
- `description` is carried but never rendered — the published sentence is the
  site-authored caption. So sidecar `description` prose was left alone at
  VOCAB.1: it is maintainer-facing data, not published copy.

**Verified at VOCAB.1:** `generate_presets.py --check` against this worktree
exits 0, 8 entries, no entry would change.

---

## 5. Option C — one word everywhere, code included

Option C is the intended end state: `Preset` → `Scene` in code and data too,
coordinated across both repos. It was deferred because it is large, it lands
near the sidecar schema, and the website's generator depends on some of these
names. **Do not do part of it opportunistically** — a half-finished identifier
rename is worse than none.

### 5.1 What it would touch

- **40 type names** (§3) and their 6,678 Swift references across 386 files.
- **The SPM target `Presets`** — 161 `import Presets` statements, plus the
  generated resource-bundle name.
- **7 directories** (§3), each a `git mv` plus the Xcode
  `project.pbxproj` four-section re-registration (25 occurrences there).
- **253 occurrences in `*.metal`**, including the `preset_fragment` entry
  point in 3 shaders.
- **128 occurrences in `Scripts/`** (`*.sh`, `*.py`, `*.js`) — the harnesses
  and gate scripts contributors are told to run by name.
- **Test fixtures and name-keyed test tables:**
  `FidelityRubricTests.certifiedPresets` and `.expectedAutomatedGate`,
  `PhotosensitivityCertificationTests.multiPassMeasured`,
  `MultiPassFlashHarnessTests`, `RouteCoverageTests`,
  `OrchestratorCertifiedFilterTests`, `GoldenSessionTests`.
- **Golden artifacts:** the per-scene reference sets under
  `docs/VISUAL_REFERENCES/` (79 tracked files), looked up by scene name; and
  the dHash goldens, which are inline `UInt64` constants in the harness
  templates (e.g. `FeedbackPathHarnessTemplate.goldenAccumulatorHash`) under
  `UzumeEngine/Tests/UzumeEngineTests/Presets/` — a directory C moves.
  Note the `target_animated.gif` motion goldens named in
  `PRESET_SESSION_CHECKLIST.md` are **not tracked** (gitignored, present only
  on the machine that rendered them), so C cannot rename what it cannot see.

### 5.2 What it would break

**The cross-repo contract (§4.1) is the hard one.** Renaming the sidecar
directory breaks `generate_presets.py`'s glob immediately and silently — it
prints "no sidecars under …" and returns 1. That means the website side must
change in the **same window**: `SIDECARS`, `OUT_DIR`, the `presets` content
collection name and its Astro schema, `preset_captions.json`, and whatever
`check_web_catalogue.py` asserts. Sidecar *keys* are safe — none say "preset" —
so `FIELDS` needs no change unless C also renames `name`, which it must not.

Then, in rough order of how quietly they fail:

1. **`"preset_fragment"` is user-data compatibility, not a code name.** Every
   third-party scene already sitting in
   `~/Library/Application Support/Uzume/Presets/` that omits
   `fragment_function` binds to that exact string. Renaming it breaks
   already-written scenes on disk. If C renames it, the decoder must accept
   both names forever.
2. **The hot-reload directory is user data too** —
   `~/Library/Application Support/Uzume/Presets` (`VisualizerEngine.swift:922`)
   holds files the user put there. Renaming needs a migration, not a `git mv`.
3. **Persisted `UserDefaults` keys.** `uzume.settings.visuals.showUncertifiedPresets`
   and `uzume.settings.visuals.excludedPresetCategories` are stored on every
   user's machine. There is a precedent to copy: `SettingsMigrator.swift`
   already maps the `phosphene.*` keys to `uzume.*`. Without a matching entry,
   C silently resets everyone's settings. Sweep the keys in tests *and* docs —
   a stale `defaults write` in a doc fails silently.
4. **The os.Logger subsystem `io.uzume.presets`** is published in
   `CONTRIBUTING.md` as a `log stream --predicate` command contributors copy.
   Changing it invalidates a documented command.
5. **The markdown anchor `#17-preset-metadata-format-json-sidecar`**, cited
   from `CLAUDE.md`, `docs/GLOSSARY.md` and `docs/presets/NEW_PRESET_CHECKLIST.md`.
   Renaming SHADER_CRAFT §17's heading breaks all three.
6. **Skill names.** `.claude/skills/preset-session/` and `preset-concept/` are
   invoked by name and their `description:` text is the trigger — renaming the
   directory without the description changes when they fire.

### 5.3 What makes C harder than a find-and-replace

**`Scene` is already taken, and it means something else.** This is the finding
that decides C's shape:

- Types: `SceneUniforms`, `SceneCamera`, `SceneLight` (+ two test suites) —
  the 3D scene bound to every ray-march and mv_warp pass. `SceneUniforms` is
  part of the documented GPU contract (`CLAUDE.md` §Key Types).
- Sidecar keys already in use: `scene_camera`, `scene_lights`, `scene_fog`,
  `scene_fog_near`, `scene_far_plane`, `scene_dolly_speed`.
- The documented mv_warp dispatch order is literally "scene → warp → compose
  → swap".
- 336 existing occurrences of the bare word "scene" in `*.swift`.

So `Preset` → `Scene` is a **collision**, not a rename: after it, `SceneCamera`
would ambiguously read as "the visualizer's camera". C must first decide
whether the 3D meaning is renamed out of the way (e.g. `SceneUniforms` →
`StageUniforms` / `WorldUniforms`, with matching `scene_*` sidecar keys, which
is itself a schema change), or whether the visualizer takes a distinct
identifier. **That decision is upstream of any mechanical sweep.**

Other things a blind replace gets wrong:

- **Case-insensitive replace corrupts third-party text.** `presets-cream-of-the-crop`
  is a real GitHub URL; `milkdrop_filename` values are quoted source titles;
  `docs/CREDITS.md`'s licence posture and takedown path describe Milkdrop
  presets. A global sweep silently rewrites all of it.
- **Name-keyed runtime dispatch on the `name` *value*.**
  `VisualizerEngine+Presets.swift` switches on `case "Gossamer"`,
  `"Nebula"`, `"Skein"`, `"Nimbus"`, `"Lumen Mosaic"` to bind stateful
  runtimes. Those strings are the sidecar `name` — the same value the website
  slugifies. Two consumers, one string, no compiler help on either.
- **`Reset` contains no "preset", but `PresetReset…` does.** Two real type
  names (`FrameBudgetManagerResetOnPresetChangeTests`,
  `TrackChangePresetResetRegressionTests`) mix both words; regex order matters.
- **File-path-derived identity.** The loader auto-discovers scenes by scanning
  the Shaders directory; a `.metal`/`.json` pair is bound by filename stem, and
  `docs/VISUAL_REFERENCES/<name>/` is looked up from the scene name. Renaming a
  directory is three coupled renames.
- **Localization keys are serialized names.** The `settings.visuals.presets.*`
  keys live in `Localizable.strings`; changing them is a rename on both sides
  at once, and `Scripts/check_user_strings.sh` will not catch a mismatch (it
  bans hardcoded literals, it does not verify keys resolve).

### 5.4 Suggested order, if C is scoped

1. Decide the `Scene` collision (§5.3). Nothing else can start first.
2. Land the compatibility shims alone, ahead of any rename: dual-accept
   `preset_fragment`, the `SettingsMigrator` key entries, the hot-reload
   directory migration.
3. Rename code identifiers and types — pure Swift, compiler-checked, no data.
4. Rename directories + `project.pbxproj` + SPM target, in one commit.
5. The sidecar directory move and the website's generator change, in the same
   window, verified by `generate_presets.py --check` before and after.
