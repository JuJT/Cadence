#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/reports
build_root="${RUNNER_TEMP:-$PWD/work}/CadenceDevice"
schemes=(CadenceSpike Cadence CadenceExtensions)
if [[ "${INCLUDE_SHARED:-false}" == "true" ]]; then schemes+=(CadenceShared); fi
for scheme in "${schemes[@]}"; do
  derived="$build_root/$scheme"
  xcodebuild -project Cadence.xcodeproj -scheme "$scheme" \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' build 2>&1 | tee "dist/reports/$scheme-build.log"
  app="$derived/Build/Products/Release-iphoneos/Cadence.app"
  test -d "$app"
  # XcodeGen target presets can override project-level device families.
  # Check the compiled bundles before publishing an iPhone-only delivery.
  python3 - "$app" <<'PY'
import plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
for bundle in [app, *sorted((app / 'PlugIns').glob('*.appex'))]:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    assert info.get('UIDeviceFamily') == [1], (bundle.name, info.get('UIDeviceFamily'))
    assert info.get('CFBundleDisplayName') == 'Cadenza', bundle.name
    assert info.get('CFBundleName') == 'Cadenza', bundle.name
print('Cadenza: compiled app and extensions target iPhone only.')
PY
  if [[ "$scheme" == "CadenceExtensions" || "$scheme" == "CadenceShared" ]]; then
    app_signing_source="Config/CadenceAppKeychain.entitlements"
    widget_signing_source="Config/CadenceKeychain.entitlements"
    if [[ "$scheme" == "CadenceShared" ]]; then
      app_signing_source="Config/CadenceShared.entitlements"
      widget_signing_source="Config/CadenceShared.entitlements"
    fi
    app_signing_intent="$derived/Cadence-app-signing-intent.plist"
    widget_signing_intent="$derived/Cadence-widget-signing-intent.plist"
    # A local ad-hoc signature only preserves the requested capabilities for the
    # re-signer. UNSIGNED00 is a declared placeholder, NEVER an Apple Team ID.
    # No profile/certificate is supplied and this IPA still cannot install as-is.
    python3 Scripts/prepare_signing_intent.py "$app_signing_source" "$app_signing_intent" --bundle-info "$app/Info.plist"
    python3 Scripts/prepare_signing_intent.py "$widget_signing_source" "$widget_signing_intent" --bundle-info "$app/PlugIns/CadenceWidgets.appex/Info.plist"
    cp "$app_signing_intent" "$app/CadenceSigningIntent.plist"
    cp "$widget_signing_intent" "$app/PlugIns/CadenceWidgets.appex/CadenceSigningIntent.plist"
    /usr/bin/codesign --force --sign - --generate-entitlement-der --entitlements "$widget_signing_intent" "$app/PlugIns/CadenceWidgets.appex"
    /usr/bin/codesign --force --sign - --generate-entitlement-der --entitlements "$app_signing_intent" "$app"
    /usr/bin/codesign -d --entitlements :- "$app" > "dist/reports/$scheme-signing-intent.plist" 2>/dev/null
    /usr/bin/codesign -d --entitlements :- "$app/PlugIns/CadenceWidgets.appex" > "dist/reports/$scheme-widget-signing-intent.plist" 2>/dev/null
  fi
  python3 Scripts/inspect_bundle.py "$app" "dist/reports/$scheme-bundle.json"
  if [[ "$scheme" != "Cadence" ]]; then
    test -d "$app/PlugIns/CadenceWidgets.appex"
  else
    test ! -d "$app/PlugIns/CadenceWidgets.appex"
  fi
  xcrun swift Scripts/render_bundle_report.swift "dist/reports/$scheme-bundle.json" "dist/reports/$scheme-bundle.png"
  package_dir="$build_root/$scheme-package"
  ipa_path="$PWD/dist/$scheme-unsigned.ipa"
  mkdir -p "$package_dir/Payload"
  ditto "$app" "$package_dir/Payload/Cadence.app"
  # Le dossier dérivé est propre à ce scheme et à ce run.
  (cd "$package_dir" && /usr/bin/zip -qry "$ipa_path" Payload)
  /usr/bin/unzip -t "dist/$scheme-unsigned.ipa" > "dist/reports/$scheme-zip-check.txt"
  python3 Scripts/inspect_ipa.py "dist/$scheme-unsigned.ipa" --output "dist/reports/$scheme-ipa-signing.json"
  if [[ "$scheme" == "CadenceExtensions" ]]; then
    python3 - "dist/reports/$scheme-ipa-signing.json" <<'PY'
import json, sys
from pathlib import Path
auth = json.loads(Path(sys.argv[1]).read_text())['authIsolation']
assert auth['privateAppGroupPresent'] and auth['privateAppGroupIsDefault'], 'Private app keychain group missing'
assert auth['extensionEntitlementsReadable'] and not auth['extensionHasAppPrivateGroup'], 'Widget must not access app credentials'
assert auth['isolatedInExecutableMetadata'], 'Auth keychain separation not established in metadata'
assert auth['templateMetadataOnly'] and not auth['readyForPhysicalPrivateStorageTest'], 'Unsigned metadata must not claim Apple provisioning'
print('Cadenza: private app auth group and widget summary group are separated in unsigned metadata.')
PY
  fi
  shasum -a 256 "dist/$scheme-unsigned.ipa" > "dist/reports/$scheme-sha256.txt"
done
