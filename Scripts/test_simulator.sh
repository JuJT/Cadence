#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/reports dist/test-attachments dist/screenshots
xcrun simctl list devices available --json > dist/reports/simulators.json
simulator_id="$(python3 - <<'PY'
import json
data = json.load(open('dist/reports/simulators.json'))['devices']
candidates = [(runtime, item['name'], item['udid']) for runtime, devices in data.items()
              if 'iOS' in runtime for item in devices
              if item.get('isAvailable') and item['name'].startswith('iPhone')]
if not candidates:
    raise SystemExit('Aucun simulateur iPhone disponible. Aucun test simulateur validé.')
print(sorted(candidates, reverse=True)[0][2])
PY
)"
derived="${RUNNER_TEMP:-$PWD/work}/CadenceSimulator"

run_tests() {
  local device="$1" result="$2" label="$3"
  shift 3
  local tests_status=0 attachments_status=0
  xcodebuild -project Cadence.xcodeproj -scheme CadenceExtensions \
    -configuration Debug -destination "platform=iOS Simulator,id=$device" \
    -derivedDataPath "$derived" -resultBundlePath "$result" \
    -parallel-testing-enabled NO "$@" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | tee "dist/reports/$label-tests.log" || tests_status=$?
  if [[ -d "$result" ]]; then
    xcrun xcresulttool export attachments --path "$result" \
      --output-path "dist/test-attachments/$label" 2>&1 | tee "dist/reports/test-attachments-$label.log" || attachments_status=$?
  fi
  # Copier uniquement les images reliées aux noms du test par le manifeste réel.
  # Les pièces jointes et manifestes bruts restent toujours dans l’archive.
  python3 Scripts/collect_test_screenshots.py dist/test-attachments dist/screenshots dist/reports/screenshot-index.json
  if (( tests_status != 0 )); then return "$tests_status"; fi
  if (( attachments_status != 0 )); then return "$attachments_status"; fi
}

xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl status_bar "$simulator_id" override --time '9:41' --batteryState charged --batteryLevel 100
# Aide exacte du SDK exécuté; API moderne documentée depuis Xcode 16, sans --legacy.
xcrun xcresulttool export attachments --help > dist/reports/xcresult-attachments-help.txt 2>&1
xcrun simctl ui "$simulator_id" appearance light
if [[ "${ONLY_SESSION_PRESENTATION:-false}" == "true" ]]; then
  run_tests "$simulator_id" dist/CadenceUITests.xcresult iphone \
    -only-testing:CadenceUITests/CadenceUITests/testNewSessionSheetAndCancellation
  printf '%s\n' 'Contrôle ciblé de Nouvelle séance, du formulaire et de la confirmation de fin. Les autres parcours ne sont pas exécutés par ce run.' > dist/reports/simulator-status.txt
  exit 0
fi
run_tests "$simulator_id" dist/CadenceUITests.xcresult iphone \
  -skip-testing:CadenceUITests/CadenceUITests/testIPadLandscapeLayout \
  -skip-testing:CadenceUITests/CadenceUITests/testDarkStatistics
xcrun simctl ui "$simulator_id" appearance dark
run_tests "$simulator_id" dist/CadenceDarkUITests.xcresult dark \
  -only-testing:CadenceUITests/CadenceUITests/testDarkStatistics
xcrun simctl ui "$simulator_id" appearance light

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
  run_tests "$ipad_id" dist/CadenceIPadUITests.xcresult ipad \
    -only-testing:CadenceUITests/CadenceUITests/testIPadLandscapeLayout
  printf '%s\n' "Test iPad paysage exécuté sur $ipad_id. Captures nommées par XCTest, sans navigation URL externe." > dist/reports/ipad-status.txt
else
  printf '%s\n' 'Aucun simulateur iPad disponible : aucune capture iPad et aucun test iPad validé.' > dist/reports/ipad-status.txt
fi
printf '%s\n' 'Navigation vérifiée par XCTest dans les vrais onglets; images exportées depuis les pièces jointes des tests. Voir screenshot-index.json pour leur provenance. Aucun test physique iPhone/iPad.' > dist/reports/simulator-status.txt
