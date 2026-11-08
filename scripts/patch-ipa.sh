#!/bin/zsh
# Turn a decrypted Plex 8.45 IPA into a Duo-ready app with the Plex Reborn add-on.
#
# Usage: patch-ipa.sh <decrypted.ipa> <PlexDuoShim.dylib> <output.ipa> [options]
#   --bundle-id ID     bundle ID for the patched app (needed to install beside App Store Plex)
#   --name NAME        name under the home-screen icon (default "Plex Reborn")
#   --team-id TEAM     your Apple developer team ID; Plex stores its sign-in token
#                      in a keychain group named after it, and sign-in fails without it
#   --unpack DIR       also leave the unpacked Payload folder in DIR (used by the dev scripts)
#
# What it changes, in order:
#   1. Removes the app extensions, SC_Info and iTunesMetadata.plist. Extensions need
#      their own provisioning profiles, and the metadata file lets the App Store
#      replace the app with the current version.
#   2. Sets the bundle ID, display name and keychain prefix.
#   3. Stamps the main binary as built with the iOS 27.1 SDK, so iOS gives it the full
#      Duo display and vertical bars instead of the letterboxed compatibility mode.
#   4. Adds the UIScene manifest. Apps built with the 27 SDK must use scenes; the
#      add-on supplies the scene delegate (PLXSceneDelegate).
#   5. Copies the add-on into Frameworks and adds a load command for it.
# The result is unsigned. Sign it with Sideloadly, or with scripts/deploy.sh.
set -euo pipefail

IN=${1:?usage: patch-ipa.sh <decrypted.ipa> <dylib> <output.ipa> [options]}
DYLIB=${2:?missing dylib}
OUT=${3:?missing output path}
shift 3
BUNDLE_ID="" NAME="Plex Reborn" TEAM="" UNPACK=""
while (( $# )); do
  case $1 in
    --bundle-id) BUNDLE_ID=$2; shift 2;;
    --name) NAME=$2; shift 2;;
    --team-id) TEAM=$2; shift 2;;
    --unpack) UNPACK=$2; shift 2;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done
[[ -n $TEAM ]] || echo "Warning: no --team-id given. Plex sign-in will fail until PlexAppIdPrefix matches the signing team."

WORK=$(mktemp -d "${TMPDIR:-/tmp}/plexpatch.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IN" -d "$WORK"
APP=$(print -r -- "$WORK"/Payload/*.app(N[1]))
[[ -d $APP ]] || { echo "No app inside $IN"; exit 1; }
BIN="$APP/$(plutil -extract CFBundleExecutable raw "$APP/Info.plist")"
if otool -l "$BIN" | grep -A4 LC_ENCRYPTION_INFO | grep -q "cryptid 1"; then
  echo "$IN is still encrypted. Decrypt it first (see docs/tools.md)."; exit 1
fi

# 1. Remove parts that block sideloading or invite App Store updates.
rm -rf "$APP/PlugIns" "$APP/SC_Info" "$APP/_CodeSignature" "$WORK/iTunesMetadata.plist" "$WORK/META-INF"

# 2. Identity.
P="$APP/Info.plist"
[[ -n $BUNDLE_ID ]] && plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$P"
plutil -replace CFBundleDisplayName -string "$NAME" "$P"
plutil -replace CFBundleName -string "$NAME" "$P"
for lp in "$APP"/*.lproj/InfoPlist.strings(N); do
  plutil -remove CFBundleDisplayName "$lp" 2>/dev/null || true
  plutil -remove CFBundleName "$lp" 2>/dev/null || true
done
[[ -n $TEAM ]] && plutil -replace PlexAppIdPrefix -string "$TEAM." "$P"

# 3. SDK stamp, keeping the app's own minimum iOS version.
MINOS=$(xcrun vtool -show-build "$BIN" | awk '/minos/{print $2; exit}')
xcrun vtool -set-build-version ios "${MINOS:-14.5}" 27.1 -replace -output "$BIN.new" "$BIN" >/dev/null
mv "$BIN.new" "$BIN"; chmod +x "$BIN"

# 4. Scene manifest.
plutil -remove UIApplicationSceneManifest "$P" 2>/dev/null || true
plutil -insert UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false,"UISceneConfigurations":{"UIWindowSceneSessionRoleApplication":[{"UISceneConfigurationName":"Default Configuration","UISceneDelegateClassName":"PLXSceneDelegate"}]}}' "$P"

# 5. Add-on library and its load command.
SHIM=${DYLIB:t}
cp "$DYLIB" "$APP/Frameworks/$SHIM"
if ! otool -L "$BIN" | grep -q "$SHIM"; then
  uv run -q --with lief python -I - "$BIN" "@executable_path/Frameworks/$SHIM" <<'EOF'
import sys, lief
binary = lief.parse(sys.argv[1])
binary.add_library(sys.argv[2])
binary.write(sys.argv[1])
EOF
fi
otool -L "$BIN" | grep -q "$SHIM" || { echo "Adding the load command failed"; exit 1; }

OUT=${OUT:A}
rm -f "$OUT"
(cd "$WORK" && zip -qr -y "$OUT" Payload)
if [[ -n $UNPACK ]]; then
  rm -rf "$UNPACK"; mkdir -p "$UNPACK"; ditto "$WORK/Payload" "$UNPACK/Payload"
fi
echo "Patched $(plutil -extract CFBundleShortVersionString raw "$P") as $(plutil -extract CFBundleIdentifier raw "$P") -> $OUT"
