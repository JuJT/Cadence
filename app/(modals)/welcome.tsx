import { useAccountStore } from "@/stores/account";
import { useSettingsStore } from "@/stores/settings";
import Stack from "@/ui/components/Stack";
import Button from "@/ui/new/Button";
import Divider from "@/ui/new/Divider";
import Typography from "@/ui/new/Typography";
import { Papicons } from "@getpapillon/papicons";
import { useRouter, useTheme } from "expo-router";
import React, { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Alert, Image, Platform, TouchableOpacity, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import * as ImagePicker from "expo-image-picker"
import { Dynamic } from "@/ui/components/Dynamic";
import { PapillonAppearIn, PapillonAppearOut } from "@/ui/utils/Transition";
import ActivityIndicator from "@/ui/components/ActivityIndicator";
import { Stack as ExpoStack } from 'expo-router';
import { AppColors, Colors } from "@/utils/colors";
import { shouldOfferTimetableAlerts } from "@/services/cadenza/timetable-alerts";
import { FadeInRight, FadeOutLeft } from "react-native-reanimated";
import { useTravelStore } from "@/stores/travel";

const WelcomeModal: React.FC = () => {
  const { t } = useTranslation();
  const theme = useTheme();
  const router = useRouter();
  const store = useAccountStore.getState();
  const accounts = useAccountStore((state) => state.accounts);
  const lastUsedAccount = useAccountStore((state) => state.lastUsedAccount);
  const settingsStore = useSettingsStore(state => state.personalization);
  const mutateProperty = useSettingsStore(state => state.mutateProperty);
  const insets = useSafeAreaInsets();

  const account = accounts.find((a) => a.id === lastUsedAccount);

  const [step, setStep] = useState<"photo" | "color">("photo");

  useEffect(() => {
    if (!account) {
      router.dismissAll();
    }
  }, [account, router]);

  const finishWelcome = async () => {
    if (account && !useTravelStore.getState().profiles[account.id]?.configured) {
      router.replace({ pathname: "/(modals)/travel", params: { onboarding: "1" } });
      return;
    }
    if (await shouldOfferTimetableAlerts().catch(() => false)) {
      router.replace({ pathname: "/(modals)/cadenza-alerts", params: { onboarding: "1" } });
    } else {
      router.dismissAll();
    }
  };

  const goNextStep = () => {
    if (step === "photo") {
      setStep("color");
    } else {
      void finishWelcome();
    }
  };

  const goPrevStep = () => {
    if (step === "color") {
      setStep("photo");
    }
  };

  const ignoreSetup = () => {
    Alert.alert(
      t("Welcome_Setup_Skip_Title"),
      t("Welcome_Setup_Skip_Description"),
      [
        {
          text: t("CANCEL_BTN"),
          style: "cancel"
        },
        {
          text: t("Welcome_Setup_Skip_Action"),
          style: "destructive",
          onPress: () => { void finishWelcome(); }
        }
      ]
    );
  };

  const [isAddingPhoto, setIsAddingPhoto] = useState<boolean>(false);

  const profilePictureUrl = useMemo(() => {
    if (!account) return null;
    return account.customisation?.profilePicture ? `data:image/png;base64,${account.customisation.profilePicture}` : null;
  }, [account]);
  const hasAPhotoBeenAdded = profilePictureUrl !== null;

  const updateProfilePictureFromLibrary = async () => {
    setIsAddingPhoto(true);
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.5,
      base64: true
    });

    setIsAddingPhoto(false);

    if (!result.canceled) {
      const b64 = result.assets[0].base64 ?? "";
      store.setAccountProfilePicture(lastUsedAccount, b64);
    }
  }

  const selectedColor = settingsStore.colorSelected ?? Colors.BLUE;

  return (
    <View style={{ flex: 1 }}>
      <ExpoStack.Toolbar placement="left">
        {step !== "photo" && (
          <ExpoStack.Toolbar.Button icon={
            Platform.select({
              ios: "chevron.backward"
            })
          } onPress={() => {
            goPrevStep();
          }} />
        )}
      </ExpoStack.Toolbar>

      <View style={{ flex: 1, justifyContent: "center", alignItems: "center", padding: 24 }}>
        <Stack animated hAlign="center">
          <Image
            source={profilePictureUrl ? { uri: profilePictureUrl } : require("@/assets/images/icon.png")}
            style={{ width: 92, height: 92, borderRadius: 64, marginBottom: 24, borderWidth: 1, borderColor: theme.colors.border }}
          />

          <Typography variant="title" align="center" weight="medium" color="textSecondary">
            {t("Welcome_Greeting", { name: account?.firstName || t("ONBOARDING_DEFAULT_USER_FIRSTNAME") })}
          </Typography>
          <Typography variant="h3" align="center">
            {t("Welcome_Title")}
          </Typography>

          <Divider ghost height={16} />
        </Stack>

        <Dynamic animated>
          {step === "photo" && (
            <Stack entering={FadeInRight.springify()} exiting={FadeOutLeft.springify()} animated hAlign="center" gap={12}>
              <Typography variant="body" align="center" color="textSecondary">
                {t("Welcome_ProfilePicture_Description")}
              </Typography>

              <Button
                label={t("Welcome_ProfilePicture_Action")}
                variant="outlined"
                height={42}
                leading={
                  <Dynamic animated key={isAddingPhoto ? "load_lead:btn" : hasAPhotoBeenAdded ? "check_lead:btn" : "camera_lead:btn"}>
                    {isAddingPhoto ? (
                      <ActivityIndicator size={24} />
                    ) : (
                      <Papicons name={hasAPhotoBeenAdded ? "check" : "camera"} fill={theme.colors.primary} />
                    )}
                  </Dynamic>
                }
                onPress={() => {
                  updateProfilePictureFromLibrary();
                }}
              />
            </Stack>
          )}

          {step === "color" && (
            <Stack entering={FadeInRight.springify()} exiting={FadeOutLeft.springify()} animated hAlign="center" gap={12}>
              <Typography variant="body" align="center" color="textSecondary">
                {t("Welcome_Color_Description")}
              </Typography>

              <Stack direction="horizontal" hAlign="center" gap={3}>
                {AppColors.map((color) => (
                  <TouchableOpacity
                    key={color.colorEnum}
                    onPress={() => {
                      mutateProperty('personalization', { colorSelected: color.colorEnum });
                    }}
                    style={{
                      borderColor: selectedColor === color.colorEnum ? color.mainColor : "transparent",
                      borderRadius: 48,
                      padding: 4,
                      borderWidth: 3,
                    }}
                  >
                    <View
                      style={{
                        width: 32,
                        height: 32,
                        borderRadius: 24,
                        backgroundColor: color.mainColor,
                        borderWidth: selectedColor === color.colorEnum ? 2 : 0,
                        borderColor: theme.colors.primary
                      }}
                    />
                  </TouchableOpacity>
                ))}
              </Stack>
            </Stack>
          )}
        </Dynamic>
      </View>

      <View style={{ justifyContent: "center", alignItems: "center", padding: 16, paddingBottom: insets.bottom + 24, gap: 12 }}>
        <Dynamic animated>
          <Button label={t("ONBOARDING_CONTINUE")} variant="primary" fullWidth onPress={goNextStep} />
        </Dynamic>

        {(step === "photo" || Platform.OS !== "ios") && (
          <Dynamic animated>
            <Button label={t("Welcome_Setup_Skip_Title")} variant="secondary" fullWidth onPress={ignoreSetup} />
          </Dynamic>
        )}
      </View>
    </View>
  );
};

export default WelcomeModal;
