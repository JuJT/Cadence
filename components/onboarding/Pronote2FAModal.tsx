import { DoubleAuthMode, SecurityError, SessionHandle } from "@blockshub/pawnote-lts";
import * as Device from "expo-device";
import { router } from "expo-router";
import { useHeaderHeight, useTheme } from "expo-router/react-navigation";
import { useRef, useState } from "react";
import { Alert, ScrollView, StyleSheet, TextInput } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";
import { resolvePronoteChallenge, storePronoteLogin } from "@/utils/pronote/sign-in";

const descriptions: Partial<Record<DoubleAuthMode, string>> = {
  [DoubleAuthMode.MGDA_Inactive]: "Désactivée",
  [DoubleAuthMode.MGDA_NotificationSeulement]: "Notification à la connexion",
  [DoubleAuthMode.MGDA_SaisieCodePIN]: "Saisie d’un code PIN",
};

type Props = {
  doubleAuthSession: SessionHandle | null;
  doubleAuthError: SecurityError | null;
  setChallengeModalVisible: (visible: boolean) => void;
  deviceId: string;
  relinkAccountId?: string;
  relinkServiceId?: string;
};

export function Pronote2FAModal(props: Props) {
  const { colors } = useTheme();
  const header = useHeaderHeight();
  const insets = useSafeAreaInsets();
  const handle = props.doubleAuthError?.handle;
  const modes = (handle?.availableSecurityModes ?? []).filter(value => descriptions[value]);
  const [mode, setMode] = useState<DoubleAuthMode | undefined>(() =>
    handle && modes.includes(handle.defaultSecurityMode) ? handle.defaultSecurityMode : modes[0]);
  const [pin, setPin] = useState("");
  const [password, setPassword] = useState("");
  const [deviceName, setDeviceName] = useState(() => (Device.deviceName || "Cadenza").slice(0, 30));
  const [loading, setLoading] = useState(false);
  const busy = useRef(false);
  if (!handle) return null;

  const createsPin = !handle.shouldEnterPIN && handle.shouldCustomDoubleAuth && mode === DoubleAuthMode.MGDA_SaisieCodePIN;
  const showPin = handle.shouldEnterPIN || createsPin;
  const field = [styles.field, { color: colors.text, borderColor: colors.border, backgroundColor: colors.card }];
  const valid = (!showPin || /^\d{4}$/.test(pin)) && (!handle.shouldCustomPassword || Boolean(password)) &&
    (!handle.shouldCustomDoubleAuth || mode !== undefined);

  async function continueSignIn() {
    const { doubleAuthSession: session, doubleAuthError: error, deviceId, relinkAccountId, relinkServiceId } = props;
    if (!valid || !session || !error || busy.current) return;
    busy.current = true;
    setLoading(true);
    try {
      const refresh = await resolvePronoteChallenge(session, error, {
        mode: handle?.shouldCustomDoubleAuth ? mode : undefined, pin, password, deviceName,
      });
      storePronoteLogin(session, refresh, deviceId,
        relinkAccountId && relinkServiceId ? { accountId: relinkAccountId, serviceId: relinkServiceId } : undefined);
      setPin("");
      setPassword("");
      router.dismissTo("/");
    } catch {
      Alert.alert("Vérification refusée", "Vérifiez le code et les options demandées par PRONOTE, puis réessayez.");
    } finally {
      busy.current = false;
      setLoading(false);
    }
  }

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.background }} keyboardShouldPersistTaps="handled"
      contentContainerStyle={[styles.content, { paddingTop: header + 20, paddingBottom: insets.bottom + 20 }]}>
      <Typography variant="h2">Vérification PRONOTE</Typography>
      {handle.shouldCustomDoubleAuth && <Typography>Mode de vérification demandé par PRONOTE</Typography>}
      {handle.shouldCustomDoubleAuth && modes.map(value => (
        <Button key={value} label={descriptions[value]!} variant={value === mode ? "primary" : "outlined"}
          disabled={loading} onPress={() => { setMode(value); setPin(""); }} />
      ))}
      {handle.shouldCustomDoubleAuth && modes.length === 0 && <Typography>Ouvrez PRONOTE pour choisir un mode de sécurité.</Typography>}
      {handle.shouldEnterSource && <TextInput accessibilityLabel="Nom de l’appareil" value={deviceName} onChangeText={setDeviceName}
        editable={!loading} maxLength={30} style={field} />}
      {showPin && (
        <>
          <Typography>{createsPin ? "Créez un code PIN à 4 chiffres." : "Saisissez le code PIN configuré dans PRONOTE."}</Typography>
          <TextInput accessibilityLabel="Code PIN PRONOTE" value={pin} onChangeText={text => setPin(text.replace(/[^0-9]/g, ""))}
            editable={!loading} style={field} keyboardType="number-pad" secureTextEntry maxLength={4} />
        </>
      )}
      {handle.shouldCustomPassword && (
        <>
          <Typography>PRONOTE exige un nouveau mot de passe.</Typography>
          <TextInput accessibilityLabel="Nouveau mot de passe PRONOTE" value={password} onChangeText={setPassword}
            editable={!loading} style={field} autoCapitalize="none" autoCorrect={false}
            textContentType="newPassword" autoComplete="new-password" secureTextEntry />
        </>
      )}
      <Button label={loading ? "Vérification…" : "Continuer"} onPress={() => void continueSignIn()} disabled={!valid || loading} />
      <Button label="Annuler" variant="text" disabled={loading} onPress={() => props.setChallengeModalVisible(false)} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { paddingHorizontal: 20, gap: 14 },
  field: { minHeight: 48, padding: 12, fontSize: 17, borderWidth: 1, borderRadius: 12 },
});
