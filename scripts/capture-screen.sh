#!/bin/zsh
# Save a screenshot and a view dump of the running simulator app for UI review.
# Usage: scripts/capture-screen.sh <screen-name> <pose-label>
# Writes logs/audit/<screen-name>/<pose-label>.png and .txt.
set -euo pipefail
source ${0:A:h}/common.sh
SCREEN=${1:?screen name}
POSE=${2:?pose label}
OUT="$PROJ/logs/audit/$SCREEN"
mkdir -p "$OUT"
BID=$(plutil -extract CFBundleIdentifier raw "$SIM_APP/Info.plist")
xcrun simctl spawn "$SIM_UDID" notifyutil -p plexreborn.viewdump
sleep 1
DATA=$(xcrun simctl get_app_container "$SIM_UDID" "$BID" data)
grep -v '^\s*"\|^)\|userInteraction=\|↳ gesture' "$DATA/Library/PlexViewDump.txt" > "$OUT/$POSE.txt"
# The Duo simulator has two displays: 1 is the outer screen (466 pt wide), 3 the inner one.
DISPLAY_ID=3
grep -q "^scene bounds={{0, 0}, {466, 678}}\|^scene bounds={{0, 0}, {678, 466}}" "$OUT/$POSE.txt" && DISPLAY_ID=1
xcrun simctl io "$SIM_UDID" screenshot --display=$DISPLAY_ID "$OUT/$POSE.png" >/dev/null 2>&1
echo "Saved $SCREEN/$POSE ($(wc -l < "$OUT/$POSE.txt") view lines)"
