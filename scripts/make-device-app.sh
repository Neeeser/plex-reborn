#!/bin/zsh
# Build the add-on and patch the decrypted IPA into work/device, ready for build-device.sh.
# Run once after downloading and decrypting, or to start over from a clean copy.
# Usage: scripts/make-device-app.sh [decrypted.ipa]
set -euo pipefail
source ${0:A:h}/common.sh
IN=${1:-$PROJ/ipa/Plex-8.45-decrypted.ipa}
mkdir -p "$PROJ/work"
build_shim iphoneos "$PROJ/work/$SHIM_NAME"
"$PROJ/scripts/patch-ipa.sh" "$IN" "$PROJ/work/$SHIM_NAME" "$PROJ/work/PlexReborn-dev.ipa" \
  --bundle-id "$TEST_BUNDLE_ID" --name "$TEST_DISPLAY_NAME" --team-id "$TEAM_ID" --unpack "$PROJ/work/device"
