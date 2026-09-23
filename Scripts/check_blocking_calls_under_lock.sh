#!/usr/bin/env bash
# check_blocking_calls_under_lock.sh
#
# D-161 ratchet gate. Bans blocking audio-stack calls made from inside a locked
# region. The defect class:
#
#   BUG-021 (2026-05-28, LocalFilePlaybackProvider): AVFoundation teardown ran
#     under the provider's NSLock while the scheduleFile completion callback
#     also took it. ABBA deadlock.
#   BUG-139 (2026-09-23, SystemAudioCapture): teardownTapResources() held
#     stateLock across AudioDeviceStop, which blocks until the CoreAudio IO proc
#     drains — while the IO proc took the same lock in probeInstallRMS. Hung the
#     engine suite with no timeout, no failing test, no crash report. Fixed in
#     8eeb9ac6 by claiming handles under the lock and destroying outside it.
#
# Both bit before anyone noticed. The rule was restated in prose twice; D-161
# says a rule violated twice gets mechanized. This is the mechanization.
#
# The fix shape is always the same: take what you need under the lock, release,
# then do the blocking work. `nonisolated static` over a value type makes it
# unreachable by construction (see SystemAudioCapture.destroyTapResources).
#
# Scope limit (honest): this is a lexical matcher, not an escape analysis. It
# sees a banned call only when it appears BETWEEN a lock acquisition and its
# release in the same file:
#   - `someLock.lock()` … `someLock.unlock()` spans
#   - `withLock { … }` bodies
#   - bodies of functions named `*Locked` (the repo convention for "caller holds
#     the lock" — this is how it catches BUG-021's `_stopLocked`)
# It does NOT catch a blocking call one frame deeper — a helper called from a
# locked region that blocks inside itself. That is the harder half of the real
# rule and no grep can see it; it stays on review. It also does not know which
# lock is held, so a `withLock` on lock A containing a blocking call that only
# ever contends on lock B reads as a violation. Allowlist those with a comment.
#
# Brace tracking is crude (it counts braces, ignoring braces inside string
# literals). A file that trips it will over-report, not under-report.
#
# Run from repo root. Exits non-zero on first hit so CI fails loud.

set -euo pipefail

ROOTS=(
  "UzumeEngine/Sources"
  "UzumeApp"
)

# Blocking audio-stack calls. CoreAudio HAL calls block until the IO proc
# drains; AVAudioEngine/AVAudioPlayerNode stop/start block on the render thread.
# Not exhaustive — add to it when a new blocking call bites.
BANNED='AudioDeviceStop\\(|AudioDeviceStart\\(|AudioHardwareDestroyAggregateDevice\\(|AudioHardwareDestroyProcessTap\\(|AudioDeviceDestroyIOProcID\\(|[A-Za-z_]*[Ee]ngine\\??\\.(stop|start)\\(|[A-Za-z_]*[Pp]layer(Node)?\\??\\.stop\\('

# Sites whose lock-held blocking call is intentional and proven safe. Entries
# are extended regexes matched against the emitted `path:line:code` — write them
# as `File\.swift:[0-9]+:.*call` so they survive line drift above the call site.
# Every entry needs a comment saying why the blocking call cannot contend with
# the lock it is under. "It has not deadlocked yet" is not a reason.
ALLOWLIST_SITES=(
  # LocalFilePlaybackProvider._startLocked(), called from `lock.withLock` in
  # start(). Blocking under the lock, but it cannot contend with this lock:
  #
  #   - `engine` and `player` are LOCAL, freshly constructed. `self.engine` /
  #     `self.playerNode` are not assigned until ~40 lines later, AFTER
  #     `_scheduleFileLoopLocked`. The completion callback that takes the lock
  #     guards on `self.playerNode === player` — for this instance that field is
  #     still nil, so no callback for this engine exists yet to block on.
  #   - `AVAudioEngine.start()` brings a render thread UP; there is no prior IO
  #     cycle to drain. BUG-021/BUG-139 are both teardown-direction defects —
  #     stop() blocks waiting for an already-running thread that holds the lock.
  #   - A PREVIOUS instance's callback is a different engine on a different
  #     render thread, and start() calls stop() before taking the lock anyway,
  #     which nils the fields so that callback bails.
  #
  # Startup stayed inside the lock at the BUG-021 fix (18d1ea4c) on this
  # reasoning; teardown is what moved out. If `engine.start()` ever moves below
  # the `self.engine = engine` assignment, this entry is void — delete it.
  'LocalFilePlaybackProvider\.swift:[0-9]+:.*engine\.start\(\)'
)

filter_allowlist() {
  if [ ${#ALLOWLIST_SITES[@]} -eq 0 ]; then cat; else
    grep -vE -f <(printf '%s\n' "${ALLOWLIST_SITES[@]}") || true
  fi
}

violations=$(
  find "${ROOTS[@]}" -name '*.swift' -type f -print0 2>/dev/null \
  | xargs -0 awk -v banned="$BANNED" '
      FNR == 1 { depth = 0; guard = 0; span = 0 }

      {
        line = $0
        code = line
        sub(/\/\/.*$/, "", code)          # strip line comments (crude: ignores strings)

        # --- enter a locked region -------------------------------------------
        entered = 0
        if (code ~ /\.withLock[[:space:]]*\{/) { entered = 1 }
        else if (code ~ /func[[:space:]]+_?[A-Za-z0-9_]*Locked[[:space:]]*[(<]/) { entered = 1 }

        if (entered && guard == 0) {
          guard = 1
          depth = 0
        }

        # explicit lock()/unlock() span, independent of braces
        if (code ~ /[A-Za-z0-9_]+\.lock\(\)/)   { span = 1 }

        # --- report ------------------------------------------------------------
        if ((guard || span) && code ~ banned) {
          printf "%s:%d:%s\n", FILENAME, FNR, line
        }

        # --- leave the region --------------------------------------------------
        if (code ~ /[A-Za-z0-9_]+\.unlock\(\)/) { span = 0 }

        if (guard) {
          n = gsub(/\{/, "{", code)
          m = gsub(/\}/, "}", code)
          depth += n - m
          if (depth <= 0) { guard = 0; depth = 0 }
        }
      }
    ' \
  | filter_allowlist \
  || true
)

if [ -n "$violations" ]; then
  echo "ERROR: blocking audio-stack call inside a locked region:" >&2
  echo "$violations" >&2
  echo >&2
  echo "BUG-021 / BUG-139: a CoreAudio or AVFoundation stop/start blocks until" >&2
  echo "its render thread or IO proc drains. If that thread takes the same lock," >&2
  echo "the process hangs — no timeout, no crash report, no failing test." >&2
  echo >&2
  echo "Fix: claim the handles under the lock, release it, then do the blocking" >&2
  echo "work. See SystemAudioCapture.claimTapResourcesForTeardown() /" >&2
  echo "destroyTapResources(_:) — the latter is nonisolated static over a value" >&2
  echo "type so it cannot reach the lock even by accident." >&2
  echo >&2
  echo "If the call is genuinely safe (it cannot contend with THIS lock), add the" >&2
  echo "site to ALLOWLIST_SITES as a regex, with a comment saying why." >&2
  exit 1
fi

exit 0
