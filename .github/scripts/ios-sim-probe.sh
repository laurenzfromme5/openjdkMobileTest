#!/usr/bin/env bash
set -euo pipefail

SIM_BUILD="${SIM_BUILD:?SIM_BUILD fehlt}"
PROBE_JAR="${PROBE_JAR:?PROBE_JAR fehlt}"
LAUNCHER_SRC="${LAUNCHER_SRC:?LAUNCHER_SRC fehlt}"
INFO_PLIST_SRC="${INFO_PLIST_SRC:?INFO_PLIST_SRC fehlt}"
LIBFFI_SIM_A="${LIBFFI_SIM_A:?LIBFFI_SIM_A fehlt}"
OUT_DIR="${OUT_DIR:-probe-out}"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-18.2}"
MIN_OS_MAJOR="${IOS_MIN_VERSION%%.*}"
SIM_BUNDLE_ID="${SIM_BUNDLE_ID:-org.openjdk.mobile.probe}"
SIM_UDID="${SIM_UDID:-}"
LAUNCH_TIMEOUT="${LAUNCH_TIMEOUT:-300}"

LIB_DIR="$SIM_BUILD/images/static-libs/lib"
JVM_A="$LIB_DIR/zero/libjvm.a"
INCLUDE_DIR="$SIM_BUILD/jdk/include"
MODULES_SRC="$SIM_BUILD/jdk/modules/java.base"
LIBSIM_A="$OUT_DIR/libsim.a"
APP="$OUT_DIR/Probe.app"

for f in "$JVM_A" "$LIB_DIR/libjava.a" "$LIB_DIR/libzip.a" "$LIB_DIR/libnet.a" \
         "$LIB_DIR/libnio.a" "$LIB_DIR/libjimage.a" "$LIBFFI_SIM_A" "$PROBE_JAR" "$LAUNCHER_SRC"; do
  if [ ! -f "$f" ]; then
    echo "::error::fehlende Datei: $f" >&2
    exit 1
  fi
done
if [ ! -d "$MODULES_SRC" ]; then
  echo "::error::explodiertes Modul java.base fehlt: $MODULES_SRC" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "::error::jq nicht installiert" >&2; exit 1; }

SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
SDK_MAJOR="${SDK_VERSION%%.*}"
if [ "$SDK_MAJOR" -lt "$MIN_OS_MAJOR" ]; then
  echo "::error::iPhoneSimulator.sdk $SDK_VERSION ist aelter als iOS $MIN_OS_MAJOR; der Simulator-Build von openjdk/mobile setzt mindestens iOS $MIN_OS_MAJOR voraus" >&2
  exit 1
fi
MIN_OS="$SDK_VERSION"
echo "iPhoneSimulator.sdk: $SDK_PATH ($SDK_VERSION), deployment target: $MIN_OS"

mkdir -p "$OUT_DIR"
rm -rf "$APP"
mkdir -p "$APP/lib/modules"

libtool -static -o "$LIBSIM_A" \
  "$JVM_A" "$LIBFFI_SIM_A" \
  "$LIB_DIR/libjava.a" "$LIB_DIR/libzip.a" "$LIB_DIR/libnet.a" \
  "$LIB_DIR/libnio.a" "$LIB_DIR/libjimage.a"
echo "libsim.a: $(du -h "$LIBSIM_A" | cut -f1)"

if [ -d "$INCLUDE_DIR/ios" ]; then
  cp "$INCLUDE_DIR"/ios/*.h "$INCLUDE_DIR"/
fi
INCLUDES="-I$INCLUDE_DIR"
for d in darwin ios macosx; do
  if [ -d "$INCLUDE_DIR/$d" ]; then
    INCLUDES="$INCLUDES -I$INCLUDE_DIR/$d"
  fi
done

xcrun --sdk iphonesimulator clang \
  -target arm64-apple-ios-simulator \
  -mios-simulator-version-min="$MIN_OS" \
  -isysroot "$SDK_PATH" \
  -fobjc-arc -Wall -O1 \
  -x objective-c "$LAUNCHER_SRC" \
  $INCLUDES \
  "$LIBSIM_A" \
  -framework Foundation -lz -lc++ \
  -o "$APP/Probe"
file "$APP/Probe"

cp "$PROBE_JAR" "$APP/HelloWorld.jar"
sed "s/__MIN_OS_VERSION__/$MIN_OS/" "$INFO_PLIST_SRC" > "$APP/Info.plist"
plutil -lint "$APP/Info.plist"
cp -R "$MODULES_SRC" "$APP/lib/modules/java.base"
echo "Boot-Image-Kandidat der VM: <bundle>/lib/modules/java.base (java.home = <bundle>/lib)"
du -sh "$APP"

codesign --force --sign - --timestamp=none "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Identifier|Format|TeamIdentifier' || true

if [ -n "$SIM_UDID" ]; then
  UDID="$SIM_UDID"
  RUNTIME_KEY=$(xcrun simctl list devices -j | jq -r --arg u "$UDID" \
    '[.devices | to_entries[] | select(.value | any(.udid == $u))] | .[0].key // empty')
  if [ -z "$RUNTIME_KEY" ]; then
    echo "::error::angegebenes Simulator-Geraet $UDID nicht gefunden" >&2
    exit 1
  fi
else
  CHOICE=$(xcrun simctl list devices available -j | jq -r --argjson need "$SDK_MAJOR" '
    def candidates: .devices | to_entries[]
      | select(.key | startswith("com.apple.CoreSimulator.SimRuntime.iOS-"))
      | ((.key | split("-"))[1] | tonumber) as $maj
      | .value[]
      | select(.isAvailable and (.name | startswith("iPhone")))
      | [$maj, .udid];
    [candidates] | map(select(.[0] >= $need)) | sort_by(.[0]) | last | @tsv')
  if [ -z "$CHOICE" ] || [ "$CHOICE" = "null" ]; then
    echo "::error::kein iOS-Simulator mit Runtime >= $SDK_MAJOR gefunden" >&2
    xcrun simctl list runtimes >&2
    xcrun simctl list devices available >&2
    exit 1
  fi
  IFS=$'\t' read -r RUNTIME_MAJOR UDID <<<"$CHOICE"
  RUNTIME_KEY="iOS-$RUNTIME_MAJOR"
fi
echo "Simulator: udid=$UDID runtime=$RUNTIME_KEY"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl get_app_container "$UDID" "$SIM_BUNDLE_ID" bundle

TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout $LAUNCH_TIMEOUT"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout $LAUNCH_TIMEOUT"
else
  echo "::warning::kein timeout-Programm gefunden, Start laeuft ohne Zeitlimit" >&2
fi

echo "Start der Sonde auf dem Simulator (stdout landet im Log)"
$TIMEOUT_CMD xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$SIM_BUNDLE_ID"
echo "Sonde beendet"
