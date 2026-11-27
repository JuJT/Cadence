import { AccountKind, createSessionHandle, loginCredentials, SecurityError } from "@blockshub/pawnote-lts";
import { router, useLocalSearchParams } from "expo-router";
import { useHeaderHeight, useTheme } from "expo-router/react-navigation";
import { useRef, useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, ScrollView, StyleSheet, TextInput } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";
import { normalizePronoteAddress } from "@/utils/pronote/address";
import { setPendingPronoteChallenge } from "@/utils/pronote/challenge";
import { customFetcher } from "@/utils/pronote/fetcher";
import { storePronoteLogin } from "@/utils/pronote/sign-in";
import uuid from "@/utils/uuid/uuid";

export default function PronoteCredentials() {
  const { url, relinkAccountId, relinkServiceId, relinkDeviceUUID } = useLocalSearchParams<{
    url?: string; relinkAccountId?: string; relinkServiceId?: string; relinkDeviceUUID?: string;
  }>();
  const address = normalizePronoteAddress(url ?? "");
  const header = useHeaderHeight();
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const busy = useRef(false);
  const deviceId = useRef(relinkDeviceUUID || uuid());
  const deviceUUID = deviceId.current;

  async function signIn() {
    if (busy.current || !address || !username.trim() || !password) return;
    busy.current = true;
    setLoading(true);
    const session = createSessionHandle(customFetcher);
    try {
      const refresh = await loginCredentials(session, {
        url: address, username: username.trim(), password, deviceUUID, kind: AccountKind.STUDENT,
      });
      const relink = relinkAccountId && relinkServiceId ? { accountId: relinkAccountId, serviceId: relinkServiceId } : undefined;
      storePronoteLogin(session, refresh, deviceUUID, relink);
      setPassword("");
      router.dismissTo("/");
    } catch (error) {
      if (error instanceof SecurityError) {
        setPassword("");
        setPendingPronoteChallenge({ session, error, deviceUUID, relinkAccountId, relinkServiceId });
        router.push("/(onboarding)/services/pronote/challenge");
      } else {
        Alert.alert("Connexion impossible", "Vérifiez vos identifiants PRONOTE. Si votre établissement demande une connexion ENT ou ÉduConnect, utilisez le portail ou le QR code.");
      }
    } finally {
      busy.current = false;
      setLoading(false);
    }
  }

  const field = [styles.field, { color: colors.text, backgroundColor: colors.card, borderColor: colors.border }];
  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.background }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={[styles.content, { paddingTop: header + 20, paddingBottom: insets.bottom + 20 }]}>
        <Typography variant="h2">Identifiants PRONOTE</Typography>
        <Typography color="textSecondary">
          {address ? new URL(address).hostname : "L’adresse PRONOTE de l’établissement doit commencer par https://."}
        </Typography>
        <TextInput accessibilityLabel="Identifiant PRONOTE" placeholder="Identifiant" placeholderTextColor={colors.text}
          value={username} onChangeText={setUsername} editable={!loading} autoCapitalize="none" autoCorrect={false}
          autoComplete="username" textContentType="username" returnKeyType="done" style={field} />
        <TextInput accessibilityLabel="Mot de passe PRONOTE" placeholder="Mot de passe" placeholderTextColor={colors.text}
          value={password} onChangeText={setPassword} editable={!loading} secureTextEntry
          autoComplete="current-password" textContentType="password" returnKeyType="go" onSubmitEditing={() => void signIn()} style={field} />
        <Button label={loading ? "Connexion…" : "Se connecter"} disabled={loading || !address || !username.trim() || !password} onPress={() => void signIn()} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
const styles = StyleSheet.create({
  content: { paddingHorizontal: 20, gap: 14 },
  field: { minHeight: 48, padding: 12, fontSize: 17, borderWidth: 1, borderRadius: 12 },
});
