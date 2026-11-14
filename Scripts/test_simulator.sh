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
tests_status=0
xcodebuild -project Cadence.xcodeproj -scheme CadenceExtensions \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$derived" -resultBundlePath dist/CadenceUITests.xcresult \
  -parallel-testing-enabled NO \
  -skip-testing:CadenceUITests/CadenceUITests/testIPadLandscapeLayout \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | tee dist/reports/simulator-tests.log || tests_status=$?
attachments_status=0
if [[ -d dist/CadenceUITests.xcresult ]]; then
  mkdir -p dist/test-attachments
  # La commande moderne est documentée par Apple depuis Xcode 16; garder l’aide
  # du SDK effectivement présent dans le rapport, sans utiliser l’API --legacy.
  xcrun xcresulttool export attachments --help > dist/reports/xcresult-attachments-help.txt 2>&1
  xcrun xcresulttool export attachments --path dist/CadenceUITests.xcresult \
    --output-path dist/test-attachments/iphone 2>&1 | tee dist/reports/test-attachments-iphone.log || attachments_status=$?
fi
if (( tests_status != 0 )); then exit "$tests_status"; fi
if (( attachments_status != 0 )); then exit "$attachments_status"; fi
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

# Même binaire de simulateur universel iPhone/iPad; aucune prétendue capture
# lorsqu’aucun appareil iPad n’est disponible sur l’image du runner.
ipad_id="$(python3 - <<'PY'
import json
data = json.load(open('dist/reports/simulators.json'))['devices']
candidates = [(runtime, item['name'], item['udid']) for runtime, devices in data.items()
              if 'iOS' in runtime for item in devices
              if item.get('isAvailable') and item['name'].startswith('iPad')]
print(sorted(candidates, reverse=True)[0][2] if candidates else '')
PY
)"
if [[ -n "$ipad_id" ]]; then
  xcrun simctl shutdown "$simulator_id"
  xcrun simctl boot "$ipad_id" 2>/dev/null || true
  xcrun simctl bootstatus "$ipad_id" -b
  xcrun simctl status_bar "$ipad_id" override --time '9:41' --batteryState charged --batteryLevel 100
  xcrun simctl ui "$ipad_id" appearance light
  xcrun simctl install "$ipad_id" "$app"
  ipad_tests_status=0
  xcodebuild -project Cadence.xcodeproj -scheme CadenceExtensions \
    -configuration Debug -destination "platform=iOS Simulator,id=$ipad_id" \
    -derivedDataPath "$derived" -resultBundlePath dist/CadenceIPadUITests.xcresult \
    -parallel-testing-enabled NO \
    -only-testing:CadenceUITests/CadenceUITests/testIPadLandscapeLayout \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | tee dist/reports/ipad-tests.log || ipad_tests_status=$?
  ipad_attachments_status=0
  if [[ -d dist/CadenceIPadUITests.xcresult ]]; then
    xcrun xcresulttool export attachments --path dist/CadenceIPadUITests.xcresult \
      --output-path dist/test-attachments/ipad 2>&1 | tee dist/reports/test-attachments-ipad.log || ipad_attachments_status=$?
  fi
  if (( ipad_tests_status != 0 )); then exit "$ipad_tests_status"; fi
  if (( ipad_attachments_status != 0 )); then exit "$ipad_attachments_status"; fi
  xcrun simctl launch "$ipad_id" com.cadence.study --uitesting
  sleep 3
  for route in accueil statistiques; do
    xcrun simctl openurl "$ipad_id" "cadence://$route"
    sleep 2
    xcrun simctl io "$ipad_id" screenshot "dist/screenshots/ipad-$route-clair.png"
  done
  printf '%s\n' "Test iPad paysage exécuté sur $ipad_id. Pièces jointes XCTest dans test-attachments/ipad; captures complémentaires dans screenshots/ipad-*.png." > dist/reports/ipad-status.txt
else
  printf '%s\n' 'Aucun simulateur iPad disponible sur ce runner : aucune capture iPad et aucun test iPad validé.' > dist/reports/ipad-status.txt
fi
printf '%s\n' 'Tests et captures iPhone de simulateur générés dans ce run; statut iPad dans ipad-status.txt. Aucun test physique iPhone/iPad.' > dist/reports/simulator-status.txt
