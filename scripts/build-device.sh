#!/bin/zsh
# Rebuild the add-on into work/device and install the app on the phone.
set -euo pipefail
source ${0:A:h}/common.sh
[[ -d $DEVICE_APP ]] || { echo "No device app yet. Run scripts/make-device-app.sh first."; exit 1; }
build_shim iphoneos "$DEVICE_APP/Frameworks/$SHIM_NAME"
if nm -gU "$DEVICE_APP/Frameworks/$SHIM_NAME" | grep -q PLXSim; then
  echo "Simulator-only code leaked into the device build"; exit 1
fi
"$PROJ/scripts/deploy.sh" "$DEVICE_APP"
