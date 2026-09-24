# The beta test playlist

**Approved by Matt 2026-09-24** (BETA.0 task 5; `BETA_SCENE_SLATE_2026-09-24.md` §00). This is the fixed
review material for every Phase BETA scene: each look spike, M7 and rewatch check runs against these ten
songs. Local files are the review path — whole-track analysis, stems on time.

## Opening it

The playlist is [`tools/data/beta_test_playlist.m3u`](../../tools/data/beta_test_playlist.m3u). Every entry
is an absolute path on `/Volumes/Extreme SSD`, so the drive must be mounted.

- **Local files → Playlist** (`.m3u or .m3u8`) on the local-source screen, or
- **drag the `.m3u` onto the Uzume window**.

Either way it is then kept in **File → Open Recent**. (File → Open Local File… accepts audio files only, not
playlists.)

**Streaming pass.** Matt keeps a Spotify mirror of the same ten songs, by hand. Each scene gets one pass on
it before it certifies (slate §00).

## What each track tests

| # | Track | Genre | What it tests |
|---|---|---|---|
| 1 | LCD Soundsystem, "Dance Yrself Clean" | electronic | About three minutes of near-hush, then the drop. Goldengrove bloom timing, Supernova build and detonation, Fireflies at near-silence, four-on-the-floor. |
| 2 | OutKast, "B.O.B." | hip-hop | Very fast and dense. Kagura's fast-tempo case; stress for stem-driven scenes. |
| 3 | Stevie Wonder, "Superstition" | soul/funk | Mid-tempo groove with horns. "Does it dance?" (Kagura, Pendulums). |
| 4 | Nirvana, "Smells Like Teen Spirit" | rock | Quiet-verse/loud-chorus switches. Section boundaries (Sumi's comb stroke, Physarum rule changes), calming at verses. |
| 5 | The Beatles, "Penny Lane" | pop | Audible key changes. Drumhead, Harmonograph, harmony-driven colour. |
| 6 | Dave Brubeck Quartet, "Take Five" | jazz | 5/4 with swing. The *"everything seems like 4/4"* note (FFO); meter-aware Pendulums. |
| 7 | Radiohead, "Pyramid Song" | art rock | The "where's the beat?" track (the census's disagreement example). Fireflies stay free; Kagura falls back to its sway. |
| 8 | Massive Attack, "Teardrop" | trip-hop | Slow, heartbeat kick, deep bass, lead vocal. The slow-tempo case; Lantern, Pool. |
| 9 | Beethoven, "Moonlight" I (Barenboim) | classical | Solo piano, no drums, slow harmonic drift. Restraint; harmony-driven scenes without a beat. |
| 10 | David Bowie, "Warszawa" | ambient | Nearly beatless. The anchor to the 2026-09-04 roster review; near-silence behaviour. |

## Measured tempo and beat regularity

From the CENSUS full run, `/Volumes/Extreme SSD/phosphene_census/full_results.csv` (2026-07-10), which
analysed a **30 s window** of each track — not the whole track. `grid BPM` is the cached beat grid's tempo;
`beat_irregular` is the D-154 flag (`folded_disagreement` between grid and drums-stem tempo). A flag of —
means the census could not assess it (no drums-stem tempo).

| # | Track | grid BPM | drums BPM | folded disagreement | beat_irregular |
|---|---|---|---|---|---|
| 1 | Dance Yrself Clean | 97.63 | 98.09 | 0.005 | false |
| 2 | B.O.B. | 153.95 | 154.21 | 0.002 | false |
| 3 | Superstition | 98.53 | 138.25 | 0.403 | **true** |
| 4 | Smells Like Teen Spirit | 116.15 | 118.01 | 0.016 | false |
| 5 | Penny Lane | 112.09 | 146.02 | 0.303 | **true** |
| 6 | Take Five | 169.24 | 170.73 | 0.009 | false |
| 7 | Pyramid Song | 66.12 | 72.64 | 0.099 | false |
| 8 | Teardrop | 76.98 | 88.24 | 0.146 | **true** |
| 9 | Moonlight I | 84.95 | 76.14 | 0.116 | **true** |
| 10 | Warszawa | 53.96 | — | — | — |

Read these as the census's 30 s view, not whole-track ground truth. Four tracks carry the D-154 flag, so
scenes that exclude beat-irregular tracks from beat-locked motion will treat them that way.

## Verification (BETA.0, 2026-09-24)

`test -r` passes on all ten paths, and `M3UParser.parse(at:)` resolves the file to **10/10** entries, 0
skipped.
