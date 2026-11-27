import { useTheme } from "expo-router/react-navigation";
import { router, useLocalSearchParams, useNavigation } from "expo-router";
import {
  AccountKind,
  createSessionHandle,
  loginToken,
  SecurityError,
} from "@blockshub/pawnote-lts";
import React, { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Alert, KeyboardAvoidingView } from "react-native";
import Reanimated, { FadeIn, FadeOut } from "react-native-reanimated";
import { formatSchoolName } from '@/utils/format/formatSchoolName';
import WebView from "react-native-webview";
import { WebViewErrorEvent, WebViewMessage, WebViewNavigationEvent } from "react-native-webview/lib/WebViewTypes";

import ActivityIndicator from "@/ui/components/ActivityIndicator";
import Stack from "@/ui/components/Stack";
import Divider from "@/ui/new/Divider";
import Typography from "@/ui/new/Typography";
import { normalizePronoteAddress } from "@/utils/pronote/address";
import { setPendingPronoteChallenge } from "@/utils/pronote/challenge";
import { storePronoteLogin } from "@/utils/pronote/sign-in";
import { customFetcher } from "@/utils/pronote/fetcher";
import uuid from "@/utils/uuid/uuid";

import OnboardingWebView from "../../components/OnboardingWebView";
import Button from "@/ui/new/Button";
import SafeHorizontalView from "@/ui/components/SafeHorizontalView";

export default function PronoteENTLogin() {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const navigation = useNavigation();
  const { url: givenAddress, schoolName, relinkAccountId, relinkServiceId, relinkDeviceUUID } = useLocalSearchParams<{
    url?: string;
    schoolName?: string;
    relinkAccountId?: string;
    relinkServiceId?: string;
    relinkDeviceUUID?: string;
  }>();
  const url = normalizePronoteAddress(givenAddress ?? "");
  const mobileURL = url ? url + "/mobile.eleve.html" : "";

  // UI Logic
  const [browserVisible, setBrowserVisible] = React.useState(false);

  const [hasLoadingBeenTooLong, setHasLoadingBeenTooLong] = useState(false);
  const [loadingHidden, setLoadingHidden] = useState(false);

  useEffect(() => {
    navigation.setOptions({ headerShown: false });
  }, []);

  useEffect(() => {
    if (browserVisible) {
      setHasLoadingBeenTooLong(false);
      return;
    }

    const timeout = setTimeout(() => {
      setHasLoadingBeenTooLong(true);
    }, 15000);

    return () => clearTimeout(timeout);
  }, [browserVisible]);

  const webViewRef = useRef<WebView>(null);

  // Login logic
  const infoMobileURL = url + "/InfoMobileApp.json?id=0D264427-EEFC-4810-A9E9-346942A862A4";

  const [deviceUUID] = useState(() => relinkDeviceUUID && /^[a-z0-9-]{16,64}$/i.test(relinkDeviceUUID) ? relinkDeviceUUID : uuid());
  const received = useRef(false);
  const alive = useRef(true);
  const hasShownConnectionError = useRef(false);

  useEffect(() => {
    alive.current = true;
    return () => { alive.current = false; };
  }, []);

  const PRONOTE_COOKIE_EXPIRED = new Date(0).toUTCString();
  const PRONOTE_COOKIE_VALIDATION_EXPIRES = new Date(
    new Date().getTime() + 5 * 60 * 1000,
  ).toUTCString();
  const PRONOTE_COOKIE_LANGUAGE_EXPIRES = new Date(
    new Date().getTime() + 365 * 24 * 60 * 60 * 1000,
  ).toUTCString();

  const INJECT_PRONOTE_HOOK_DEFINITION = `
    window.hookAccesDepuisAppli = function() {
      this.passerEnModeValidationAppliMobile('', '${deviceUUID}');
    };
    true;
    `.trim();

  const INJECT_PRONOTE_INITIAL_LOGIN_HOOK = `
    window.hookAccesDepuisAppli = function() {
      this.passerEnModeValidationAppliMobile('', '${deviceUUID}');
    };
    try {
          window.GInterface.passerEnModeValidationAppliMobile('', '${deviceUUID}', '', '', '{"model": "random", "platform": "android"}');
    } catch (e) {
    }
    `.trim();

  const INJECT_PRONOTE_JSON = `
      (function () {
        try {
          const json = JSON.parse(document.body.innerText);
          const lJetonCas = !!json && !!json.CAS && json.CAS.jetonCAS;
          
          if (!!lJetonCas) {
            document.cookie = "appliMobile=; expires=${PRONOTE_COOKIE_EXPIRED}";
            document.cookie = "validationAppliMobile=" + lJetonCas + "; expires=${PRONOTE_COOKIE_VALIDATION_EXPIRES}";
            document.cookie = "uuidAppliMobile=${deviceUUID}; expires=${PRONOTE_COOKIE_VALIDATION_EXPIRES}";
            // 1036 = French
            document.cookie = "ielang=1036; expires=${PRONOTE_COOKIE_LANGUAGE_EXPIRES}";
          } else {
            document.cookie = "appliMobile=1; expires=${PRONOTE_COOKIE_VALIDATION_EXPIRES}";
            document.cookie = "ielang=1036; expires=${PRONOTE_COOKIE_LANGUAGE_EXPIRES}";
          }

          window.location.assign(${JSON.stringify(mobileURL + "?fd=1")});
        }
        catch {
          window.ReactNativeWebView.postMessage(JSON.stringify({ type: "pronote.connectionError" }));
        }
      })();
    `.trim();

  const INJECT_PRONOTE_CURRENT_LOGIN_STATE = `
    (function () {
      setInterval(function() {
        const state = window && window.loginState ? window.loginState : void 0;

        if (state && state.status === 0 && typeof state.login === 'string' && typeof state.mdp === 'string') {
          window.ReactNativeWebView.postMessage(JSON.stringify({
            type: 'pronote.loginState',
            data: { status: state.status, login: state.login, mdp: state.mdp }
          }));
        }
      }, 1000);
    })();
    `.trim();

  const INJECT_PRONOTE_CONNECTION_ERROR_WATCHER = `
    (function () {
      if (window.__pronoteConnImpossibleWatcherInstalled) return;
      window.__pronoteConnImpossibleWatcherInstalled = true;

      function hasConnectionError() {
        const nodes = document.querySelectorAll('div');
        for (let i = 0; i < nodes.length; i += 1) {
          const node = nodes[i];
          const raw = node && node.textContent ? node.textContent : "";
          const text = raw
            .normalize("NFD")
            .replace(/[\\u0300-\\u036f]/g, "")
            .toLowerCase()
            .trim();

          if (!text) continue;
          if (text.includes("connexion impossible") || text.includes("erreur")) {
            return true;
          }
        }

        return false;
      }

      function notifyIfNeeded() {
        if (window.__pronoteConnImpossibleSent) return;
        if (!hasConnectionError()) return;
        window.__pronoteConnImpossibleSent = true;
        window.ReactNativeWebView.postMessage(JSON.stringify({
          type: 'pronote.connectionError'
        }));
      }

      notifyIfNeeded();
      setInterval(notifyIfNeeded, 1000);

      const observer = new MutationObserver(notifyIfNeeded);
      observer.observe(document.documentElement || document.body, { childList: true, subtree: true, characterData: true });
    })();
    `.trim();

  function onMobilePage(address: string) {
    try {
      const page = new URL(address);
      return page.origin + page.pathname === mobileURL;
    } catch {
      return false;
    }
  }

  function showConnectionError() {
    setBrowserVisible(true);
    if (hasShownConnectionError.current) return;
    hasShownConnectionError.current = true;
    const fallback = url && {
      text: "Identifiants PRONOTE",
      onPress: () => router.replace({
        pathname: "/(onboarding)/services/pronote/credentials",
        params: { url, relinkAccountId, relinkServiceId, relinkDeviceUUID },
      }),
    };
    Alert.alert(
      "Portail PRONOTE indisponible",
      "Ce portail n’a pas transmis de connexion PRONOTE Mobile. Essayez les identifiants PRONOTE ou le QR code de l’espace Élèves.",
      fallback ? [fallback, { text: "Fermer", style: "cancel" }] : undefined,
    );
  }

  const onWebviewMessage = async ({ nativeEvent }: { nativeEvent: WebViewMessage }) => {
    if (!url || received.current) return;
    const isMobile = onMobilePage(nativeEvent.url);
    if (!isMobile && nativeEvent.url !== infoMobileURL) return;
    let message: { type?: string; data?: { status?: unknown; login?: unknown; mdp?: unknown } };
    try {
      message = JSON.parse(nativeEvent.data);
    } catch {
      return;
    }
    if (message.type === "pronote.connectionError") {
      showConnectionError();
      return;
    }
    if (!isMobile || message.type !== "pronote.loginState" || message.data?.status !== 0 ||
        typeof message.data.login !== "string" || typeof message.data.mdp !== "string" ||
        !message.data.login || !message.data.mdp) return;
    received.current = true;
    const session = createSessionHandle(customFetcher);
    try {
      const refresh = await loginToken(session, {
        url, kind: AccountKind.STUDENT, username: message.data.login, token: message.data.mdp, deviceUUID,
      });
      if (!alive.current) return;
      storePronoteLogin(session, refresh, deviceUUID,
        relinkAccountId && relinkServiceId ? { accountId: relinkAccountId, serviceId: relinkServiceId } : undefined);
      router.dismissTo("/");
    } catch (error) {
      if (!alive.current) return;
      if (error instanceof SecurityError) {
        setPendingPronoteChallenge({ session, error, deviceUUID, relinkAccountId, relinkServiceId });
        router.push("/(onboarding)/services/pronote/challenge");
        return;
      }
      received.current = false;
      showConnectionError();
    }
  };

  const onWebviewLoadEnd = (event: WebViewNavigationEvent | WebViewErrorEvent) => {
    const address = event.nativeEvent.url;
    setBrowserVisible(address !== infoMobileURL);
    if (address === infoMobileURL) {
      webViewRef.current?.injectJavaScript(INJECT_PRONOTE_JSON);
    } else if (onMobilePage(address)) {
      webViewRef.current?.injectJavaScript(INJECT_PRONOTE_INITIAL_LOGIN_HOOK);
      webViewRef.current?.injectJavaScript(INJECT_PRONOTE_CONNECTION_ERROR_WATCHER);
      webViewRef.current?.injectJavaScript(INJECT_PRONOTE_CURRENT_LOGIN_STATE);
    }
  };

  if (!url) {
    return <SafeHorizontalView base={20} style={{ flex: 1, justifyContent: "center", gap: 16 }}>
      <Typography variant="h4">L’adresse du portail PRONOTE doit commencer par https://.</Typography>
      <Button label="Retour" onPress={() => router.back()} />
    </SafeHorizontalView>;
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior="padding" keyboardVerticalOffset={20}>
      {!browserVisible && !loadingHidden &&
        <Reanimated.View
          style={{
            height: "100%",
            width: "100%",
            position: "absolute",
            backgroundColor: colors.card,
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
          }}
          entering={FadeIn.duration(130)}
          exiting={FadeOut.duration(130)}
        >
          <SafeHorizontalView base={20} style={{ width: "100%" }}>
            <Stack vAlign="center" hAlign="center" width={"100%"} gap={3} padding={[0, 20]}>
              <ActivityIndicator />
              <Divider height={12} ghost />
              <Typography align="center" variant="h4">{t("ONBOARDING_LOGIN_TO")} {schoolName ? formatSchoolName(schoolName) : t("ONBOARDING_YOUR_SCHOOL")}</Typography>
              <Typography align="center" variant="body" color="textSecondary">{t("ONBOARDING_SCHOOLS_SEARCHING_HINT")}</Typography>

              {hasLoadingBeenTooLong && (
                <Button label="Masquer" variant="text" onPress={() => setLoadingHidden(true)} />
              )}
            </Stack>
          </SafeHorizontalView>
        </Reanimated.View>
      }

      <OnboardingWebView
        source={{ uri: infoMobileURL }}
        webViewRef={webViewRef}
        incognito={true}
        userAgent="Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
        onMessage={onWebviewMessage}
        onLoadEnd={onWebviewLoadEnd}
        injectedJavaScriptBeforeContentLoaded={INJECT_PRONOTE_HOOK_DEFINITION}
        startInLoadingState
        onOpenWindow={(evt) => {
          const target = evt.nativeEvent.targetUrl;
          if (!target.startsWith("https://")) return;
          webViewRef.current?.stopLoading();
          webViewRef.current?.injectJavaScript("window.location.assign(" + JSON.stringify(target) + ");");
        }}
        injectedJavaScript={`
        var meta = document.createElement('meta');
        meta.setAttribute('name', 'viewport');
        meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');
        document.getElementsByTagName('head')[0].appendChild(meta);
        `}
      />

    </KeyboardAvoidingView>
  )
}
