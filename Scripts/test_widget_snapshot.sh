#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks_root="${RUNNER_TEMP:-$PWD/work}/CadenceWidgetChecks"
mkdir -p "$checks_root" dist/reports
# No CADENCE_KEYCHAIN_SHARED flag: these checks never access the host keychain.
xcrun swiftc Shared/SignedKeychainGroups.swift Shared/WidgetSnapshot.swift Tests/WidgetSnapshotChecks/main.swift -o "$checks_root/WidgetSnapshotChecks"
"$checks_root/WidgetSnapshotChecks" | tee dist/reports/widget-snapshot-tests.log
