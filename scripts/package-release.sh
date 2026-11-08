#!/bin/zsh
# Build the release files into dist/:
#   PlexReborn-<VERSION>.ipa        Plex 8.45 with Plex Reborn, unsigned, ready for Sideloadly
#   PlexDuoShim-<VERSION>.dylib     the add-on alone, for patching your own copy with patch-ipa.sh
#
# Usage: scripts/package-release.sh                        build the files
#        scripts/package-release.sh --publish "<summary>"  also create a draft GitHub release
#
# The release is titled "v<VERSION> - <summary>" (a plain list of the
# highlights), its notes are the version's CHANGELOG section, and its tag is
# v8.45_<VERSION> (Plex version, then Plex Reborn version).
set -euo pipefail
source ${0:A:h}/common.sh
VERSION=$(<"$PROJ/VERSION")
DIST="$PROJ/dist"
IN="$PROJ/ipa/Plex-8.45-decrypted.ipa"
[[ -f $IN ]] || { echo "Put the decrypted Plex 8.45 IPA at $IN first."; exit 1; }
mkdir -p "$DIST"

# Release builds leave out the view-dump debugging aid; simulator-only files
# compile to nothing for the device.
DYLIB="$DIST/PlexDuoShim-$VERSION.dylib"
build_shim iphoneos "$DIST/$SHIM_NAME" PlexViewDump.m
if nm -gU "$DIST/$SHIM_NAME" | grep -q PLXSim; then echo "Simulator-only code leaked into the release"; exit 1; fi
cp "$DIST/$SHIM_NAME" "$DYLIB"

# No bundle ID or team: the person installing picks the bundle ID in
# Sideloadly, and the add-on adopts their signing team at launch.
IPA="$DIST/PlexReborn-$VERSION.ipa"
"$PROJ/scripts/patch-ipa.sh" "$IN" "$DIST/$SHIM_NAME" "$IPA" --name "Plex Reborn" --release
rm -f "$DIST/$SHIM_NAME"

# The release must not carry anything tied to the account that downloaded Plex.
LEAKS=$(unzip -l "$IPA" | grep -E -i "iTunesMetadata|SC_Info|META-INF|\.sinf|\.supp" || true)
[[ -z $LEAKS ]] || { echo "Account files left in the IPA:"; echo "$LEAKS"; exit 1; }

echo "Built:"
for f in "$IPA" "$DYLIB"; do
  printf '  %-34s %6s  SHA-256 %s\n' "${f:t}" "$(du -h "$f" | cut -f1)" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
done

if [[ ${1:-} == --publish ]]; then
  SUMMARY=${2:?give the release summary, e.g. --publish "Hide Plex's online content and more"}
  NOTES=$(awk -v v="## [v$VERSION]" 'index($0, v)==1{f=1;next} /^## /{f=0} f' "$PROJ/CHANGELOG.md")
  [[ -n $NOTES ]] || { echo "CHANGELOG.md has no ## [v$VERSION] section."; exit 1; }
  gh release create "v8.45_$VERSION" "$IPA" "$DYLIB" --draft --title "v$VERSION - $SUMMARY" --notes "$NOTES"
fi
