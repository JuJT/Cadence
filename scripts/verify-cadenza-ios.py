import json
import plistlib
import subprocess
import sys
from pathlib import Path


def verify(app, bundle, version, build, report):
    def check(condition, message):
        if not condition:
            raise SystemExit(message)

    def inspect_bundle(path, expected_identifier):
        info = plistlib.loads((path / "Info.plist").read_bytes())
        check(info["CFBundleIdentifier"] == expected_identifier, f"Identifiant inattendu dans {path.name}")
        check(info["CFBundleShortVersionString"] == version, f"Version inattendue dans {path.name}")
        check(not build or info["CFBundleVersion"] == build, f"Build inattendu dans {path.name}")
        check(not (path / "embedded.mobileprovision").exists(), f"Profil Apple inattendu dans {path.name}")
        binary = path / info["CFBundleExecutable"]
        architectures = subprocess.check_output(["lipo", "-archs", binary], text=True).split()
        check("arm64" in architectures, f"Architecture iPhone absente dans {path.name}")
        return {
            "path": path.name,
            "identifier": info["CFBundleIdentifier"],
            "displayName": info.get("CFBundleDisplayName"),
            "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"],
            "minimumOS": info.get("MinimumOSVersion"),
            "liveActivities": info.get("NSSupportsLiveActivities", False),
            "architectures": architectures,
        }

    main = inspect_bundle(app, bundle)
    if build:
        check(main["displayName"] == "Cadenza", "Nom d’application Cadenza absent.")
        check(main["liveActivities"], "Live Activities désactivées dans l’IPA.")
    check((app / "main.jsbundle").is_file(), "Bundle JavaScript Release absent de l’IPA.")
    plugins = list((app / "PlugIns").glob("*.appex"))
    check(len(plugins) == 1, f"Une extension Widgets était attendue, {len(plugins)} trouvée(s).")
    widget = inspect_bundle(plugins[0], bundle + ".widgets")
    report.write_text(json.dumps({"app": main, "widgets": widget, "appleProvisioning": False},
                                 ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        raise SystemExit("Usage: verify-cadenza-ios.py APP BUNDLE VERSION BUILD RAPPORT")
    _, app_path, expected_bundle, expected_version, expected_build, report_path = sys.argv
    verify(Path(app_path), expected_bundle, expected_version, expected_build, Path(report_path))
