# Increment FARADAY.1 — extract the shared spectral solver spine (infrastructure increment)

**Objective.** After this session the pseudo-spectral compute machinery ALFVEN.4 built is a
**shared engine surface** rather than Alfvén-private: the threadgroup FFT, the Hou–Li filter,
the integrating factor, the dealias, and the Swift substep spine live in a paradigm-level
`SpectralSolver` core, with `AlfvenSolver` re-pointed at it and every one of its existing gates
still green. **No Faraday code, no new preset, no new physics.** This is the increment that
stops the second spectral preset from copying the first (FA #73).

Motivating design: `docs/presets/FARADAY_DESIGN.md` §7. Nothing here is Faraday-specific.

## Skills to invoke

- `shader-authoring` — BEFORE touching any `.metal` or GPU-facing Swift.
- `closeout` — at the end (8-part report + verbatim `Scripts/closeout_evidence.sh` block as §2).
- **Do NOT** invoke `preset-session`: no preset is authored or tuned here.

## Read first (in order)

1. `docs/presets/FARADAY_DESIGN.md` §6 and §7 — what Faraday needs from the spine, and
   explicitly what it does **not** need (no CFL reduction, no Poisson, no brackets).
2. `docs/CAPABILITY_REGISTRY/` — the ALFVEN.4b row for "pseudo-spectral PDE solver on a compute
   pipeline". It records why the staged fragment path cannot host one; this increment must keep
   that reasoning true of the extracted core.
3. `UzumeEngine/Sources/Renderer/Geometry/AlfvenSolver.swift` — the header comment is the
   rationale for the whole architecture; read it before moving any of it.
4. `UzumeEngine/Sources/Renderer/Geometry/AlfvenSolver+Ops.swift` — the spine to extract:
   `encode` / `fft` / `kernel` / `gradient` / `brackets` / `accumulate` / `spectral` /
   `finalize` / `copy`.
5. `UzumeEngine/Sources/Renderer/Geometry/AlfvenSolver+Substep.swift` and
   `AlfvenSolverConfiguration.swift`.
6. `UzumeEngine/Sources/Renderer/Shaders/AlfvenSolver.metal` — kernel inventory below.
7. `UzumeEngine/Tests/UzumeEngineTests/Renderer/AlfvenComputeFFTTests.swift` and
   `AlfvenSolverTests.swift` — the gates that must not move.
8. The **`claude/alfven-1c-fft`** branch — it appears to already split the FFT out
   (`FFTSandbox.json` / `FFTSandbox.metal`). **Read it before writing anything.** If it does
   part of this job, continue it rather than duplicating it; say in the closeout which parts you
   adopted.

## What is generic and what is not (the scope boundary)

| Kernel / helper | Verdict |
|---|---|
| `alfven_fft_rows`, `alfven_fft_cols` | **generic** — move, rename |
| `alfven_houli` | **generic** — move, rename |
| `alfven_efactor` | **generic** — move; the per-field factor stays a caller-supplied parameter |
| `alfven_dealias` | **generic** — move, but see the Do-NOT on where it may be applied |
| Ops spine: `encode` / `fft` / `kernel` / `spectral` / `finalize` / `copy` | **generic** — move |
| `alfven_grad_spectrum`, `alfven_brackets`, `alfven_j_spectrum`, `alfven_accumulate` | **Alfvén-specific** — stay |
| `alfven_cfl_reduce`, `alfven_cfl_finish` | **Alfvén-specific** — stay. Faraday's stiffness is fixed; it needs no adaptive dt |
| `alfven_seed_state` | **judgement call** — the re-seed *pattern* is shared, the spectrum shape is per-preset. Parameterise or leave; state which and why |

## Pre-flight invariants (each failure stops the session)

- **Branch from `claude/alfven-2-preset` at its head, NOT from `main`.** `main` does not contain
  `AlfvenSolver` at all — starting there gives you nothing to extract. Verify
  `git log --oneline -1` shows `[ALFVEN.4b] docs: module map, capability registry, plan entry`.
- Gates green at that head before any edit: `swiftlint lint --strict` = 0;
  `xcodebuild -scheme UzumeApp -destination 'platform=macOS' build` = SUCCEEDED;
  `swift test --package-path UzumeEngine --filter Alfven` = pass.
- Record the FFT gate numbers **before** you touch anything, and put them in the closeout beside
  the after numbers: round-trip max relative error and the Parseval ratio. The published values
  are 8.868e-07 and 1.000000.
- `docs/presets/FARADAY_DESIGN.md` and `docs/VISUAL_REFERENCES/faraday/` are present and
  committed. If either is missing, STOP — design is authored in Matt's seat, never mid-session.

## Numbered tasks

1. **Read `claude/alfven-1c-fft` and decide.** Either continue that split or supersede it, and
   record the choice. **Done-when:** one paragraph in the transcript naming what that branch
   already provides and what this increment adds on top.

2. **Create the shared core.** New files under `UzumeEngine/Sources/Renderer/Geometry/` —
   `SpectralSolverCore.swift` (the Ops spine, device/pipeline ownership, texture pair
   management) and `UzumeEngine/Sources/Renderer/Shaders/SpectralOps.metal` (the generic
   kernels, renamed `spectral_fft_rows` / `spectral_fft_cols` / `spectral_houli` /
   `spectral_efactor` / `spectral_dealias`). **The move must be behaviour-preserving — no
   physics changes, no opportunistic tuning.**
   **Done-when:** the new files exist and `AlfvenSolver.metal` no longer defines the moved kernels.

3. **Re-point `AlfvenSolver` at the core** and delete the moved code from it. Alfvén keeps its
   own brackets, gradient spectra, `j_spectrum`, CFL reduction and accumulate.
   **Done-when:** `AlfvenSolver` compiles against the core with no duplicated kernel source, and
   the Alfvén file shrinks by roughly the moved volume — report the line counts.

4. **The gates must not move.** Re-run the FFT round-trip and Parseval gates against the
   extracted kernels; re-run `AlfvenSolverTests` and the dHash goldens.
   **Done-when:** round-trip and Parseval match the pre-flight numbers to the digits recorded,
   `AlfvenSolverTests` is green, and `PresetRegressionTests` dHash is unchanged. **A moved dHash
   is a regression in this change, not a golden to refresh — stop and report.**

5. **Give the core its own gate, independent of Alfvén.** A `SpectralSolverCoreTests` that
   exercises the FFT round-trip and Parseval on the core directly, plus one property Alfvén does
   not test: an **impulse response** — transform a delta, confirm a flat magnitude spectrum.
   Two properties caught a real bug last time (the bit-reversal was wrong while Parseval still
   passed, because Parseval is invariant under a permutation of the outputs); a third makes the
   next silent failure less likely.
   **Done-when:** `SpectralSolverCoreTests` passes and does not import anything Alfvén-specific.

6. **Document the surface for its second consumer.** `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`
   gets the spectral-core row: what it provides, what a consumer must supply, and the two
   things it deliberately does **not** provide (adaptive dt, Poisson). Add the FA #44 `half`
   hazard and the dealias rule where a Faraday session will actually find them.
   **Done-when:** `DocIntegrityTests` passes and a reader can tell from the registry alone what
   FARADAY.2 has to write.

7. **Decisions and plan.** `docs/DECISIONS.md` — the extraction decision (**verify the next free
   D-number at run time**; D-245 was the last one I saw). `docs/ENGINEERING_PLAN.md` — the
   FARADAY.1 row. `docs/ARCHITECTURE.md` §Module Map — the new files.
   **Done-when:** all three carry the change and `DocIntegrityTests` is green.

8. **Stop and report.** Post the before/after gate numbers, the line counts moved, and one
   sentence on whether anything in the core still smells Alfvén-shaped. That sentence is the
   input to FARADAY.2. **Do not begin FARADAY.2.**

## Do NOT

- Do NOT write `Tacoma.metal`, `TacomaSolver`, or any Faraday physics. That is FARADAY.2.
- Do NOT change any physics while moving it. An extraction that also "improves" a kernel is
  untestable — if the gates move you will not know which change did it.
- Do NOT move `alfven_cfl_reduce` / `alfven_cfl_finish` into the core. Faraday's stiffness is
  fixed and known ahead of time; a shared adaptive-dt reduction would be built for one consumer
  and add a per-frame global reduction the other must pay for.
- Do NOT apply the dealias anywhere except the bracket product — that rule is recorded in the
  ALFVEN.4b Module Map notes and it is easy to lose in a move.
- Do NOT name any MSL variable `half` — it is a keyword and it has bitten this codebase three
  times (FA #44). ALFVEN.4 added an assertion that refuses to write the file if the bare word
  survives; keep it and point it at the new file too.
- Do NOT regenerate goldens.
- Do NOT merge `claude/alfven-2-preset` to main as part of this increment unless Matt asks —
  the merge is his call and is a separate decision from the extraction.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
swift test --package-path UzumeEngine --filter AlfvenComputeFFTTests 2>&1
swift test --package-path UzumeEngine --filter AlfvenSolverTests 2>&1
swift test --package-path UzumeEngine --filter SpectralSolverCoreTests 2>&1
swift test --package-path UzumeEngine --filter PresetRegressionTests 2>&1
swift test --package-path UzumeEngine --filter DocIntegrity 2>&1
```

## Commit + closeout

- Small commits, `git commit -F <message-file>` (never `-m` with backticks):
  `[FARADAY.1] Spectral: shared FFT / Hou-Li / integrating-factor kernels`
  `[FARADAY.1] Spectral: SpectralSolverCore — the Swift substep spine`
  `[FARADAY.1] Alfven: re-point at the shared core, drop the duplicated kernels`
  `[FARADAY.1] Tests: SpectralSolverCoreTests — round-trip, Parseval, impulse`
  `[FARADAY.1] Docs: capability registry, module map, D-2xx`
- Local commits on a branch off `claude/alfven-2-preset`. **Push only on Matt's explicit
  "yes, push".**
- Closeout: invoke `closeout`; 8-part report. Increment-specific additions: (i) the before/after
  FFT gate numbers side by side; (ii) which dispatch path each test exercised — "tests pass" is
  not evidence; (iii) what `claude/alfven-1c-fft` contributed; (iv) the task-8 sentence.

## DECISION-NEEDED

**None in this increment** — it is a pure extraction with no product-visible surface, and the
gates decide correctness.

The decision that *is* coming, in FARADAY.2, so it can be thought about meanwhile: **how often
the picture should renew itself.** The pattern anneals into parallel stripes if left alone, so
the preset dissolves to a fresh field when a measured order parameter says it has gone stale.
Tighter settings hold the picture consistently cellular but renew roughly every two seconds,
which may read as restless; looser settings let it drift toward stripes for stretches. That is
a felt judgement on live playback, not a number — and it is Matt's.
