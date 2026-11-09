#!/bin/zsh
# Send a playback command to the simulator app and print the engine status.
# Usage: scripts/engine.sh "seek 300" | "seekby -10" | pause | resume | fakeend | status
# Needs the simulator build (PlexTranscodeSeek.m's test hook) and a video open.
set -euo pipefail
source ${0:A:h}/common.sh
BID=$(plutil -extract CFBundleIdentifier raw "$SIM_APP/Info.plist")
DATA=$(xcrun simctl get_app_container "$SIM_UDID" "$BID" data)
print -r -- "${1:-status}" > "$DATA/Library/PlexEngineCommand.txt"
xcrun simctl spawn "$SIM_UDID" notifyutil -p plexreborn.engine
sleep 0.5
cat "$DATA/Library/PlexEngineStatus.txt"
