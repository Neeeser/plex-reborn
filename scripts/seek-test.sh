#!/bin/zsh
# Seek the simulator's current video by each offset given (seconds, relative),
# then report where playback actually resumed, from mpv's log lines.
# Usage: scripts/seek-test.sh -30 -60 45
set -euo pipefail
source ${0:A:h}/common.sh
BID=$(plutil -extract CFBundleIdentifier raw "$SIM_APP/Info.plist")
DATA=$(xcrun simctl get_app_container "$SIM_UDID" "$BID" data)
LOG="$DATA/Library/Logs/$(ls -t "$DATA/Library/Logs/" | grep '\.log$' | head -1)"
for delta in "$@"; do
  before=$(${0:A:h}/engine.sh status | sed -E 's/.*progress=([0-9.]+).*/\1/')
  target=$(printf '%.3f' $(( before + delta )))
  mark=$(( $(wc -l < "$LOG") + 1 ))
  ${0:A:h}/engine.sh "seek $target" >/dev/null
  sleep 15
  landed=$(tail -n +$mark "$LOG" | grep -o 'playback restart complete @ [0-9.]*' | tail -1 | grep -o '[0-9.]*$' || true)
  now=$(${0:A:h}/engine.sh status | sed -E 's/.*progress=([0-9.]+).*/\1/')
  restarts=$(tail -n +$mark "$LOG" | grep -c 'Preparing video playback' || true)
  printf 'from %8.1f  target %8.1f  resumed at %8s  15 s later %8.1f  stream restarts %s\n' $before $target "${landed:-none}" $now $restarts
done
