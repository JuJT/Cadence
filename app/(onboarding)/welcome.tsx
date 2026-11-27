import { useIsFocused, useTheme } from "expo-router/react-navigation";
import { useRouter } from "expo-router";
import * as WebBrowser from 'expo-web-browser';
import React from "react";
import { Image, StatusBar, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Reanimated, { FadeIn, FadeOut } from "react-native-reanimated";

import Stack from "@/ui/components/Stack";
import Button from "@/ui/new/Button";
import Divider from "@/ui/new/Divider";
import Typography from "@/ui/new/Typography";
import SafeHorizontalView from "@/ui/components/SafeHorizontalView";
import { LinearGradient } from "expo-linear-gradient";
import { useTranslation } from "react-i18next";

import { consumeSecurityLogoutNotice } from "@/stores/global/encryption";
import { CADENZA_SOURCE } from "@/constants/Cadenza";
import { hideAppSplash } from "@/hooks/useAppInitialization";

export default function Welcome() {
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();
  const router = useRouter();
  const { t } = useTranslation();

  const openHelpWebPage = () => {
    WebBrowser.openBrowserAsync("https://docs.papillon.bzh/support", {
      presentationStyle: WebBrowser.WebBrowserPresentationStyle.PAGE_SHEET
    });
  }

  const openSourceWebPage = () => {
    WebBrowser.openBrowserAsync(CADENZA_SOURCE, {
      presentationStyle: WebBrowser.WebBrowserPresentationStyle.PAGE_SHEET
    });
  }

  const openDevMenu = () => {
    router.push("/devmode");
  }

  React.useEffect(() => {
    if (!consumeSecurityLogoutNotice()) {return;}
    router.navigate({
      pathname: "/alert",
      params: {
        data: JSON.stringify({
          title: t("SecurityLogout_Title"),
          description: t("SecurityLogout_Description"),
          icon: "Lock",
          color: "#0E7CCB",
          customButton: { label: t("SecurityLogout_Button") },
        }),
      },
    });
  }, []);

  const isFocused = useIsFocused();

  return (
    <View
      onLayout={hideAppSplash}
      style={{
        flex: 1,
        backgroundColor: "#06172F",
        display: "flex",
        alignItems: "center",
      }}
    >
      {isFocused && (
        <StatusBar barStyle={"light-content"} animated />
      )}
      {isFocused && (
        <Reanimated.View
          entering={FadeIn.duration(600)}
          exiting={FadeOut.duration(600)}

          style={{
            width: "100%",
            height: "100%",
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 0,
          }}
        >
          <LinearGradient
            colors={["#103773", "#2776F8", "#06172F"]}
            start={{ x: 0.05, y: 0 }}
            end={{ x: 0.8, y: 0.9 }}
            style={{ flex: 1 }}
          />
        </Reanimated.View>
      )}

      <LinearGradient
        colors={[
          "rgba(6, 23, 47, 1)",
          "rgba(0, 0, 0, 0.0)",
          "rgba(0, 0, 0, 0)",
          "rgba(6, 23, 47, 1)",
        ]}
        locations={[0, 0.2, 0.3, 0.7]}
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          zIndex: 1,
          opacity: 0.8,
        }}
      />

      <View style={{ maxWidth: 600 }}>
        <SafeHorizontalView
          base={16}
          style={{
            flex: 1,
            justifyContent: "flex-end",
            alignItems: "center",
            paddingTop: 16,
            gap: 10,
            paddingBottom: insets.bottom + 16,
            zIndex: 99,
            maxWidth: 600,
          }}
        >
          <Image
            source={require("@/assets/images/icon.png")}
            accessibilityIgnoresInvertColors
            style={{ width: 72, height: 72, borderRadius: 18 }}
          />
          <Typography variant="h1" weight="bold" align="center" color="#FFFFFF">
            Cadenza
          </Typography>

          <Typography
            color="#FFFFFF"
            variant="title"
            align="center"
            weight="medium"
            style={{ marginHorizontal: 10, opacity: 0.8 }}
          >
            {t("ONBOARDING_WELCOME_DESCRIPTION")}
          </Typography>

          <Divider height={2} ghost />

          <Button
            label={t("ONBOARDING_WELCOME_LOGIN_WITH")}
            gap={4}
            trailing={
              <Stack direction="horizontal" gap={0}>
                <Image
                  source={require("@/assets/images/service_pronote.png")}
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 32,
                    borderWidth: 3,
                    borderColor: colors.primary,
                    zIndex: 3,
                  }}
                />
                <Image
                  source={require("@/assets/images/service_ed.png")}
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 32,
                    borderWidth: 3,
                    borderColor: colors.primary,
                    marginLeft: -16,
                    zIndex: 2,
                  }}
                />
                <Image
                  source={require("@/assets/images/service_skolengo.png")}
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 32,
                    borderWidth: 3,
                    borderColor: colors.primary,
                    marginLeft: -16,
                    zIndex: 1,
                  }}
                />
              </Stack>
            }
            onPress={() => {
              router.push("./ageSelection");
            }}
            fullWidth
          />
          <Button
            label={t("ONBOARDING_WELCOME_OFFLINE", { defaultValue: "Continuer sans compte scolaire" })}
            onPress={() => router.push("/(onboarding)/offlineAccount")}
            fullWidth
            variant="outlined"
            color="#FFFFFF"
          />
          <Button
            label={t("ONBOARDING_HELP_BTN")}
            onPress={() => {
              openHelpWebPage();
            }}
            fullWidth
            variant="secondary"
            color="#FFFFFF"
          />

          <Divider height={2} ghost />

          <Typography
            color="#FFFFFF88"
            variant="caption"
            align="center"
            style={{ marginHorizontal: 20, opacity: 0.7 }}
            onPress={() => {
              openSourceWebPage();
            }}
            onLongPress={() => {
              openDevMenu();
            }}
          >
            {t("ONBOARDING_WELCOME_SOURCE", { defaultValue: "Sources et licences" })}
          </Typography>
        </SafeHorizontalView>
      </View>
    </View>
  );
}
