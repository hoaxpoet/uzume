#!/usr/bin/env python3
"""cut_promo.py — PROMO.1: cut a square promo video from REC.2 pinned-scene takes, frame-exact on track time.

    python3 tools/promo/cut_promo.py --edit tools/promo/edit.json
    python3 tools/promo/cut_promo.py --self-test

Frame rule (the whole method): output frame k shows track time t = k / fps. It comes from the segment whose
[from, to) contains it, each edge snapped to its nearest output frame, using that take's frame whose map
`track_time_s` is nearest t + the segment's `source_offset_s` (default 0: the scene as it rendered at that exact
moment; a whole number of bars moves a beat-locked take to another stretch of the same song and keeps it on the
beat). If no take frame lies within 0.75 output frame (the takes start ~0.5 s into the song), the frame is black;
a single 60 fps capture drop leaves the nearest frame at most half an output frame away, so drops never go black.
That one rule does the 60 -> 30 decimation, absorbs capture drops, and puts every cut on the frame nearest its
downbeat. Clips are never concatenated by duration: container timestamps drift (REC.1).

Framing: a full-height square of each take, centred plus `crop_offset_px`; `crop_width_px` wider than the height
zooms out (the slice is scaled to the square's width and padded top and bottom with black), for scenes on a black
ground whose subject outgrows the square.

Stages: (1) select frames -> lossless `clean.mkv` (crop + scale, no tag, no fades) -> contact sheet + cover
stills; (2) tag PNG (tools/promo/render_text.swift: this ffmpeg has no drawtext) + fades -> H.264 at each CRF
candidate, the one nearest the target bitrate kept; (3) song 0 -> end at 48 kHz, one gain step only if the
true peak exceeds the ceiling; (4) mux. Standard library + ffmpeg/ffprobe/swift subprocesses only.
"""
import argparse, csv, json, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))


# MARK: - Frame selection

def nearest(times, t):
    """Index of the map time nearest t (times ascending). Ties go to the earlier frame."""
    lo, hi = 0, len(times)
    while lo < hi:
        mid = (lo + hi) // 2
        if times[mid] < t:
            lo = mid + 1
        else:
            hi = mid
    cands = [i for i in (lo - 1, lo) if 0 <= i < len(times)]
    return min(cands, key=lambda i: (abs(times[i] - t), i))


def select(k, fps, bounds, maps, offsets=None):
    """(segment index, take frame index or None for black) for output frame k.
    bounds: segment edges [b0, b1, ..., bn]; maps: per-segment ascending track times;
    offsets: per-segment source time offsets in seconds (default all 0)."""
    # A segment starts on the output frame nearest its cut, so every cut lands within half an output frame.
    seg = max(i for i in range(len(bounds) - 1) if round(bounds[i] * fps) <= k)
    t = k / fps + (offsets[seg] if offsets else 0.0)
    i = nearest(maps[seg], t)
    return seg, (i if abs(maps[seg][i] - t) <= 0.75 / fps else None)


def self_test():
    fps = 30
    # Take A: 60 fps from 0.5 s with the frame at 0.5 + 2/60 dropped. Take B: 60 fps from 0.0.
    a = [0.5 + j / 60 for j in range(60) if j != 2]
    b = [j / 60 for j in range(300)]
    cut = 1.01                               # between output frames 30 (1.000) and 31 (1.0333); 30 is nearer
    bounds, maps = [0.0, cut, 3.0], [a, b]
    for k in range(15):                      # before take A begins: black
        assert select(k, fps, bounds, maps) == (0, None), k
    assert select(15, fps, bounds, maps) == (0, 0)           # t = 0.5 -> A's first frame
    # t = 0.5333 falls on the dropped frame: the neighbours tie at 1/60 and the earlier one (0.5167) wins.
    assert select(16, fps, bounds, maps) == (0, 1)
    assert select(17, fps, bounds, maps) == (0, 3)           # t = 0.5667 = j 4, index 3 after the drop
    assert select(29, fps, bounds, maps) == (0, 27)          # 0.9667 = j 28 -> index 27, still take A
    assert select(30, fps, bounds, maps) == (1, 60)          # 1.000 is the frame nearest the cut -> take B
    assert select(31, fps, bounds, maps) == (1, 62)          # 1.0333 -> take B, frame 62
    # A source offset of 1.5 s reads take B 1.5 s later: 1.0333 + 1.5 = 2.5333 -> frame 152.
    assert select(31, fps, bounds, maps, [0.0, 1.5]) == (1, 152)
    assert select(15, fps, bounds, maps, [0.0, 1.5]) == (0, 0)   # segment A untouched
    print("self-test: ok")


# MARK: - Helpers

def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def expand(p):
    return os.path.expanduser(p)


def probe_size(path):
    out = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
               "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    w, h = out.split(",")
    return int(w), int(h)


def render_text(spec, out_png, work):
    spec_path = os.path.join(work, os.path.basename(out_png) + ".json")
    with open(spec_path, "w") as f:
        json.dump(spec, f)
    run(["swift", os.path.join(HERE, "render_text.swift"), spec_path, out_png])


def true_peak(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-map", "a:0", "-af",
                          "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    m = re.findall(r"True peak:\s*\n\s*Peak:\s*(-?[\d.]+|-inf) dBFS", err)
    return float(m[-1])


# MARK: - Stages

def build_clean(e, work):
    """Select every output frame, crop the square, scale; write lossless clean.mkv. Returns per-frame log."""
    fps, size, n = e["fps"], e["size"], round(e["end"] * e["fps"])
    segs = e["segments"]
    bounds = [s["from"] for s in segs] + [e["end"]]
    maps, rows = [], []
    for s in segs:
        with open(expand(s["map"])) as f:
            r = list(csv.DictReader(f))
        rows.append(r)
        maps.append([float(x["track_time_s"]) for x in r])
    offsets = [float(s.get("source_offset_s", 0.0)) for s in segs]
    plan = [select(k, fps, bounds, maps, offsets) for k in range(n)]
    fb = size * size * 3 // 2
    black = bytes([16]) * (size * size) + bytes([128]) * (size * size // 2)
    clean = os.path.join(work, "clean.mkv")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "yuv420p",
                            "-s", f"{size}x{size}", "-r", str(fps), "-i", "-", "-c:v", "ffv1", clean],
                           stdin=subprocess.PIPE)
    log, motion = [], [0.0] * n
    for seg, s in enumerate(segs):
        path = expand(s["take"])
        w, h = probe_size(path)
        cw = min(w, max(h, int(s.get("crop_width_px", h))))
        x = max(0, min(w - cw, (w - cw) // 2 + int(s.get("crop_offset_px", 0))))
        dec = subprocess.Popen(["ffmpeg", "-v", "fatal", "-i", path, "-vf",
                                f"crop={cw}:{h}:{x}:0,scale={size}:-2:flags=lanczos,"
                                f"pad={size}:{size}:(ow-iw)/2:(oh-ih)/2:black",
                                "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"], stdout=subprocess.PIPE)
        cur, frame, prev = -1, None, None
        for k in (k for k in range(n) if plan[k][0] == seg):
            src = plan[k][1]
            if src is None:
                out = black
            else:
                assert src >= cur, "take frames must move forward"
                while cur < src:
                    frame = dec.stdout.read(fb)
                    cur += 1
                    assert len(frame) == fb, f"{path}: short read at frame {cur}"
                out = frame
                if prev is not None:   # motion: mean |dY| on a 1-in-97 luma sample
                    ys, yp = out[:size * size:97], prev[:size * size:97]
                    motion[k] = sum(abs(p - q) for p, q in zip(ys, yp)) / len(ys)
                prev = out
            enc.stdin.write(out)
            r = rows[seg][src] if src is not None else None
            log.append(dict(k=k, t=k / fps, seg=seg, src=src, track=maps[seg][src] if src is not None else None,
                            downbeat=r["is_downbeat"] if r else "", beat=r["beat_in_bar"] if r else ""))
        dec.kill()
        dec.wait()
    enc.stdin.close()
    assert enc.wait() == 0
    return clean, log, motion


def contact_sheet(e, clean, log, work, out_png):
    """First / middle / last output frame of each segment, 3 across x 5 down, labelled."""
    tile, cols, font = 360, 3, expand(e["tag"]["font"])
    picks = []
    for seg in range(len(e["segments"])):
        ks = [x["k"] for x in log if x["seg"] == seg]
        picks.append([ks[0], ks[len(ks) // 2], ks[-1]])
    flat = [k for row in picks for k in row]
    sel = "+".join(f"eq(n\\,{k})" for k in flat)
    rows_n = len(picks)
    labels = os.path.join(work, "sheet_labels.png")
    lines = []
    for r, row in enumerate(picks):
        for c, k in enumerate(row):
            lines.append({"text": f"{e['segments'][r]['scene']}  {k / e['fps']:.3f} s  (frame {k})", "size": 22,
                          "center_x": c * tile + tile / 2, "center_y": r * tile + tile - 18})
    render_text({"width": cols * tile, "height": rows_n * tile, "font": font, "weight": 500, "alpha": 1.0,
                 "shadow_px": 3, "lines": lines}, labels, work)
    run(["ffmpeg", "-v", "error", "-y", "-i", clean, "-i", labels, "-filter_complex",
         f"[0:v]select='{sel}',scale={tile}:{tile},tile={cols}x{rows_n}[g];[g][1:v]overlay",
         "-frames:v", "1", "-fps_mode", "passthrough", out_png])


def covers(e, clean, log, motion):
    """1080x1080 stills (no tag) at each named scene's peak of frame-to-frame motion."""
    picked = []
    for i, c in enumerate(e["covers"], 1):
        seg = next(j for j, s in enumerate(e["segments"]) if s["scene"] == c["scene"])
        ks = [x["k"] for x in log if x["seg"] == seg and x["src"] is not None][1:]
        k = max(ks, key=lambda k: motion[k])
        out = expand(c["out"])
        run(["ffmpeg", "-v", "error", "-y", "-i", clean, "-vf", f"select=eq(n\\,{k})", "-frames:v", "1",
             "-fps_mode", "passthrough", out])
        picked.append((c["scene"], k, round(motion[k], 2), out))
    return picked


def encode_video(e, clean, tag_png, work):
    """Tag + fades over clean.mkv, H.264 at each CRF candidate; keep the one nearest the target bitrate."""
    fps, n, t = e["fps"], round(e["end"] * e["fps"]), e["tag"]
    fade_n = round(e["video_fade_out_s"] * fps)
    vf = (f"[1:v]format=rgba,fade=t=in:st={t['in']}:d={t['fade_in_s']}:alpha=1[tag];"
          f"[0:v][tag]overlay=shortest=1:format=auto,"
          f"fade=t=out:start_frame={n - 1 - fade_n}:nb_frames={fade_n},format=yuv420p[v]")
    results = []
    for crf in e["encode"]["crf_candidates"]:
        out = os.path.join(work, f"video_crf{crf}.mp4")
        run(["ffmpeg", "-v", "error", "-y", "-i", clean, "-loop", "1", "-framerate", str(fps), "-i", tag_png,
             "-filter_complex", vf, "-map", "[v]", "-frames:v", str(n), "-r", str(fps), "-fps_mode", "cfr",
             "-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-crf", str(crf), "-pix_fmt", "yuv420p",
             "-an", out])
        br = float(run(["ffprobe", "-v", "error", "-show_entries", "format=bit_rate", "-of", "csv=p=0", out],
                       capture_output=True, text=True).stdout.strip())
        results.append((abs(br - e["encode"]["target_mbps"] * 1e6), crf, br, out))
    results.sort()
    return results


def encode_audio(e, work):
    """Song 0 -> end, 48 kHz, fade-out; one clean gain step only if the true peak is over the ceiling."""
    end, fo = e["end"], e["audio_fade_out_s"]
    ceiling = e["encode"]["true_peak_max_dbtp"]

    def enc(gain_db):
        out = os.path.join(work, f"audio_{gain_db:+.2f}dB.m4a")
        af = (f"volume={gain_db}dB," if gain_db else "") + f"afade=t=out:st={end - fo:.3f}:d={fo},aresample=48000"
        run(["ffmpeg", "-v", "error", "-y", "-t", str(end), "-i", expand(e["audio"]), "-vn", "-af", af,  # mp3 carries cover art
             "-c:a", "aac", "-profile:a", "aac_low", "-b:a", f"{e['encode']['audio_kbps']}k", "-ar", "48000",
             "-ac", "2", out])
        return out, true_peak(out)

    out, before = enc(0.0)
    after, gain = before, 0.0
    if before > ceiling:
        gain = round(ceiling - before - e["encode"].get("gain_margin_db", 0.0), 2)
        out, after = enc(gain)
    return out, before, gain, after


# MARK: - Main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--edit")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        self_test()
        return
    with open(a.edit) as f:
        e = json.load(f)
    out = expand(e["output"])
    work = expand(e["work_dir"])
    os.makedirs(work, exist_ok=True)
    clean, log, motion = build_clean(e, work)
    contact_sheet(e, clean, log, work, expand(e["contact_sheet"]))
    cover_picks = covers(e, clean, log, motion)
    tag = e["tag"]
    tag_png = os.path.join(work, "tag.png")
    render_text({"width": e["size"], "height": e["size"], "font": expand(tag["font"]), "weight": tag["weight"],
                 "alpha": tag["alpha"], "shadow_px": tag["shadow_px"], "tracking_em": tag["tracking_em"],
                 "lines": tag["lines"]}, tag_png, work)
    videos = encode_video(e, clean, tag_png, work)
    _, crf, br, video = videos[0]
    audio, tp_before, gain, tp_after = encode_audio(e, work)
    run(["ffmpeg", "-v", "error", "-y", "-i", video, "-i", audio, "-map", "0:v", "-map", "1:a", "-c", "copy",
         "-movflags", "+faststart", out])
    shutil.copy(tag_png, os.path.join(os.path.dirname(out), "end_tag.png"))
    # Report: each segment's first frame vs its cut; CRF choice; audio peak.
    fps = e["fps"]
    report = {"output": out, "frames": len(log), "black_lead_in_frames": sum(1 for x in log if x["src"] is None),
              "crf": crf, "video_bitrate": round(br), "crf_candidates": [(c, round(b)) for _, c, b, _ in videos],
              "true_peak_before_dbtp": tp_before, "gain_db": gain, "true_peak_after_dbtp": tp_after,
              "segments": [], "covers": cover_picks}
    for seg, s in enumerate(e["segments"]):
        ks = [x for x in log if x["seg"] == seg]
        first_real = next(x for x in ks if x["src"] is not None)
        report["segments"].append(dict(scene=s["scene"], cut=s["from"], out_frames=(ks[0]["k"], ks[-1]["k"]),
                                       first_frame_t=round(ks[0]["t"], 4),
                                       first_frame_err_ms=round((ks[0]["t"] - s["from"]) * 1000, 2),
                                       first_real=(first_real["k"], first_real["src"], first_real["track"])))
    report["within_half_frame"] = all(abs(x["first_frame_err_ms"]) <= 500 / fps + 1e-6 for x in report["segments"])
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    sys.exit(main())
