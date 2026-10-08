#!/bin/zsh

# BUG-176: measured Understory + real-music launch.
#
# Usage: Scripts/memrepro.sh <app path> <label> [playback seconds, default 300]
#
# The licensed input must already exist at the fixed /Users/Shared path. The
# script moves its content-addressed cache entry aside, restores it on every
# exit path, samples phys_footprint every two seconds, and kills Uzume at 8 GB.

set -u

if (( $# < 2 || $# > 3 )); then
    print -u2 "usage: $0 <app path> <label> [playback seconds]"
    exit 64
fi

app_path=$1
label=$2
playback_seconds=${3:-300}
track_path="/Users/Shared/memrepro/01 Dance Yrself Clean.mp3"
output_csv="$PWD/$label.csv"
limit_mb=8192
cache_root="$HOME/Library/Application Support/Uzume/StemCache/sha256"

if [[ ! -d "$app_path" ]]; then
    print -u2 "app does not exist: $app_path"
    exit 66
fi
if [[ ! -r "$track_path" ]]; then
    print -u2 "track is not readable: $track_path"
    exit 66
fi
if [[ ! "$playback_seconds" == <-> ]]; then
    print -u2 "playback seconds must be a non-negative integer"
    exit 64
fi

track_hash=$(shasum -a 256 "$track_path" | awk '{print $1}')
cache_entry="$cache_root/${track_hash[1,2]}/$track_hash"
cache_aside="$cache_entry.memrepro-old-$$"
fresh_cache_copy="/private/tmp/uzume-memrepro-$label-$$-fresh-cache"
had_cache=0
uzume_pid=""

restore_cache() {
    if [[ -n "$uzume_pid" ]] && kill -0 "$uzume_pid" 2>/dev/null; then
        kill "$uzume_pid" 2>/dev/null || true
        sleep 1
        kill -9 "$uzume_pid" 2>/dev/null || true
    fi

    if (( had_cache == 1 )); then
        if [[ -e "$cache_entry" ]]; then
            mv "$cache_entry" "$fresh_cache_copy"
            print "fresh cache preserved at $fresh_cache_copy"
        fi
        if [[ -e "$cache_aside" ]]; then
            mv "$cache_aside" "$cache_entry"
            print "original cache restored at $cache_entry"
        fi
    fi
}
trap restore_cache EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ -e "$cache_entry" ]]; then
    mv "$cache_entry" "$cache_aside"
    had_cache=1
    print "original cache moved aside: $cache_aside"
fi

pkill -x Uzume 2>/dev/null || true
sleep 2

before_session=$(ls -dt "$HOME/Documents/uzume_sessions"/*(/N) | head -1)
open -n "$app_path" \
    --env UZUME_LOCAL_FILE_PLAYBACK="$track_path" \
    --env UZUME_PIN_SCENE=Understory
sleep 3

uzume_pid=$(pgrep -nx Uzume) || {
    print -u2 "no Uzume process"
    exit 1
}

session=""
for _ in {1..120}; do
    session=$(ls -dt "$HOME/Documents/uzume_sessions"/*(/N) | head -1)
    [[ -n "$session" && "$session" != "$before_session" ]] && break
    sleep 1
done
if [[ -z "$session" || "$session" == "$before_session" ]]; then
    print -u2 "no new session (permission prompt not answered?)"
    exit 1
fi

binary=$(ps -o command= -p "$uzume_pid")
print "pid $uzume_pid  binary $binary  session $session"
ps -Ao pid,lstart,command | grep "Uzume.*\\.app/Contents/MacOS" | grep -v grep || true

print "t_s,footprint_mb" > "$output_csv"
start=$SECONDS
ready_at=0
peak=0
why="timeout"

while (( SECONDS - start < 900 )); do
    kill -0 "$uzume_pid" 2>/dev/null || {
        why="exited"
        break
    }
    footprint_mb=$(footprint -p "$uzume_pid" 2>/dev/null | awk '
        /phys_footprint:/ {
            value=$2; unit=$3
            if (unit ~ /GB/) value*=1024
            if (unit ~ /KB/) value/=1024
            print int(value)
            exit
        }
    ')
    if [[ -n "$footprint_mb" ]]; then
        print "$((SECONDS - start)),$footprint_mb" >> "$output_csv"
        (( footprint_mb > peak )) && peak=$footprint_mb
    fi
    if [[ -n "$footprint_mb" ]] && (( footprint_mb > limit_mb )); then
        why="WATCHDOG at ${footprint_mb} MB"
        break
    fi
    if (( ready_at == 0 )) \
        && grep -q "startLocalFiles→ready" "$session/session.log" 2>/dev/null; then
        ready_at=$((SECONDS - start))
    fi
    if (( ready_at > 0 && SECONDS - start - ready_at > playback_seconds )); then
        why="ready + ${playback_seconds} s"
        break
    fi
    sleep 2
done

print "$label: stop=$why  peak=${peak} MB  ready_at=${ready_at}s  csv=$output_csv"
