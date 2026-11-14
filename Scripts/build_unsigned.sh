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
  shasum -a 256 "dist/$scheme-unsigned.ipa" > "dist/reports/$scheme-sha256.txt"
done
