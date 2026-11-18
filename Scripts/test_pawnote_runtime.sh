#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks_root="${RUNNER_TEMP:-$PWD/work}/CadenzaPawnoteChecks"
mkdir -p "$checks_root" dist/reports
# Test-only JS fixtures and URLProtocol transport: no real school request,
# credentials, Keychain access, personal cookie store or developer account.
xcrun swiftc -swift-version 5 -parse-as-library -D CADENZA_RUNTIME_HARNESS \
  App/Services/PawnoteRuntime.swift Tests/PawnoteRuntimeChecks/main.swift \
  -framework JavaScriptCore -framework Security -o "$checks_root/PawnoteRuntimeChecks"
bundle_args=()
if [[ -f Resources/Pronote/pawnote.bundle.js ]]; then bundle_args+=("$PWD/Resources/Pronote/pawnote.bundle.js"); fi
"$checks_root/PawnoteRuntimeChecks" "${bundle_args[@]}" | tee dist/reports/pawnote-runtime-checks.log
