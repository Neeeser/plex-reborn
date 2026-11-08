#!/bin/zsh
# Have Xcode create a development certificate and provisioning profile for a
# bundle ID, so deploy.sh can sign patched apps without Sideloadly.
#
# It builds a placeholder app (signing-stub/) for the phone with automatic
# signing. Xcode must be signed in to your developer account (Xcode > Settings >
# Accounts) and the phone must be connected and unlocked.
# Usage: scripts/make-signing-profile.sh [bundle-id]
set -euo pipefail
source ${0:A:h}/common.sh
BUNDLE_ID=${1:-$TEST_BUNDLE_ID}
STUB="$PROJ/signing-stub"
OUT="$PROJ/work/signing-stub-build"
mkdir -p "$OUT"
ditto "$STUB/Stub" "$OUT/Stub"
cat > "$OUT/project.yml" <<EOF
name: SigningStub
targets:
  SigningStub:
    type: application
    platform: iOS
    deploymentTarget: "15.0"
    sources: [Stub]
    info:
      path: Stub/Info.plist
      properties:
        CFBundleDisplayName: SigningStub
        UILaunchScreen: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
        DEVELOPMENT_TEAM: $TEAM_ID
        CODE_SIGN_STYLE: Automatic
        GENERATE_INFOPLIST_FILE: NO
EOF
cd "$OUT"
xcodegen generate -q
xcodebuild -project SigningStub.xcodeproj -scheme SigningStub -destination "id=$DEVICE_UDID" \
  -allowProvisioningUpdates -derivedDataPath build build > build.log 2>&1 \
  || { echo "xcodebuild failed; see $OUT/build.log"; tail -5 build.log; exit 1; }
echo "Profile ready for $BUNDLE_ID."
