import { router, useLocalSearchParams } from "expo-router";
import { useHeaderHeight, useTheme } from "expo-router/react-navigation";
import { useState } from "react";
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, TextInput } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";
import { normalizePronoteAddress } from "@/utils/pronote/address";

export default function PronoteLoginURL() {
  const { prefill, schoolName } = useLocalSearchParams<{ prefill?: string; schoolName?: string }>();
  const header = useHeaderHeight();
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();
  const [url, setUrl] = useState(prefill ?? "");
  const address = normalizePronoteAddress(url);

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.background }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={[styles.content, { paddingTop: header + 20, paddingBottom: insets.bottom + 20 }]}>
        <Typography variant="h2">{schoolName || "Adresse de l’établissement"}</Typography>
        <Typography color="textSecondary">Collez l’adresse HTTPS de l’espace Élèves, puis choisissez votre mode de connexion habituel.</Typography>
        <TextInput accessibilityLabel="Adresse HTTPS PRONOTE" placeholder="https://…" placeholderTextColor={colors.text}
          value={url} onChangeText={setUrl} autoCapitalize="none" autoCorrect={false} autoComplete="url" textContentType="URL" keyboardType="url"
          style={[styles.field, { color: colors.text, backgroundColor: colors.card, borderColor: colors.border }]} />
        {Boolean(url.trim()) && !address && <Typography color="textSecondary">Vérifiez que l’adresse correspond bien à l’espace Élèves.</Typography>}
        <Button label="Identifiants PRONOTE" fullWidth disabled={!address} onPress={() => {
          if (address) router.push({ pathname: "/(onboarding)/services/pronote/credentials", params: { url: address } });
        }} />
        <Button label="ENT ou ÉduConnect" variant="outlined" fullWidth disabled={!address} onPress={() => {
          if (address) router.push({ pathname: "/(onboarding)/services/pronote/browser", params: { url: address, schoolName } });
        }} />
        <Typography color="textSecondary">Le portail ENT doit autoriser la connexion PRONOTE Mobile.</Typography>
        <Button label="Scanner un QR code" variant="text" onPress={() => router.push("/(onboarding)/services/pronote/qrcode")} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
const styles = StyleSheet.create({
  content: { paddingHorizontal: 20, gap: 14 },
  field: { minHeight: 48, padding: 12, fontSize: 17, borderWidth: 1, borderRadius: 12 },
});
