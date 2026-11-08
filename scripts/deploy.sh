#!/bin/zsh
# Sign an unpacked .app with the Xcode-managed development profile and install
# it on the phone, without Sideloadly.
#
# Usage: scripts/deploy.sh <path/to/App.app> [bundle-id]
# The bundle ID needs a provisioning profile first: run scripts/make-signing-profile.sh once.
set -euo pipefail
source ${0:A:h}/common.sh

APP_SRC=${1:?usage: deploy.sh <app> [bundle-id]}
BUNDLE_ID=${2:-$TEST_BUNDLE_ID}
WORK="$PROJ/work/build/deploy"
LOG="$WORK/deploy.log"

rm -rf "$WORK" && mkdir -p "$WORK"
: > "$LOG"

# Find the newest profile whose application-identifier ends in this bundle ID.
PROFILE=""
for p in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision(N); do
  appid=$(security cms -D -i "$p" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)
  if [[ "$appid" == *".$BUNDLE_ID" ]]; then PROFILE="$p"; fi
done
[[ -n "$PROFILE" ]] || { echo "No profile for $BUNDLE_ID. Run scripts/make-signing-profile.sh first."; exit 1; }

security cms -D -i "$PROFILE" > "$WORK/profile.plist"
plutil -extract Entitlements xml1 -o "$WORK/entitlements.plist" "$WORK/profile.plist"
TEAM=$(plutil -extract TeamIdentifier.0 raw -o - "$WORK/profile.plist")
# A profile can list several team certificates; use the one whose private key
# is in this Mac's keychain.
IDENTITIES=$(security find-identity -v -p codesigning)
CERT_SHA=""
i=0
while cert=$(plutil -extract "DeveloperCertificates.$i" raw -o - "$WORK/profile.plist" 2>/dev/null); do
  sha=$(print -r -- "$cert" | base64 -D | shasum | cut -d' ' -f1 | tr a-f A-F)
  if [[ "$IDENTITIES" == *"$sha"* ]]; then CERT_SHA="$sha"; break; fi
  i=$((i + 1))
done
[[ -n "$CERT_SHA" ]] || { echo "None of the profile's certificates are in this Mac's keychain."; exit 1; }

APP="$WORK/$(basename "$APP_SRC")"
ditto "$APP_SRC" "$APP"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Info.plist"
# Plex builds its keychain access group from this prefix; it must be the signing
# team or sign-in tokens cannot be saved and Plex reports the login as expired.
plutil -replace PlexAppIdPrefix -string "$TEAM." "$APP/Info.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature" "$APP/SC_Info"

# Sign nested code first (dylibs, then frameworks), then the app itself.
count=0
while IFS= read -r -d '' item; do
  codesign -f -s "$CERT_SHA" --generate-entitlement-der "$item" >> "$LOG" 2>&1
  count=$((count + 1))
done < <(find "$APP/Frameworks" \( -name '*.dylib' -o -name '*.framework' \) -print0 2>/dev/null)
codesign -f -s "$CERT_SHA" --entitlements "$WORK/entitlements.plist" --generate-entitlement-der "$APP" >> "$LOG" 2>&1
codesign --verify --deep --strict "$APP" >> "$LOG" 2>&1 || { echo "Signature check failed; see $LOG"; exit 1; }

echo "Signed $(basename "$APP") as $BUNDLE_ID ($count nested items)."
if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" >> "$LOG" 2>&1; then
  echo "Install failed; last lines of $LOG:"; tail -5 "$LOG"; exit 1
fi
echo "Installed on the phone."
