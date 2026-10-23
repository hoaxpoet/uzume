#!/bin/zsh
# tv_soak.sh — VQ.0's live check on the 4K TV (Matt's hour; docs/RUNBOOK.md §VQ.0 render soak).
#
# Usage: Scripts/tv_soak.sh <app path> <playlist folder> [minutes, default 60]
#
# A named Release build plays the folder with every track's stem cache moved aside (so stem preparation
# runs during the soak — BUG-176's failure was preparation, not rendering), cycles every certified scene
# every 20 s at the display's real size, samples phys_footprint every 2 s, kills at 4 GB and prints the
# session folder. Caches are restored on every exit path. The six steps:
#
#   1. Put the playlist folder in /Users/Shared (external volumes are blocked by TCC).
#   2. Plug the TV in; drag Uzume's window onto it once it opens; make it fullscreen.
#   3. Run:  Scripts/tv_soak.sh "<path to Uzume.app>" "/Users/Shared/<playlist>"
#   4. During the hour: unplug the TV, wait 30 s, plug it back in — twice, ~20 min apart.
#   5. Note anything you see (a freeze, a black frame that stays, stutter after a replug).
#   6. When it ends, send the printed folder name; the report is in ./tv_soak_<time>/.

set -u
(( $# >= 2 )) || { print -u2 "usage: $0 <app path> <playlist folder> [minutes]"; exit 64; }
exec "$(dirname "$0")/render_soak.sh" "$1" "tv_soak_$(date +%Y%m%d_%H%M)" \
    --track "$2" --fresh-prep --minutes "${3:-60}"
