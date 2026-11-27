import { nativeApplicationVersion, nativeBuildVersion } from "expo-application";
import Constants from "expo-constants";

import packageJson from "@/package.json";

export const installedCadenzaVersion = nativeApplicationVersion ?? Constants.expoConfig?.version ?? packageJson.version;
export const installedCadenzaBuild = nativeBuildVersion ?? Constants.expoConfig?.ios?.buildNumber;
export const installedCadenzaVersionLabel = installedCadenzaBuild
  ? `Version ${installedCadenzaVersion} · build ${installedCadenzaBuild}`
  : `Version ${installedCadenzaVersion}`;
