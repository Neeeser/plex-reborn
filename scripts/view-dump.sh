#!/bin/zsh
# Ask the running simulator app to write its screen, window and view layout,
# then copy it to logs/viewdump-<label>.txt and print the top-level lines.
# Usage: scripts/view-dump.sh [label] [grep pattern]
set -euo pipefail
source ${0:A:h}/common.sh
LABEL=${1:-latest}
BID=$(plutil -extract CFBundleIdentifier raw "$SIM_APP/Info.plist")
xcrun simctl spawn "$SIM_UDID" notifyutil -p plexreborn.viewdump
sleep 1
DATA=$(xcrun simctl get_app_container "$SIM_UDID" "$BID" data)
mkdir -p "$PROJ/logs"
OUT="$PROJ/logs/viewdump-$LABEL.txt"
cp "$DATA/Library/PlexViewDump.txt" "$OUT"
grep -E "${2:-^SCREEN|^scene|^FOLD|^WINDOW}" "$OUT" | cut -c1-220
echo "Full dump: $OUT"
