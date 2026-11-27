import { Papicons } from "@getpapillon/papicons";
import { useTheme } from "expo-router/react-navigation";
import { CameraView, useCameraPermissions } from "expo-camera";
import * as Haptics from "expo-haptics";
import { router } from "expo-router";
import { createSessionHandle, loginQrCode, SecurityError } from "@blockshub/pawnote-lts";
import React, { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { ActivityIndicator, Alert, Keyboard, KeyboardAvoidingView, Modal, StyleSheet, TextInput, View } from "react-native";
import Reanimated, { FadeInUp, FadeOutUp, LinearTransition } from "react-native-reanimated";
import { SafeAreaView, useSafeAreaInsets } from "react-native-safe-area-context";

import Button from "@/ui/components/Button";
import Icon from "@/ui/components/Icon";
import Typography from "@/ui/components/Typography";
import { isPronotePairingCode, parsePronoteQrCode } from "@/utils/pronote/address";
import { storePronoteLogin } from "@/utils/pronote/sign-in";
import { setPendingPronoteChallenge } from "@/utils/pronote/challenge";
import { customFetcher } from "@/utils/pronote/fetcher";
import uuid from "@/utils/uuid/uuid";
import SafeHorizontalView from "@/ui/components/SafeHorizontalView";

export default function PronoteLoginWithQR() {
  const theme = useTheme();
  const insets = useSafeAreaInsets();

  const { colors } = theme;
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);

  const [keyboardOpen, setKeyboardOpen] = useState(false);

  const [QRValidationCode, setQRValidationCode] = useState("");
  const [pinModalVisible, setPinModalVisible] = useState(false);

  const [loadingModalVisible, setLoadingModalVisible] = useState(false);

  const scanning = useRef(false);
  const busy = useRef(false);
  const alive = useRef(true);
  const [QRData, setQRData] = useState<ReturnType<typeof parsePronoteQrCode>>();

  useEffect(() => {
    alive.current = true;
    return () => { alive.current = false; };
  }, []);

  function resetScan() {
    scanning.current = false;
    setScanned(false);
    setQRData(undefined);
    setQRValidationCode("");
  }

  async function loginQR() {
    if (!QRData || !isPronotePairingCode(QRValidationCode) || busy.current) return;
    busy.current = true;
    setPinModalVisible(false);
    setLoadingModalVisible(true);
    const accountID = uuid();
    const session = createSessionHandle(customFetcher);
    try {
      const refresh = await loginQrCode(session, { qr: QRData, pin: QRValidationCode, deviceUUID: accountID });
      if (!alive.current) return;
      storePronoteLogin(session, refresh, accountID);
      router.dismissTo("/");
    } catch (error) {
      if (!alive.current) return;
      if (error instanceof SecurityError) {
        setPendingPronoteChallenge({ session, error, deviceUUID: accountID });
        router.push("/(onboarding)/services/pronote/challenge");
      } else {
        Alert.alert("Connexion impossible", "Vérifiez le code temporaire et générez un nouveau QR code dans l’espace Élèves de PRONOTE.");
      }
    } finally {
      busy.current = false;
      if (alive.current) {
        setLoadingModalVisible(false);
        resetScan();
      }
    }
  }

  useEffect(() => {
    if (permission && !permission.granted && permission.canAskAgain && permission.status === "undetermined") {
      void requestPermission();
    }
  }, [permission, requestPermission]);

  const handleBarCodeScanned = ({ data }: { data: string }) => {
    if (scanning.current || busy.current) return;
    scanning.current = true;
    setScanned(true);
    const qr = parsePronoteQrCode(data);
    if (!qr) {
      Alert.alert("QR code PRONOTE requis", "Affichez le QR code de connexion depuis l’espace Élèves de votre établissement.", [
        { text: "Réessayer", onPress: resetScan },
      ], { cancelable: true, onDismiss: resetScan });
      return;
    }
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setQRValidationCode("");
    setQRData(qr);
    setPinModalVisible(true);
  };

  const keyboardDidShow = () => setKeyboardOpen(true);
  const keyboardDidHide = () => setKeyboardOpen(false);

  useEffect(() => {
    const keyboardDidShowListener = Keyboard.addListener("keyboardDidShow", keyboardDidShow);
    const keyboardDidHideListener = Keyboard.addListener("keyboardDidHide", keyboardDidHide);

    return () => {
      keyboardDidShowListener?.remove();
      keyboardDidHideListener?.remove();
    };
  }, []);

  const { t } = useTranslation();

  return (
    <SafeAreaView style={styles.container}>
      <Modal
        visible={loadingModalVisible}
        animationType="slide"
        presentationStyle="pageSheet"
      >
        <View
          style={{
            flex: 1,
            backgroundColor: colors.background,
            justifyContent: "center",
            alignItems: "center",
          }}
        >
          <View style={{ flex: 1 }} />

          <ActivityIndicator
            size="large"
          />

          <Typography
            style={{
              fontSize: 18,
              fontWeight: "600",
              color: colors.text,
              marginTop: 16,
            }}
          >
            {t("ONBOARDING_LOADING_LOGIN")}
          </Typography>

          <Typography
            style={{
              fontSize: 16,
              fontWeight: "400",
              color: colors.text,
              marginTop: 4,
            }}
          >
            {t("ONBOARDING_QRCODE_WAIT")}
          </Typography>

          <View style={{ flex: 1 }} />

          <SafeHorizontalView
            base={16}
            style={{
              width: "100%",
              paddingBottom: insets.bottom,
              gap: 8,
            }}
          >
            <Button
              title={t("CANCEL_BTN")}
              onPress={() => {
                setLoadingModalVisible(false);
                router.back();
              }}
            />
          </SafeHorizontalView>
        </View>
      </Modal>

      <Modal
        visible={pinModalVisible}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => {
          setPinModalVisible(false);
          resetScan();
        }}
      >
        <KeyboardAvoidingView
          style={{
            flex: 1,
            backgroundColor: colors.background,
          }}
          behavior="padding"
          keyboardVerticalOffset={insets.top}
        >
          <SafeHorizontalView
            base={20}
            style={{
              justifyContent: "center",
              alignItems: "center",
              marginBottom: 24,
              paddingVertical: 16,
              borderBottomColor: colors.border,
              borderBottomWidth: 0.5,
            }}
          >
            <Typography
              style={{
                fontSize: 17,
                fontWeight: "600",
                color: colors.text,
                textAlign: "center",
              }}
            >
              {t("ONBOARDING_QRCODE_VALIDATION")}
            </Typography>
          </SafeHorizontalView>

          <Reanimated.View
            entering={FadeInUp.duration(250)}
            exiting={FadeOutUp.duration(150)}
            style={{
              zIndex: 9999,
              paddingTop: keyboardOpen ? 20 : 100,
              alignItems: "center",
            }}
            layout={LinearTransition}
          >
            <Typography style={{
              color: colors.text,
              fontSize: 16,
              textAlign: "center",
              marginHorizontal: 24,
              fontWeight: "400",
              width: 300,
              marginBottom: 12
            }}>
              {t("ONBOARDING_PRONOTE_PIN")}
            </Typography>
          </Reanimated.View>

          <View
            style={{
              flex: 1,
              alignItems: "center",
              marginBottom: "7%",
            }}
          >
            <TextInput
              style={{
                width: "90%",
                paddingHorizontal: 20,
                paddingVertical: 15,
                backgroundColor: colors.card,
                borderRadius: 12,
                fontSize: 24,
                color: colors.text,
                textAlign: "center",
                borderColor: colors.border,
                borderWidth: 2,
                fontWeight: "500",
              }}
              placeholderTextColor={colors.text}
              placeholder="••••"
              keyboardType="number-pad"
              maxLength={4}
              secureTextEntry
              value={QRValidationCode}
              onChangeText={(text) => setQRValidationCode(text.replace(/[^0-9]/g, ""))}
              autoFocus
            />
          </View>

          <SafeHorizontalView
            base={16}
            style={{
              width: "100%",
              paddingBottom: insets.bottom + 16,
              gap: 8,
            }}
          >
            <Button
              title={t("CONFIRM_BTN")}
              disabled={!isPronotePairingCode(QRValidationCode)}
              onPress={() => void loginQR()}
            />
            <Button
              title={t("CANCEL_BTN")}
              variant="outline"
              onPress={() => {
                setPinModalVisible(false);
                resetScan();
              }}
            />
          </SafeHorizontalView>
        </KeyboardAvoidingView>
      </Modal>

      <View style={[styles.explainations,
        { top: insets.top + 48 + 10 }
      ]}>
        <Icon size={40} fill={"white"} papicon>
          <Papicons name="QrCode" />
        </Icon>
        <Typography style={styles.title}>
          {t("ONBOARDING_LOGIN_TO")} PRONOTE
        </Typography>
        <Typography style={styles.text}>
          {t("ONBOARDING_SCAN_QRCODE")}
        </Typography>
        {permission && !permission.granted && (
          <>
            <Typography style={styles.text}>Autorisez la caméra dans les réglages de Cadenza pour scanner le QR code.</Typography>
            {permission.canAskAgain && <Button title="Autoriser la caméra" onPress={() => void requestPermission()} />}
            <Button title="Choisir une autre méthode" onPress={() => router.back()} />
          </>
        )}
      </View>

      {permission?.granted && (
        <>
          <CameraView
            facing="back"
            barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
            onBarcodeScanned={scanned ? undefined : handleBarCodeScanned}
            style={StyleSheet.absoluteFill}
          />
          <View pointerEvents="none" style={styles.transparentSquareBorder} />
        </>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    backgroundColor: "black",
  },
  transparentSquareBorder: {
    position: "absolute",
    width: 300,
    height: 300,
    backgroundColor: "transparent",
    borderWidth: 2,
    borderColor: "#fff",
    borderRadius: 30,
    borderCurve: "continuous",
    alignSelf: "center",
    top: "35%",
  },

  explainations: {
    position: "absolute",
    alignItems: "center",
    justifyContent: "center",
    marginHorizontal: 24,
    gap: 4,
    zIndex: 9999,
  },
  title: {
    fontSize: 18,
    fontWeight: "600",
    color: "white",
    textAlign: "center",
  },
  text: {
    fontSize: 16,
    fontWeight: "400",
    color: "white",
    textAlign: "center",
    opacity: 0.8,
  },
});
