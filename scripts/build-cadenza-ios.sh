#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

reports=dist/ios-reports
mkdir -p "$reports"
xcodebuild -version | tee "$reports/xcode-version.txt"
pod --version
printf '{"POSTHOG_API_KEY":"","POSTHOG_HOST":""}\n' > secrets.json

# Expo restores the repository's protected Podfile through with-ios-native-files.
npx --no-install expo prebuild --platform ios --clean --no-install 2>&1 | tee "$reports/prebuild.log"
projects=(ios/*.xcodeproj)
if (( ${#projects[@]} != 1 )); then
  printf 'Un projet Xcode était attendu, %s trouvé(s).\n' "${#projects[@]}" >&2
  exit 1
fi
scheme="$(basename "${projects[0]}" .xcodeproj)"
if ! grep -Fq "target '$scheme' do" ios/Podfile; then
  printf 'Le Podfile protégé doit déclarer le target %s.\n' "$scheme" >&2
  exit 1
fi
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
  build=9
fi
version="$(node -p 'require("./package.json").version')"
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
mkdir -p "$payload/Payload"
ditto "$app" "$payload/Payload/$(basename "$app")"
(cd "$payload" && zip -qry "$OLDPWD/dist/$ipa" Payload)
(cd dist && shasum -a 256 "$ipa" > SHA256SUMS.txt)
unzip -t "dist/$ipa" > "$reports/ipa-zip.log"

if [[ "${BOOTSTRAP:-false}" == true ]]; then exit 0; fi

xcodebuild "${settings[@]}" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$temporary/cadenza-simulator" build 2>&1 | tee "$reports/simulator-build.log"
device="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print(next(d["udid"] for runtime in sorted(devices, reverse=True) if "iOS-" in runtime
           for d in devices[runtime] if d["name"].startswith("iPhone")))
')"
xcrun simctl boot "$device" || xcrun simctl bootstatus "$device" -b
xcrun simctl bootstatus "$device" -b
sim_apps=("$temporary"/cadenza-simulator/Build/Products/Release-iphonesimulator/*.app)
test "${#sim_apps[@]}" -eq 1
xcrun simctl install "$device" "${sim_apps[0]}"
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100
launch="$(xcrun simctl launch "$device" "$bundle")"
printf '%s\n' "$launch" | tee "$reports/simulator-launch.log"
sleep 8
kill -0 "${launch##*: }"
xcrun simctl io "$device" screenshot "$reports/cadenza-premier-lancement.png"
