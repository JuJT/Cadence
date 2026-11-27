import PackageJSON from "./package.json" with { type: "json" };

const CADENZA_BUNDLE_IDENTIFIER = "com.cadence.study";
const CADENZA_STORAGE_GROUP = `group.${CADENZA_BUNDLE_IDENTIFIER}`;
const CADENZA_DATABASE_GROUP = `${CADENZA_STORAGE_GROUP}.ios`;

// versionCode: seconds since 2020-01-01 UTC — unique, strictly increasing, well under the 2.1e9 cap
const androidVersionCode = Math.floor(Date.now() / 1000) - 1577836800;

export default {
  expo: {
    name: "Cadenza",
    slug: "cadenza",
    version: PackageJSON.version,
    orientation: "default",
    icon: "./assets/images/icon.png",
    scheme: ["cadence", "izly", "skoapp-prod"],
    platforms: ["ios", "android"],
    userInterfaceStyle: "automatic",
    ios: {
      bundleIdentifier: CADENZA_BUNDLE_IDENTIFIER,
      buildNumber: "11",
      icon: "./assets/app.icon",
      minimumOSVersion: "17.6",
      deploymentTarget: "17.6",
      infoPlist: {
        AppGroupIdentifier: CADENZA_STORAGE_GROUP,
        PapillonKitDatabaseAppGroup: CADENZA_DATABASE_GROUP,
        CFBundleDisplayName: "Cadenza",
        CFBundleName: "Cadenza",
        NSSupportsLiveActivities: true,
        NSCameraUsageDescription: "Cadenza utilise la caméra pour scanner les QR codes de connexion.",
        CFBundleURLTypes: [
          {
            CFBundleURLSchemes: ["cadence", "izly", "skoapp-prod"],
          },
        ],
        CFBundleLocalizations: [
          "fr",
          "en",
          "br",
          "pt",
          "de",
          "es",
          "tr",
          "ja",
          "ru",
          "ko",
          "af",
          "ar",
          "el",
          "hi",
          "nl",
          "pl",
          "ro",
          "sq",
          "uk",
          "vi",
          "bg",
          "bn",
          "cs",
          "da",
          "fi",
          "he",
          "hu",
          "id",
          "no",
          "sk",
          "sv",
          "sw",
          "th",
          "it",
          "fa",
          "ur",
          "ms",
          "hr",
          "et",
        ],
        CADisableMinimumFrameDurationOnPhone: true,
        LSApplicationQueriesSchemes: ["maps"],
      },
      entitlements: {
        "com.apple.security.application-groups": [
          CADENZA_STORAGE_GROUP,
          CADENZA_DATABASE_GROUP,
        ],
      },
      supportsTablet: true,
      config: {
        usesNonExemptEncryption: false,
      },
    },
    android: {
      versionCode: androidVersionCode,
      package: CADENZA_BUNDLE_IDENTIFIER,
      blockedPermissions: [
        "android.permission.READ_MEDIA_IMAGES",
        "android.permission.READ_MEDIA_VIDEO",
      ],
      adaptiveIcon: {
        foregroundImage: "./assets/images/icon.png",
        backgroundColor: "#ffffff",
      },
      supportsTablet: true,
      predictiveBackGestureEnabled: false,
    },
    web: {
      bundler: "metro",
      output: "static",
      favicon: "./assets/images/icon.png",
    },
    plugins: [
      "expo-router",
      "expo-status-bar",
      "expo-font",
      "expo-video",
      [
        "expo-audio",
        {
          enableBackgroundPlayback: false,
        },
      ],
      "expo-localization",
      "expo-asset",
      "@react-native-community/datetimepicker",
      [
        "expo-splash-screen",
        {
          backgroundColor: "#F4F8FF",
          image: "./assets/images/splash-mark.png",
          imageWidth: 136,
          dark: { backgroundColor: "#06172F", image: "./assets/images/splash-mark.png" },
        },
      ],
      [
        "expo-image-picker",
        {
          photosPermission:
            "Cadenza accède à tes photos lorsque tu choisis une image de profil ou une carte de transport.",
          cameraPermission: "Cadenza utilise l’appareil photo quand tu choisis de scanner une carte de transport ou un QR PRONOTE.",
        },
      ],
      "expo-web-browser",
      "expo-secure-store",
      [
        "expo-location",
        {
          locationWhenInUsePermission:
            "Cadenza utilise ta position pour trouver des établissements ou des arrêts quand tu choisis Autour de moi.",
        },
      ],
      [
        "react-native-edge-to-edge",
        {
          android: {
            parentTheme: "Material3",
            enforceNavigationBarContrast: false,
          },
        },
      ],
      [
        "expo-build-properties",
        {
          android: {
            enable16KbPageSizes: true,
          },
          ios: {
            extraPods: [
              { name: "SDWebImage", modular_headers: true },
              { name: "SDWebImageSVGCoder", modular_headers: true },
            ],
            buildReactNativeFromSource: false,
            ccacheEnabled: true,
          },
        },
      ],
      ["@getpapillon/papillonkit", {
        storageAppGroup: CADENZA_STORAGE_GROUP,
        databaseAppGroup: CADENZA_DATABASE_GROUP,
      }],
      "./plugins/with-ios-native-files",
      "./plugins/with-cadenza-study-widgets",
      "./plugins/with-android-gradle-properties-newline",
    ],
    experiments: {
      typedRoutes: true,
    },
  },
};
