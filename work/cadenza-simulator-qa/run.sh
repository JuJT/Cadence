#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin || "$#" -ne 5 ]]; then
  printf 'Usage: %s REPO DRAFT SHA VERSION BUILD  (macOS/Xcode)\n' "$0" >&2
  exit 64
fi

suite="$(cd "$(dirname "$0")" && pwd)"
out="$(mkdir -p "${CADENZA_QA_OUTPUT:-cadenza-tap-reports}" && cd "${CADENZA_QA_OUTPUT:-cadenza-tap-reports}" && pwd)"
repo="$1"
draft="$2"
sha="$3"
expected_version="$4"
expected_build="$5"
bundle=com.cadence.study
[[ "$sha" =~ ^[0-9a-f]{40}$ ]]

temporary="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/cadenza-taps.XXXXXX")"
device=
finish() {
  if [[ -n "$device" ]]; then
    xcrun simctl spawn "$device" log show --last 15m --style compact \
      --predicate 'process == "Cadenza"' > "$out/runtime.log" 2>&1 || true
    xcrun simctl shutdown "$device" || true
    xcrun simctl delete "$device" || true
  fi
}
trap finish EXIT

release_sha="$(gh release view "$draft" --repo "$repo" --json isDraft,body,targetCommitish \
  --jq 'select(.isDraft and (.body | contains("Résultat : success (simulator)"))) | .targetCommitish')"
test "$release_sha" = "$sha"
gh release download "$draft" --repo "$repo" --dir "$temporary" \
  --pattern Cadenza-simulator.app.zip --pattern Cadenza-iOS-verification.zip
unzip -p "$temporary/Cadenza-iOS-verification.zip" ios-reports/simulator-source.txt > "$out/simulator-source.txt"
test "$(cat "$out/simulator-source.txt")" = "$sha"
ditto -x -k "$temporary/Cadenza-simulator.app.zip" "$temporary/application"

shopt -s nullglob
apps=("$temporary/application/"*.app)
test "${#apps[@]}" -eq 1
app="${apps[0]}"
python3 - "$app" "$bundle" "$expected_version" "$expected_build" <<'PY' | tee "$out/bundle.txt"
import plistlib, re, subprocess, sys
from pathlib import Path

app, identifier, version, build = sys.argv[1:]
app = Path(app)
info = plistlib.loads((app / "Info.plist").read_bytes())
expected = (identifier, version, build)
actual = tuple(info.get(key) for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"))
if actual != expected:
    sys.exit(f"Unexpected simulator app metadata: {actual!r}")
platform = subprocess.check_output(
    ["xcrun", "vtool", "-arch", "arm64", "-show-build", str(app / info["CFBundleExecutable"])], text=True,
)
if not re.search(r"\bplatform IOSSIMULATOR\b", platform):
    sys.exit(f"App is not a native arm64 simulator build: {platform}")
print(*actual)
PY

xcodegen_version=2.49.0
xcodegen_sha=ae5598b33a19ad1e23e775d6648f97375c3529c970905f489358a21055b65e53
xcodegen_archive="$temporary/xcodegen.zip"
curl --fail --silent --show-error --location --connect-timeout 20 --max-time 120 --retry 2 \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$xcodegen_version/xcodegen.zip" -o "$xcodegen_archive"
printf '%s  %s\n' "$xcodegen_sha" "$xcodegen_archive" | shasum -a 256 -c -
ditto -x -k "$xcodegen_archive" "$temporary/xcodegen"
xcodegen_bin="$(find "$temporary/xcodegen" -path '*/bin/xcodegen' -type f -print -quit)"
test -n "$xcodegen_bin"
chmod +x "$xcodegen_bin"
mkdir -p "$temporary/qa"
cp -R "$suite/Fixture" "$suite/Tests" "$suite/project.yml" "$temporary/qa"
(cd "$temporary/qa" && "$xcodegen_bin" generate)

device_config="$(xcrun simctl list devices available -j | python3 -c '
import json, sys

for runtime, devices in reversed(sorted(json.load(sys.stdin)["devices"].items())):
    if "iOS-" not in runtime:
        continue
    phones = [phone for phone in devices if phone["name"].startswith("iPhone") and "Duo" not in phone["name"]]
    if phones:
        phone = next((phone for phone in phones if phone["name"] == "iPhone 17 Pro"), phones[0])
        print(phone["deviceTypeIdentifier"], runtime)
        break
else:
    sys.exit("No iOS simulator runtime available")
')"
read -r model runtime <<< "$device_config"
device="$(xcrun simctl create 'Cadenza Tap QA' "$model" "$runtime")"
xcrun simctl bootstatus "$device" -b | tee "$out/boot.log"
if grep -Fq 'Data Migration Failed' "$out/boot.log"; then exit 1; fi
xcrun simctl spawn "$device" defaults write NSGlobalDomain AppleLanguages -array fr
xcrun simctl spawn "$device" defaults write NSGlobalDomain AppleLocale -string fr_FR
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100

xcrun simctl install "$device" "$app"
xcrun simctl privacy "$device" grant location "$bundle"
result="$temporary/CadenzaTapQA.xcresult"
status=0
xcodebuild test -project "$temporary/qa/CadenzaTapQA.xcodeproj" -scheme CadenzaTapQA \
  -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
  -derivedDataPath "$temporary/derived" -resultBundlePath "$result" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGN_IDENTITY=- 2>&1 | tee "$out/xctest.log" || status=$?
if [[ -d "$result" ]]; then
  xcrun xcresulttool get test-results summary --path "$result" > "$out/tests.json" || true
  xcrun xcresulttool export attachments --path "$result" --output-path "$out/attachments" || true
fi
xcrun simctl io "$device" screenshot "$out/final.png" || true
exit "$status"
