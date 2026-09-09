# Proposal — telling the scorer which stems a preset *needs*

**Status:** proposal, for Matt's decision. Nothing implemented.
**Raised by:** Matt, 2026-09-09 — *"this could be an issue of limiting selection of the preset to only songs with prominent vocals."*

## The ask, and why the obvious change is wrong

Gossamer's signature visual is keyed to vocals. It should therefore be *chosen* more often for
vocal-forward tracks. The apparently one-line version — declare only `vocals` in
`stem_affinity` — was rejected on inspection.

`stem_affinity`'s meaning is fixed by the schema (`PresetDescriptor.swift:361–365`):

> Maps stem names to visual parameter descriptors. **Presence of a key signals that this preset
> responds to that stem.** The string value is a hint for the Orchestrator visual-wiring layer;
> **the scorer only checks key membership.**

Gossamer genuinely responds to all four stems — drums drive strand tremor, bass drives tautness,
`other` drives emission rate, vocals drive hue and the emission gate. Deleting three keys would make
the sidecar **false** in order to move a score, and would delete the preset's own routing
documentation as a side effect.

## The actual gap

`stemAffinitySubScore` reads key membership and averages the track's deviation over the declared
stems. So **"responds to" and "depends on" are the same thing to the scorer**, and there is no way to
express the difference. Checked against the full sidecar schema (`SHADER_CRAFT.md §17`): no field
carries stem dependence.

A second-order effect makes this sharper than it was last week. Under **D-245** (2026-09-09) a preset
declaring *no* affinity now scores the track's mean deviation across all four stems. Declaring all
four is therefore **arithmetically identical to declaring none** — Gossamer currently gets no
selectivity at all, despite naming four stems.

## Options

### A. `stem_dependence` — a weight map (recommended for evaluation)

```json
"stem_affinity":   { "drums": "...", "bass": "...", "other": "...", "vocals": "..." },
"stem_dependence": { "vocals": 1.0, "other": 0.4 }
```

`stemAffinitySubScore` weights the per-stem deviation by these values instead of averaging equally;
absent key ⇒ current behaviour. `stem_affinity` keeps its truthful meaning and stays the routing
record; dependence becomes a separate, explicit statement.

- **For:** expressive (a preset can need vocals *strongly* and `other` *somewhat*); backward
  compatible; leaves `stem_affinity` honest.
- **Against:** a new number per preset with no calibration; risks becoming a knob nobody can justify.

### B. `requires_stems: ["vocals"]` — a hard-ish filter

Scores the named stems only, ignoring the rest.

- **For:** the smallest change that answers the ask; unambiguous.
- **Against:** binary. A preset that mostly wants vocals but tolerates instrumentals has no way to say
  so, and on an instrumental playlist a `requires_stems` preset could vanish entirely.

### C. Do nothing

Gossamer stays unselective. Vocal-forward tracks reach it only by chance.

- **For:** no schema growth; the sidecar-key gate demands an adopter and a stated reason for any new
  key, and one preset is a thin adopter set.
- **Against:** leaves a real product need unmet, and the need generalises — any preset with a
  stem-specific signature has it.

## What this touches

Both A and B change **which presets open which tracks**, on top of D-245, which changed the same path
yesterday. Recommend measuring before and after with `PlanRankingDumpTests`
(`PLAN_DUMP_META=<StemCache …/metadata.json>`) on at least one vocal-forward and one instrumental
track, so the effect is observed rather than predicted.

Gates: `PresetSidecarKeyGateTests` requires every decoded key to have an adopter or a stated reason;
`RouteCoverageTests` is unaffected (it reads `audio_routes`, not affinity).

## Recommendation

**A, scoped to an evaluation** — implement `stem_dependence`, adopt it on Gossamer alone, and measure
the ranking shift on both kinds of material before deciding whether it stays. If the shift does not
match what Matt wants to see, delete the key rather than tune it. **Not started; Matt's call.**
