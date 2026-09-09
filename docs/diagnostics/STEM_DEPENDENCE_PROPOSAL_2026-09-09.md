# Proposal — telling the scorer which stems a preset *needs*

**Status:** **A was chosen, implemented, measured, and REVERTED the same day.** The mechanism works; the
signal it would weight does not exist. See §Outcome. Nothing is in the tree.
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


---

## Outcome (2026-09-09) — A implemented, measured, reverted

Matt chose **A**. It was built (`stem_dependence` on `PresetDescriptor`, weighting in
`stemAffinitySubScore`, adopted on Gossamer as `{"vocals": 1.0, "other": 0.4}`) and measured with
`PlanRankingDumpTests` against a vocal track and an instrumental, exactly as this document required.

**It made selection worse.**

| | without | with `{vocals 1.0, other 0.4}` |
|---|---:|---:|
| Seven Nation Army (vocal) — Gossamer affinity | **0.88** | 0.76 |
| Pacific Theme (instrumental) — Gossamer affinity | 0.03 | 0.00 |
| **discrimination gap (total score)** | **0.207** | **0.176** |

**Why — the primitive measures variability, not prominence.** `stemEnergyDeviation` is deviation about
a stem's own running mean, so a *steady, prominent* vocal barely deviates. On Seven Nation Army the
vocal has the **lowest** deviation of the four stems (0.705 against bass 0.973) despite being the most
prominent thing in the song. Weighting toward vocals therefore penalises exactly the material it was
meant to select. And the unweighted mean is a *better* discriminator, because on an instrumental all
four deviations collapse together (Pacific Theme: 0.058 / 0.059 / 0.000 / 0.000) — averaging four
signals beats trusting one.

**The premise of this proposal was also wrong.** It said Gossamer "has no selectivity today" because
declaring four stems is arithmetically identical to declaring none (D-245). Arithmetically true, but
it does not follow: the mean deviation *is* selective (0.88 vocal vs 0.03 instrumental).

**Two other candidate signals were measured and both fail.**

- **Energy share** — Seven Nation Army's vocal is 22.8 % of stem energy, Pacific Theme's is 18.0 %.
  Five points apart, because separation always emits four stems with energy in them.
- **Pitch-confidence duty cycle** (newly meaningful after BUG-124) — *inverted*: **Weeping Wall, a
  purely instrumental piece, scores 94.8 %**, above Seven Nation Army's 79.9 % and Combat Baby's
  85.6 %. On that instrumental the separated "vocals" stem still carries median energy **0.301** and
  reads as pitched at **132 Hz** — against Seven Nation Army's 0.339 and 130 Hz. Statistically the
  same. The stem is full of periodic bleed and nothing downstream distinguishes it from a voice.

**Conclusion: the blocker is not plumbing, it is that no primitive identifies vocal presence.** Any
vocal-based selection needs one built first — a vocal-presence detector, not a re-weighting of what
exists. Until then, selection by stem is guesswork.

**Consequence for BUG-124, recorded there too:** the YIN fix recovers *periodicity*, which is not the
same as *vocals*. Gossamer's emission gate now opens on 94.8 % of an instrumental's frames. The preset
reading well on Combat Baby does not establish that it is responding to the voice.
