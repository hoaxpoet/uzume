#!/bin/zsh
# render_soak.sh — VQ.0 render soak: a named Release build, every certified scene, measured per minute.
#
# Usage: Scripts/render_soak.sh <app path> <label> [options]
#   --track <file|folder>  what plays (default: the memrepro track in /Users/Shared — TCC blocks external volumes)
#   --fresh-prep           move each track's stem cache aside first (restored on every exit), so stem
#                          preparation runs during the soak (BUG-176's failure was preparation, not rendering)
#   --override <WxH>       force the drawable (e.g. 3840x2160); omit to use the real display (the TV soak)
#   --toggle <seconds>     toggle the override ↔ 1920x1080 at this period (needs --override)
#   --minutes <n>          length (default 60)
#   --floor                the 8 GB-Mac floor simulation: that Mac's budget ceiling, plus memory-pressure events
#                          injected in the app — warning at 40 % of the run, critical at 70 %, normal at 85 %
#   --cycle <seconds>      seconds per scene (default 20: one roster cycle ≈ 9 min)
#
# Writes <label>/ in the current directory: footprint.csv (this script, every 2 s), render_soak_minutes.csv
# and render_soak_summary.txt (the app). Kills the app at 4 GB phys_footprint (so does the app itself).
# Prints the session folder. Recipes: docs/RUNBOOK.md §VQ.0 render soak.

set -u

if (( $# < 2 )); then
    print -u2 "usage: $0 <app path> <label> [--track p] [--fresh-prep] [--override WxH] [--toggle s] [--minutes n] [--floor] [--cycle s]"
    exit 64
fi
app_path=$1; label=$2; shift 2
track="/Users/Shared/memrepro/01 Dance Yrself Clean.mp3"
fresh_prep=0; override=""; toggle=""; minutes=60; floor=0; cycle=20
while (( $# > 0 )); do
    case $1 in
        --track) track=$2; shift 2 ;;
        --fresh-prep) fresh_prep=1; shift ;;
        --override) override=$2; shift 2 ;;
        --toggle) toggle=$2; shift 2 ;;
        --minutes) minutes=$2; shift 2 ;;
        --floor) floor=1; shift ;;
        --cycle) cycle=$2; shift 2 ;;
        *) print -u2 "unknown option: $1"; exit 64 ;;
    esac
done

[[ -d "$app_path" ]] || { print -u2 "app does not exist: $app_path"; exit 66; }
[[ -r "$track" ]] || { print -u2 "track is not readable: $track"; exit 66; }
out_dir="$PWD/$label"
mkdir -p "$out_dir"
limit_mb=4096
cache_root="$HOME/Library/Application Support/Uzume/StemCache/sha256"
uzume_pid=""
typeset -a moved

# --- Stem caches aside (memrepro.sh's pattern), restored on every exit path -----------------------
restore() {
    if [[ -n "$uzume_pid" ]] && kill -0 "$uzume_pid" 2>/dev/null; then
        kill "$uzume_pid" 2>/dev/null; sleep 1; kill -9 "$uzume_pid" 2>/dev/null
    fi
    for entry in $moved; do
        [[ -e "$entry" ]] && mv "$entry" "$out_dir/fresh-cache-${entry:t}"   # what this run built, kept aside
        mv "$entry.vq0-aside-$$" "$entry" && print "restored $entry"
    done
}
trap restore EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

if (( fresh_prep )); then
    if [[ -d "$track" ]]; then files=("$track"/**/*.(mp3|m4a|aac|wav|aiff|aif|flac)(N.)); else files=("$track"); fi
    for f in $files; do
        h=$(shasum -a 256 "$f" | awk '{print $1}')
        entry="$cache_root/${h[1,2]}/$h"
        if [[ -e "$entry" ]]; then mv "$entry" "$entry.vq0-aside-$$" && moved+=("$entry"); fi
    done
    print "stem caches moved aside: ${#moved}"
fi

# --- Launch -----------------------------------------------------------------------------------------
pkill -x Uzume 2>/dev/null; sleep 2
before_session=$(ls -dt "$HOME/Documents/uzume_sessions"/*(/N) | head -1)
env_args=(--env UZUME_LOCAL_FILE_PLAYBACK="$track"
          --env UZUME_SCENE_CYCLE_SECONDS="$cycle"
          --env UZUME_RENDER_SOAK_REPORT="$out_dir"
          --env UZUME_RENDER_SOAK_MINUTES="$minutes"
          --env UZUME_FOOTPRINT_KILL_MB="$limit_mb")
[[ -n "$override" ]] && env_args+=(--env UZUME_DRAWABLE_OVERRIDE="$override")
[[ -n "$toggle" ]] && env_args+=(--env UZUME_RESIZE_TOGGLE_SECONDS="$toggle")
# The floor's pressure is injected in the app (memory_pressure -S needs root, and real critical pressure
# would starve the whole Mac): warning at 40 % of the run, critical at 70 %, normal at 85 %.
(( floor )) && env_args+=(--env UZUME_SIMULATE_MAC_GB=8
    --env UZUME_SIMULATE_PRESSURE="warning:$(( minutes * 40 / 100 )),critical:$(( minutes * 70 / 100 )),normal:$(( minutes * 85 / 100 ))")
open -n "$app_path" $env_args
sleep 4
uzume_pid=$(pgrep -nf "$app_path/Contents/MacOS/Uzume") || { print -u2 "no Uzume process"; exit 1; }
print "pid $uzume_pid  $(ps -o lstart=,command= -p $uzume_pid)"

session=""
for _ in {1..60}; do
    session=$(ls -dt "$HOME/Documents/uzume_sessions"/*(/N) | head -1)
    [[ -n "$session" && "$session" != "$before_session" ]] && break
    sleep 1
done
print "session $session"

# --- Sample and watch -----------------------------------------------------------------------------
print "t_s,footprint_mb" > "$out_dir/footprint.csv"
total=$(( minutes * 60 )); start=$SECONDS; peak=0; why="app finished"
while kill -0 "$uzume_pid" 2>/dev/null; do
    t=$(( SECONDS - start ))
    mb=$(footprint -p "$uzume_pid" 2>/dev/null | awk '/phys_footprint:/ {v=$2; if ($3 ~ /GB/) v*=1024; if ($3 ~ /KB/) v/=1024; print int(v); exit}')
    if [[ -n "$mb" ]]; then
        print "$t,$mb" >> "$out_dir/footprint.csv"
        (( mb > peak )) && peak=$mb
        if (( mb > limit_mb )); then why="WATCHDOG at $mb MB"; kill "$uzume_pid"; break; fi
    fi
    (( t > total + 300 )) && { why="overran by 5 min"; kill "$uzume_pid"; break; }
    sleep 2
done

print "$label: stop=$why  peak=${peak} MB  out=$out_dir  session=$session"
cat "$out_dir/render_soak_summary.txt" 2>/dev/null
