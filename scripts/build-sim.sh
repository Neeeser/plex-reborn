#!/bin/zsh
# Rebuild the add-on for the simulator, re-sign, install and launch in the Duo simulator.
# The simulator build also compiles the PlexSim*.m/.c files (guarded by
# TARGET_OS_SIMULATOR) that make Plex run there; see docs/duo-playbook/simulator-testing.md.
set -euo pipefail
source ${0:A:h}/common.sh
[[ -d $SIM_APP ]] || { echo "No simulator app yet. Run scripts/make-simulator-app.sh first."; exit 1; }
BID=$(plutil -extract CFBundleIdentifier raw "$SIM_APP/Info.plist")
build_shim iphonesimulator "$SIM_APP/Frameworks/$SHIM_NAME"
while IFS= read -r -d '' item; do
  codesign -f -s - "$item" >/dev/null 2>&1
done < <(find "$SIM_APP/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0)
codesign -f -s - "$SIM_APP" >/dev/null 2>&1
xcrun simctl terminate "$SIM_UDID" "$BID" 2>/dev/null || true
xcrun simctl install "$SIM_UDID" "$SIM_APP"
xcrun simctl launch "$SIM_UDID" "$BID" >/dev/null
echo "Built and launched $BID in the Duo simulator."
