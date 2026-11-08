# Shared paths and settings for the Plex Reborn scripts. Sourced, not run.
PROJ=${0:A:h:h}
ROOT=${PROJ:h:h}
if [[ -f "$ROOT/config.local.sh" ]]; then
  source "$ROOT/config.local.sh"
else
  echo "Missing $ROOT/config.local.sh. Copy config.example.sh to config.local.sh and fill it in." >&2
  exit 1
fi

# The patched app used for device builds and the simulator copy made from it.
DEVICE_APP="$PROJ/work/device/Payload/PlexMobile.app"
SIM_APP="$PROJ/work/simulator/PlexMobile.app"

# The test copy installs beside App Store Plex and the plain Plex Legacy copy.
TEST_BUNDLE_ID="${TEST_BUNDLE_ID:-$BUNDLE_PREFIX.plexlegacy.duotest}"
TEST_DISPLAY_NAME="${TEST_DISPLAY_NAME:-Plex Duo Test}"

# Name of the add-on library inside the app's Frameworks folder.
SHIM_NAME="PlexDuoShim.dylib"

# Compiles the add-on. $1 = iphoneos or iphonesimulator, $2 = output path,
# remaining arguments = extra source files to leave out (release builds drop the debug dump).
build_shim() {
  local sdk=$1 out=$2; shift 2
  local -a sources skip=("$@")
  for f in "$PROJ"/src/*.m "$PROJ"/src/*.c; do
    (( ${skip[(Ie)${f:t}]} )) || sources+=("$f")
  done
  local minflag="-mios-version-min=14.5"
  [[ $sdk == iphonesimulator ]] && minflag="-mios-simulator-version-min=15.0"
  xcrun -sdk $sdk clang -arch arm64 -dynamiclib -fobjc-arc -fmodules $minflag \
    -framework UIKit -framework Foundation -framework Security \
    -install_name "@executable_path/Frameworks/$SHIM_NAME" \
    -Wall -Wno-unguarded-availability-new -o "$out" "${sources[@]}"
}
