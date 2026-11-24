const fs = require("node:fs");
const path = require("node:path");
const { withFinalizedMod } = require("expo/config-plugins");

module.exports = function withCadenzaStudyWidgets(config) {
  return withFinalizedMod(config, ["ios", mod => {
    const { projectRoot, platformProjectRoot } = mod.modRequest;
    const extension = path.join(platformProjectRoot, "PapillonWidgets", "PapillonWidgets.swift");
    const generated = fs.readFileSync(extension, "utf8");
    const originalWidgetEntry = "PapillonWidgetBundle().body";
    if (!generated.includes(originalWidgetEntry)) {
      throw new Error("The PapillonKit widget entry has changed; review Cadenza's widget integration.");
    }
    if (!generated.includes("CadenzaStudyTodayWidget()")) {
      const contents = [
        generated.replace(originalWidgetEntry, `${originalWidgetEntry}\n        CadenzaStudyTodayWidget()\n        CadenzaStudyWeekWidget()\n        CadenzaRevisionLiveActivity()`),
        fs.readFileSync(path.join(projectRoot, "modules/cadenza-study/ios/CadenzaStudySurface.swift"), "utf8"),
        fs.readFileSync(path.join(projectRoot, "native/cadenza-study-widgets/StudyWidgets.swift"), "utf8"),
      ];
      fs.writeFileSync(extension, contents.join("\n\n"));
    }
    return mod;
  }]);
};
