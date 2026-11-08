#!/bin/zsh
# Build a release zip: the device add-on, the patch script and install notes.
# Plex's own app is never included; users patch an IPA they decrypted themselves.
#
# Usage: scripts/package-release.sh            builds dist/PlexReborn-<VERSION>.zip
#        scripts/package-release.sh --publish  also creates a GitHub release draft
set -euo pipefail
PROJ=${0:A:h:h}
SHIM_NAME="PlexDuoShim.dylib"
VERSION=$(<"$PROJ/VERSION")
DIST="$PROJ/dist"
STAGE="$DIST/PlexReborn-$VERSION"
rm -rf "$STAGE" && mkdir -p "$STAGE"

# Release builds leave out the view-dump debugging aid; simulator-only files
# compile to nothing for the device.
sources=()
for f in "$PROJ"/src/*.m "$PROJ"/src/*.c; do
  [[ ${f:t} == PlexViewDump.m ]] || sources+=("$f")
done
xcrun -sdk iphoneos clang -arch arm64 -dynamiclib -fobjc-arc -fmodules -mios-version-min=14.5 \
  -framework UIKit -framework Foundation -framework Security \
  -install_name "@executable_path/Frameworks/$SHIM_NAME" -Wall -Wno-unguarded-availability-new \
  -o "$STAGE/$SHIM_NAME" "${sources[@]}"
if nm -gU "$STAGE/$SHIM_NAME" | grep -q PLXSim; then echo "Simulator-only code leaked into the release"; exit 1; fi

cp "$PROJ/scripts/patch-ipa.sh" "$STAGE/"
cp "$PROJ/README.md" "$PROJ/CHANGELOG.md" "$STAGE/"
(cd "$DIST" && rm -f "PlexReborn-$VERSION.zip" && zip -qr "PlexReborn-$VERSION.zip" "PlexReborn-$VERSION")
SHA=$(shasum -a 256 "$DIST/PlexReborn-$VERSION.zip" | cut -d' ' -f1)
echo "Built dist/PlexReborn-$VERSION.zip"
echo "SHA-256 $SHA"

if [[ ${1:-} == --publish ]]; then
  NOTES=$(awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' "$PROJ/CHANGELOG.md")
  gh release create "plex-reborn-v$VERSION" "$DIST/PlexReborn-$VERSION.zip" --draft \
    --title "Plex Reborn $VERSION" --notes "$NOTES"$'\n\n'"SHA-256: \`$SHA\`"
fi
