#!/bin/zsh
# Convert the patched device app in work/device into a simulator app in work/simulator.
#
# Device binaries do not run in the simulator. Every Mach-O file is thinned to
# arm64 and re-stamped with the iossim platform, then each framework is signed
# ad hoc on its own (a single --deep signature leaves frameworks invalid).
# Run again whenever work/device is rebuilt from a new IPA; build-sim.sh only
# replaces the add-on.
set -euo pipefail
source ${0:A:h}/common.sh
[[ -d $DEVICE_APP ]] || { echo "No device app yet. Run scripts/make-device-app.sh first."; exit 1; }

rm -rf "${SIM_APP:h}" && mkdir -p "${SIM_APP:h}"
ditto "$DEVICE_APP" "$SIM_APP"
rm -rf "$SIM_APP/embedded.mobileprovision"
find "$SIM_APP" -name _CodeSignature -type d -prune -exec rm -rf {} +

n=0
while IFS= read -r -d '' f; do
  file "$f" | grep -q 'Mach-O' || continue
  [[ ${f:t} == "$SHIM_NAME" ]] && continue
  archs=$(lipo -archs "$f" 2>/dev/null)
  [[ $archs == *arm64* ]] || { echo "No arm64 slice: $f"; exit 1; }
  if [[ $archs != arm64 ]]; then lipo -thin arm64 "$f" -output "$f.thin" && mv "$f.thin" "$f"; fi
  minos=$(xcrun vtool -show-build "$f" 2>/dev/null | awk '/minos/{print $2; exit}')
  sdk=$(xcrun vtool -show-build "$f" 2>/dev/null | awk '/sdk/{print $2; exit}')
  xcrun vtool -set-build-version iossim "${minos:-14.5}" "${sdk:-27.1}" -replace -output "$f.sim" "$f" >/dev/null
  mv "$f.sim" "$f"; chmod +x "$f"
  n=$((n + 1))
done < <(find "$SIM_APP" -type f -print0)
echo "Converted $n binaries to the simulator platform."

# Shaders get the same treatment; without it Plex's home background stays black.
if xcrun -sdk iphonesimulator metal --version >/dev/null 2>&1; then
  find "$SIM_APP" -name '*.metallib' -exec python3 -I "$PROJ/scripts/shaders-for-simulator.py" {} \;
else
  echo "Metal toolchain missing, so shaders stay device-only (black home background)."
  echo "Install it with: xcodebuild -downloadComponent MetalToolchain"
fi
"$PROJ/scripts/build-sim.sh"
