# tools/promo — promo video cutter (PROMO.1)

Cuts a square promo video from REC.2 pinned-scene takes (`UZUME_PIN_SCENE` + `UZUME_RECORD_VIDEO=capture`,
trimmed by REC.2's alignment step into `take_<n>_<scene>.mp4` + `_map.csv`).

```bash
python3 tools/promo/cut_promo.py --self-test
python3 tools/promo/cut_promo.py --edit tools/promo/edit.json
```

- **`edit.json`** holds everything that varies: take and map paths, segment start times (with the offline and
  engine sources recorded), end time, per-take crop offset, end-tag text/font/timing, cover picks and encode
  targets. A reshot take or a moved cut is an edit there, then one command.
- **Frame rule.** Output frame k shows track time k / fps, taken from the segment containing it (edges snapped to
  the nearest output frame) using the take frame whose map time is nearest. Nothing is concatenated by duration.
  Frames the takes don't cover (the first ~0.5 s of the song) are black.
- **Crop.** Each take's full-height square (1440×1440 from 2560×1440), centred plus `crop_offset_px` (source
  pixels), scaled down to `size`. Never upscaled.
- **Text.** Homebrew's ffmpeg has no `drawtext` (built without freetype), so `render_text.swift` draws the end
  tag and contact-sheet labels with macOS CoreText and ffmpeg overlays the PNG.
- **Outputs** beside the video: `contact_sheet.png` (first/middle/last frame per segment), `cover_1..3.png`
  (1080² stills at each named scene's peak of motion, no tag), `end_tag.png`; intermediates in `work_dir`.
- **Audio.** The song from 0 to `end`, resampled to 48 kHz, faded out; one gain step only if the true peak is
  above `true_peak_max_dbtp`.
