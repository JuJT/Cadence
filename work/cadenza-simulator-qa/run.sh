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

maestro_version=2.12.1
maestro_zip_sha=54dbb0716425626604973cbb374c585ca30272375d9ce15177a1152765ddd9d7
maestro_archive="$temporary/maestro.zip"
curl --fail --silent --show-error --location --retry 3 \
  "https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$maestro_version/maestro.zip" -o "$maestro_archive"
printf '%s  %s\n' "$maestro_zip_sha" "$maestro_archive" | shasum -a 256 -c -
ditto -x -k "$maestro_archive" "$temporary/maestro-cli"
maestro_bin="$(find "$temporary/maestro-cli" -path '*/bin/maestro' -type f -print -quit)"
test -n "$maestro_bin"
chmod +x "$maestro_bin"
export MAESTRO_CLI_NO_ANALYTICS=1 CI=true
java -version 2>&1 | tee "$out/java-version.txt"
"$maestro_bin" --version | tee "$out/maestro-version.txt"

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

failed=0
for flow in home-settings home-palette course-clock homework-clock; do
  mkdir -p "$out/$flow"
  if [[ "$flow" != home-settings ]]; then xcrun simctl uninstall "$device" "$bundle"; fi
  xcrun simctl install "$device" "$app"
  xcrun simctl privacy "$device" grant location "$bundle"
  xcrun simctl launch --terminate-running-process "$device" "$bundle" --cadenza-preview home | tee "$out/$flow/launch.log"
  # Keep the app in the foreground so the two-token preview argument is handled by the shipped build.
  if ! "$maestro_bin" --device "$device" test "$suite/$flow.yaml" \
    --format junit --output "$out/$flow/report.xml" --test-output-dir "$out/$flow" \
    --debug-output "$out/$flow/debug" 2>&1 | tee "$out/$flow/maestro.log"; then
    failed=1
    "$maestro_bin" --device "$device" hierarchy > "$out/$flow/hierarchy.json" 2> "$out/$flow/hierarchy.log" || true
  fi
  xcrun simctl io "$device" screenshot "$out/$flow/final.png" || true
done
exit "$failed"
