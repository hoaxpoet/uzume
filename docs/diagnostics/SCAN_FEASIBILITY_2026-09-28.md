# SCAN.0 — Playlist screen-reading feasibility (2026-09-28)

**Verdict: PASS.** Reading a Spotify playlist off the screen with Apple Vision, then
resolving each row through `PreviewResolver`, finds every row (coverage **100 %**, no
silent misses), identifies **99.2 %** of the songs and plays the **wrong song 0.0 %** of
the time on Matt's four fixture playlists. Reading takes **209 ms a frame** (median,
Release). Decision record: D-260.

## Setup

- **Build:** `swift build -c release --package-path UzumeEngine --product ScanBench`
  (Release, `-O`), run on the Mac mini (Apple M2 Pro, 16 GB, macOS 26.5.1).
- **Harness:** `UzumeEngine/Sources/ScanBench` —
  `UzumeEngine/.build/release/ScanBench [~/Documents/uzume_scan_fixtures] [--report out.md]`.
  `SCANBENCH_MODE=reader|whole|both` picks the reading mode (default `reader`, the production path).
- **Fixtures:** `~/Documents/uzume_scan_fixtures/playlist 1…4` — full-window Spotify desktop
  captures (default list view, both side panels open, 3–4 overlapping captures each, every
  list ending in the "Recommended" shelf) plus one Exportify CSV per playlist as ground truth.
  Outside the repo; never committed (they show a real account). 40 + 34 + 38 + 32 = **144 rows**.
- **Resolution:** both the scanned rows and the ground truth go through the real
  `PreviewResolver`. iTunes responses are cached in `~/.uzume/scanbench/itunes_cache.json`;
  network misses wait on `ITunesRateLimiter.shared` (20/min).

## Metrics (definitions)

- **Coverage** — ground-truth rows that were read, or reported as a numbered gap. A row that is
  neither is a *silent miss* (a failure).
- **Identification** — rows whose scan resolves to the same iTunes song as the ground truth:
  the same preview, the same catalog title + artist (a single and its album release carry
  different preview URLs), or exactly the playlist's own song (full title ignoring "feat."
  credits, same artist) when the ground-truth lookup picked another version.
- **Wrong song** — rows whose scan resolves to a different song. Worse than a miss.
- **Excluded from both**, reported separately:
  - *ground truth has no preview* (as specified), and
  - *ground truth resolves elsewhere* — the CSV's own title + artist lands on a **different song**
    (e.g. "Not Techno — i_o" → Lady Gaga's "Just Dance"). There is no valid reference to judge
    against. This category was not anticipated by the prompt; it is the same reasoning as the
    no-preview exclusion, and the **strict** figure (judged against the ground-truth lookup
    whatever it returned) is reported alongside so nothing is hidden.

## Result — production path (`reader`: find the list pane once, then read only the pane)

Every capture is the default (non-compact) list view; the compact view is **untested** on real
captures (synthetic coverage only — `PlaylistScanLogicTests`).

| Playlist | Songs (truth / header read) | Name read | Coverage | Identification | Wrong song | Truth w/o preview | Truth resolves elsewhere (scan found the right song) | Strict identification | Frame ms (median / max) |
|---|---|---|---|---|---|---|---|---|---|
| playlist 1 | 40 / 40 | ✓ | 100.0 % (40 read, 0 gap, 0 silent) | 100.0 % (34/34) | 0.0 % (0) | 4 | 2 (1) | 94.4 % (34/36) | 209 / 735 |
| playlist 2 | 34 / 34 | ✓ | 100.0 % (34 read, 0 gap, 0 silent) | 100.0 % (29/29) | 0.0 % (0) | 1 | 4 (0) | 81.8 % (27/33) | 219 / 517 |
| playlist 3 | 38 / 38 | ✓ | 100.0 % (38 read, 0 gap, 0 silent) | 100.0 % (36/36) | 0.0 % (0) | 1 | 1 (0) | 94.6 % (35/37) | 202 / 483 |
| playlist 4 | 32 / 32 | ✓ | 100.0 % (32 read, 0 gap, 0 silent) | 96.2 % (25/26) | 0.0 % (0) | 2 | 4 (1) | 83.3 % (25/30) | 189 / 450 |
| **All** | **144** | 4/4 | **100.0 % (0 silent)** | **99.2 % (124/125)** | **0.0 % (0)** | 8 | 11 (2) | 89.0 % (121/136) | **209 / 735** |

Other reading modes, same resolver: `whole` (whole window every frame) 99.2 % / 0.0 %, 310 ms
median; `both` (whole + pane, merged) 99.2 % / 0.0 %, 500 ms median. The pane read is the
fastest at the same accuracy, and is what the live scan and the screenshot drop use.

### Pass bar

| Bar | Required | Measured |
|---|---|---|
| Coverage | 100 %, every row found or a numbered gap | **100 %**, 0 silent misses, 0 gaps |
| Identification | ≥ 95 % | **99.2 %** (strict 89.0 % — see *resolves elsewhere* below) |
| Wrong song | ≤ 2 % | **0.0 %** (strict: 0 as well — the scan never lands on a different song than the reference except where the reference itself is wrong) |
| Speed | keeps up with a normal scroll | **209 ms** median a frame; the first frame of a scan is ~0.5–0.7 s (it reads the whole window once to find the list) |

**Why 209 ms keeps up.** A capture shows ~12 rows. The scan loses nothing as long as
consecutive reads overlap, i.e. the list moves less than ~12 rows between them: at ~5 reads a
second that is ~60 rows a second — a hard fling, not reading pace. A normal scroll through a
playlist moves roughly 5–15 rows a second. Faster flicks leave gaps, which the panel reports by
number ("Missed 14–16. Scroll back up a little."). The live stream asks for 4 frames a second
and the reader sets the real pace (frames arriving mid-read wait or drop).

### Failures, row by row (production path)

| Playlist | # | Ground truth | Scanned (as displayed) | Outcome | Detail |
|---|---|---|---|---|---|
| 4 | 27 | Spitting Off the Edge of the World — Yeah Yeah Yeahs | "Spitting Offthe Edg…" — Yeah Yeah Yeahs, Pe… | not identified | Vision dropped a space in the pane read ("Offthe"); the whole-window read gets it right. |
| 1 | 17 | Three Sisters — Beats Antique | Three Sisters — Beats Antique, Tatyana… | truth resolves elsewhere | truth → "Beauty Beats"; **scan → "Three Sisters (feat. Tatyana Kalmykova)" (right song)** |
| 1 | 22 | III. Derivative — Jlin | "IIl. Derivative" — Jlin, Third Coast Percus… | truth resolves elsewhere | truth → "Perspective: III. Derivative" (other artist credit); scan → no match |
| 2 | 1 | Not Techno — i_o | Not Techno — io | truth resolves elsewhere | truth → "Just Dance" (Lady Gaga); scan → no match |
| 2 | 7 | Praise — ZHU | Praise — ZHU, BANKS, bludn… | truth resolves elsewhere | truth → "Praise" (Julie True); scan → no match (not in the catalog) |
| 2 | 18 | Ride — joe unknown | Ride — joe unknown | truth resolves elsewhere | truth → "Unknown Legend" (Neil Young); scan → no match |
| 2 | 21 | Don't — Honeyglaze | Don't — Honeyglaze | truth resolves elsewhere | truth → "Pretty Girls"; scan → no match (not in the catalog) |
| 3 | 35 | A&W — Lana Del Rey | A&W — "ELana Del Rey" | truth resolves elsewhere | truth → "White Mustang"; scan → no match (not in the catalog) |
| 4 | 2 | One For Your Workout — Get Well Soon | One For Your Worko… — Get Well Soon | truth resolves elsewhere | truth → "The Method" (Lecrae); scan → no match |
| 4 | 8 | You'll Never Leave Harlan Alive — Ruby Friedman Orchestra | You'll Never Leave… — Ruby Friedman Orches… | truth resolves elsewhere | truth → Patty Loveless' recording; scan → no match (this recording not in the catalog) |
| 4 | 17 | It´s Up There — The Field | It's Up There — The Field | truth resolves elsewhere | truth → "In The Mood For Love" (the acute accent breaks the lookup); **scan → the right song** |
| 4 | 19 | Thinking Of You — Serge Devant | Thinking Of You — Serge Devant, Damian… | truth resolves elsewhere | truth → a 7:57 mix; scan → no match (only 7–9 min mixes in the catalog; this one is 4:04) |

Ground truth with no preview at all (excluded as specified): 8 rows (4 / 1 / 1 / 2).

## What went wrong on the way, in terms Matt can see

The gate was not passed first time. Numbers per step (all 144 rows, Release):

| Step | Identification | Wrong song | What changed |
|---|---|---|---|
| Parser iteration 1 + the existing first-hit lookup | 91.9 % | **7.4 %** | Reading was already complete (100 % coverage). But **1 in 5 songs with a cut-off title played the wrong song**: "Cheap And Cheerfu…" → the original instead of the Sebastian remix; "Spitting Off the…" → Usher's "Yeah!". The first catalog hit for a shortened title is often another song. |
| + verified lookup for screen-read rows | 92.0 % | 1.6 % | Screen-read rows now ask the catalog for 25 candidates and accept only one whose title matches what was on screen (a prefix when cut off), whose artist matches, and whose length matches the duration in the row. No verified match → the row is left out, never guessed. |
| Parser iteration 2 (read the list pane only) | 91.2 % | 2.4 % | Reading only the list pane recovered names the whole-window read dropped ("i_o", "SOFI TUKKER") but exposed the next problem: Spotify's music-video badge fuses onto the artist ("DSZA", "L] Big Wild", "EOJENNIE"), and verification rightly refused those artists. |
| + badge-tolerant artist check, title-only retry | **99.2 %** | **0.0 %** | Up to 3 leading badge characters are ignored when comparing artists; a search spoiled by a fused badge retries once with the title alone (still verified). |

**Parser iterations used: 2 of 2.** Iteration 1: text lines grouped by text height (normal
rows were being mistaken for compact view), and a hovered row's duration read through the "⋯"
button. Iteration 2: read the list pane rather than the whole window; playlist name taken from
the lines between the "Playlist" label and the count line, left-aligned with it (cover-art text
and a shrunken title height had broken it). The lookup changes are to *resolution*, applied only
to screen-read rows (`TrackIdentity.screenReading`); every other track sends the exact request it
sent before (`PreviewResolverScreenReadTests.streamingUnchanged`).

## Truncation — does it justify the "widen the window" tip?

**No.** 26 of the 144 rows had a cut-off title (heavy truncation with both side panels open);
25 were identified. The one miss compounds a misread ("Offthe"). With the verified lookup,
truncation stopped causing wrong songs, so the conditional tip in the UX contract is left out.

## A finding about the existing path (not SCAN's to fix)

The **ground-truth lookup is exactly what the paste-a-link Spotify connector and the Apple Music
connector do today**: first iTunes hit for "artist title". On these four playlists it lands on a
**different song for 11 of 136 rows (8 %)** — Lady Gaga for "Not Techno", Neil Young for
"Ride", a piano cover or another track for songs the catalog lacks. Those sessions plan visuals
for music that isn't playing. Filed as BUG-152 (`KNOWN_ISSUES.md`); the verified lookup here is
the likely fix, but changing the streaming path needs its own before/after (the prompt's rule:
never weaken or change `PreviewResolver` matching globally inside SCAN).

## Untested (recorded in KNOWN_ISSUES)

- Compact list view on real captures (synthetic fixtures only).
- A 100+ song playlist.
- A non-English Spotify interface ("N songs" is read in English only; without it the list's end
  — the "Recommended" shelf — sets the count).
- The Spotify web player, very small windows.
