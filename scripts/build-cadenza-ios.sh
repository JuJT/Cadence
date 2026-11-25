#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

reports=dist/ios-reports
mkdir -p "$reports"
xcodebuild -version | tee "$reports/xcode-version.txt"
pod --version
if [[ "${BOOTSTRAP:-false}" == true ]]; then
  printf '{"POSTHOG_API_KEY":"","POSTHOG_HOST":""}\n' > secrets.json
fi

# Expo restores the repository's protected Podfile through with-ios-native-files.
npx --no-install expo prebuild --platform ios --clean --no-install 2>&1 | tee "$reports/prebuild.log"
projects=(ios/*.xcodeproj)
if (( ${#projects[@]} != 1 )); then
  printf 'Un projet Xcode était attendu, %s trouvé(s).\n' "${#projects[@]}" >&2
  exit 1
fi
scheme="$(basename "${projects[0]}" .xcodeproj)"
(cd ios && pod install) 2>&1 | tee "$reports/pods.log"
printf 'export NODE_BINARY=%q\n' "$(command -v node)" > ios/.xcode.env.local
cp ios/Podfile.lock "$reports/Podfile.lock"

temporary="${RUNNER_TEMP:-$(mktemp -d)}"
settings=(
  -workspace "ios/$scheme.xcworkspace"
  -scheme "$scheme"
  -configuration Release
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
)
verify_react_framework() {
  xcrun nm -arch arm64 -gU "$1/Frameworks/React.framework/React" > "$reports/react-exports.log"
  if ! grep -Fq '_OBJC_CLASS_$_RCTStatusBarAppearance' "$reports/react-exports.log"; then
    printf 'React.framework ne fournit pas RCTStatusBarAppearance, requis par ExpoModulesCore.\n' >&2
    return 1
  fi
}

destination="${CADENZA_BUILD_DESTINATION:-both}"
if [[ "$destination" != simulator ]]; then
xcodebuild "${settings[@]}" -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$temporary/cadenza-device" build 2>&1 | tee "$reports/device-build.log"

apps=("$temporary"/cadenza-device/Build/Products/Release-iphoneos/*.app)
if (( ${#apps[@]} != 1 )); then
  printf 'Une application iPhone était attendue, %s trouvée(s).\n' "${#apps[@]}" >&2
  exit 1
fi
app="${apps[0]}"
if [[ "${BOOTSTRAP:-false}" == true ]]; then
  ipa=Papillon-base-unsigned.ipa
  bundle=xyz.getpapillon.ios
  build=
else
  ipa=Cadenza-iPhone-0.8.0.ipa
  bundle=com.cadence.study
  build=10
fi
version="$(node -p 'require("./package.json").version')"
if [[ -n "$build" ]]; then
  test "$version" = "0.8.0"
  verify_react_framework "$app"
fi
python3 scripts/verify-cadenza-ios.py "$app" "$bundle" "$version" "$build" "$reports/bundle.json"

# Record generated capability metadata in ad-hoc signatures for the re-signer.
# These signatures are local templates; Sideloadly supplies the real profiles.
for container in "$app" "$app"/PlugIns/*.appex; do
  if [[ -d "$container/Frameworks" ]]; then
    find "$container/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0 |
      while IFS= read -r -d '' item; do /usr/bin/codesign --force --sign - "$item"; done
  fi
done
for container in "$app"/PlugIns/*.appex "$app"; do
  name="$(basename "${container%.*}")"
  entitlement_files=(ios/"$name"/*.entitlements)
  if (( ${#entitlement_files[@]} == 1 )); then
    intent="$reports/$name-entitlements.plist"
    sed 's/$(AppIdentifierPrefix)/UNSIGNED00./g;s/$(TeamIdentifierPrefix)/UNSIGNED00./g' \
      "${entitlement_files[0]}" > "$intent"
    /usr/bin/codesign --force --sign - --generate-entitlement-der --entitlements "$intent" "$container"
  else
    /usr/bin/codesign --force --sign - "$container"
  fi
done

payload="$(mktemp -d "$temporary/cadenza-ipa.XXXXXX")"
ipa_path="$PWD/dist/$ipa"
mkdir -p "$payload/Payload"
ditto "$app" "$payload/Payload/$(basename "$app")"
(cd "$payload" && zip -qry "$ipa_path" Payload)
(cd dist && shasum -a 256 "$ipa" > SHA256SUMS.txt)
unzip -t "dist/$ipa" > "$reports/ipa-zip.log"
fi

if [[ "$destination" == device || "${BOOTSTRAP:-false}" == true ]]; then exit 0; fi

xcodebuild "${settings[@]}" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -derivedDataPath "$temporary/cadenza-simulator" build 2>&1 | tee "$reports/simulator-build.log"
sim_apps=("$temporary"/cadenza-simulator/Build/Products/Release-iphonesimulator/*.app)
test "${#sim_apps[@]}" -eq 1
verify_react_framework "${sim_apps[0]}"
ditto -c -k --keepParent "${sim_apps[0]}" dist/Cadenza-simulator.app.zip
/usr/bin/codesign -d --entitlements :- "${sim_apps[0]}" > "$reports/simulator-entitlements.plist" 2> "$reports/simulator-signature.log" || true
device_config="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [(runtime, d) for runtime in sorted(devices, reverse=True) if "iOS-" in runtime
          for d in devices[runtime] if d["name"].startswith("iPhone")]
runtime, phone = next(((runtime, d) for runtime, d in phones if "Duo" not in d["name"]), phones[0])
print(phone["deviceTypeIdentifier"], runtime)
')"
read -r device_type runtime <<< "$device_config"
device="$(xcrun simctl create 'Cadenza QA' "$device_type" "$runtime")"
xcrun simctl bootstatus "$device" -b 2>&1 | tee "$reports/simulator-boot.log"
if grep -Fq 'Data Migration Failed' "$reports/simulator-boot.log"; then
  printf 'Le simulateur n’a pas terminé son démarrage.\n' >&2
  exit 1
fi
xcrun simctl install "$device" "${sim_apps[0]}"
bundle=com.cadence.study
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100

collect_launch_logs() {
  local diagnostics artifact
  xcrun simctl spawn "$device" log show --last 3m --style compact \
    --predicate 'process == "Cadenza" OR eventMessage CONTAINS[c] "com.cadence.study"' \
    > "$reports/simulator-runtime.log" 2>&1 || true
  for diagnostics in "$HOME/Library/Logs/DiagnosticReports" \
    "$HOME/Library/Developer/CoreSimulator/Devices/$device/data/Library/Logs/CrashReporter"; do
    for artifact in "$diagnostics"/Cadenza*.ips "$diagnostics"/Cadenza*.crash; do
      cp "$artifact" "$reports/"
    done
  done
}

preview() {
  local image="$1" label="${1%.png}" launch
  shift
  if ! launch="$(xcrun simctl launch --terminate-running-process \
    --stdout="$PWD/$reports/$label-stdout.log" --stderr="$PWD/$reports/$label-stderr.log" \
    "$device" "$bundle" "$@")"; then
    collect_launch_logs
    return 1
  fi
  printf '%s %s\n' "$image" "$launch" | tee -a "$reports/simulator-launch.log"
  sleep 14
  if ! kill -0 "${launch##*: }"; then
    collect_launch_logs
    return 1
  fi
  xcrun simctl io "$device" screenshot "$reports/$image"
}
preview cadenza-premier-lancement.png
preview cadenza-accueil.png --cadenza-preview home
preview cadenza-cours.png --cadenza-preview courses
preview cadenza-notes.png --cadenza-preview grades
preview cadenza-etude.png --cadenza-preview study
collect_launch_logs
python3 - "$reports" <<'PY'
import hashlib
from pathlib import Path
import sys

screens = sorted(Path(sys.argv[1]).glob("cadenza-*.png"))
digests = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in screens}
if len(digests) != 5 or len(set(digests.values())) != 5:
    raise SystemExit(f"Le simulateur doit fournir cinq captures différentes : {digests}")
PY
