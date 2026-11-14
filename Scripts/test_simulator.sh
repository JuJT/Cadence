#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/reports dist/screenshots
xcrun simctl list devices available --json > dist/reports/simulators.json
simulator_id="$(python3 - <<'PY'
import json
data = json.load(open('dist/reports/simulators.json'))['devices']
candidates = [(runtime, item['name'], item['udid']) for runtime, devices in data.items()
              if 'iOS' in runtime for item in devices
              if item.get('isAvailable') and item['name'].startswith('iPhone')]
if not candidates:
    raise SystemExit('Aucun simulateur iPhone installé sur ce runner. Aucun test simulateur validé.')
print(sorted(candidates, reverse=True)[0][2])
PY
)"
xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl status_bar "$simulator_id" override --time '9:41' --batteryState charged --batteryLevel 100
derived="${RUNNER_TEMP:-$PWD/work}/CadenceSimulator"
xcodebuild -project Cadence.xcodeproj -scheme CadenceExtensions \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$derived" -resultBundlePath dist/CadenceUITests.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | tee dist/reports/simulator-tests.log
app="$derived/Build/Products/Debug-iphonesimulator/Cadence.app"
xcrun simctl install "$simulator_id" "$app"
xcrun simctl launch "$simulator_id" com.cadence.study --uitesting
sleep 3
for route in accueil cours revision statistiques; do
  xcrun simctl openurl "$simulator_id" "cadence://$route"
  sleep 2
  xcrun simctl io "$simulator_id" screenshot "dist/screenshots/$route-clair.png"
done
xcrun simctl ui "$simulator_id" appearance dark
sleep 2
xcrun simctl io "$simulator_id" screenshot dist/screenshots/statistiques-sombre.png
xcrun simctl ui "$simulator_id" appearance light
printf '%s\n' 'Tests et captures de simulateur générés dans ce run. Aucun test physique iPhone.' > dist/reports/simulator-status.txt
