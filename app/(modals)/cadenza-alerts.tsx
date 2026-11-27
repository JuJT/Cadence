import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useEffect, useState } from "react";
import { AppState, Linking } from "react-native";

import { getStudyDiagnostics } from "@/modules/cadenza-study";
import { getTimetableAlertSettings, setTimetableAlerts } from "@/services/cadenza/timetable-alerts";
import NativeSwitch from "@/ui/native/NativeSwitch";
import List from "@/ui/new/List";
import Typography from "@/ui/new/Typography";

export default function CadenzaAlerts() {
  const { colors } = useTheme();
  const router = useRouter();
  const { onboarding } = useLocalSearchParams<{ onboarding?: string }>();
  const isOnboarding = onboarding === "1";
  const [settings, setSettings] = useState<Awaited<ReturnType<typeof getTimetableAlertSettings>>>();
  const [diagnostics, setDiagnostics] = useState<Awaited<ReturnType<typeof getStudyDiagnostics>>>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  const load = async () => {
    setSettings(await getTimetableAlertSettings());
    setDiagnostics(await getStudyDiagnostics());
  };

  useEffect(() => {
    void load().catch(() => setError(true));
    const subscription = AppState.addEventListener("change", state => {
      if (state === "active") void load().catch(() => setError(true));
    });
    return () => subscription.remove();
  }, []);

  const change = async (value: boolean, back = false) => {
    setBusy(true);
    setError(false);
    try {
      await setTimetableAlerts(value);
      await load();
      if (back && router.canGoBack()) router.back();
    } catch {
      setError(true);
    } finally {
      setBusy(false);
    }
  };

  return (
    <List contentInsetAdjustmentBehavior="automatic" safeHorizontalPadding={16} style={{ flex: 1, backgroundColor: colors.background }}>
      <Stack.Screen options={{ title: isOnboarding ? "Notifications" : "Alertes et widgets", headerShown: true }} />
      <List.Section>
        <List.SectionTitle><List.Label>PRONOTE</List.Label></List.SectionTitle>
        <List.Item onPress={isOnboarding && settings && !busy && !settings.enabled && !settings.blockedByOS ? () => { void change(true); } : undefined}>
          <Typography variant="title">Changements de cours</Typography>
          <Typography color="textSecondary">Cadenza peut te prévenir quand PRONOTE signale une absence, une annulation ou un changement d’horaire lors d’une synchronisation.</Typography>
          {!isOnboarding && <List.Trailing>
            <NativeSwitch value={settings?.enabled ?? false} disabled={!settings || busy || settings.blockedByOS} onValueChange={value => { void change(value); }} />
          </List.Trailing>}
        </List.Item>
        {settings?.blockedByOS && <List.Item onPress={() => { void Linking.openSettings(); }}><Typography>Ouvrir les réglages iOS</Typography></List.Item>}
        {!isOnboarding && <List.Item href="/(modals)/timetable-changes"><Typography>Changements récents</Typography></List.Item>}
        {isOnboarding && settings && !settings.enabled && !settings.blockedByOS && <List.Item onPress={busy ? undefined : () => { void change(true); }}><Typography color="primary">Autoriser les notifications</Typography></List.Item>}
        {isOnboarding && <List.Item onPress={busy ? undefined : () => {
          if (settings?.enabled) router.back();
          else void change(false, true);
        }}><Typography>{settings?.enabled ? "Terminer" : "Plus tard"}</Typography></List.Item>}
        {error && <List.Item><Typography color="textSecondary">Impossible de charger les réglages. Réessaie dans un instant.</Typography></List.Item>}
      </List.Section>
      {!isOnboarding && diagnostics && <List.Section>
        <List.SectionTitle><List.Label>Sur cet iPhone</List.Label></List.SectionTitle>
        <List.Item>
          <Typography variant="title">Widgets d’étude</Typography>
          <Typography color="textSecondary">{diagnostics.sharedContainer ? "Le conteneur partagé est disponible." : "La signature de l’app ne donne pas accès au conteneur partagé des widgets."}</Typography>
        </List.Item>
        <List.Item>
          <Typography variant="title">Activité en direct</Typography>
          <Typography color="textSecondary">{diagnostics.liveActivities ? "Autorisée par iOS." : "Désactivée dans les réglages iOS."}</Typography>
        </List.Item>
      </List.Section>}
    </List>
  );
}
