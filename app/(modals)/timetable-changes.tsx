import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useEffect, useState } from "react";

import { describeTimetableChange, readTimetableChanges, type TimetableChangeBatch } from "@/services/cadenza/timetable-alerts";
import { useAccountStore } from "@/stores/account";
import List from "@/ui/new/List";
import Typography from "@/ui/new/Typography";

export default function TimetableChanges() {
  const { colors } = useTheme();
  const router = useRouter();
  const { change } = useLocalSearchParams<{ change?: string }>();
  const account = useAccountStore(state => state.accounts.find(item => item.id === state.lastUsedAccount));
  const [result, setResult] = useState<TimetableChangeBatch[]>();
  useEffect(() => {
    let active = true;
    setResult(undefined);
    void readTimetableChanges(account?.services.map(service => service.id) ?? []).then(batches => {
      if (active) setResult(change ? [...batches.filter(item => item.id === change), ...batches.filter(item => item.id !== change)] : batches);
    }).catch(() => { if (active) setResult([]); });
    return () => { active = false; };
  }, [account, change]);

  return <List style={{ flex: 1, backgroundColor: colors.background }} contentInsetAdjustmentBehavior="automatic" safeHorizontalPadding={16}>
    <Stack.Screen options={{ title: "Changements de cours", headerShown: true }} />
    {(!result || !result.length) && <List.Section><List.Item><Typography color="textSecondary">
      {result ? "Aucun changement récent pour ce profil." : "Chargement…"}
    </Typography></List.Item></List.Section>}
    {result?.map(batch => <List.Section key={batch.id}>
      <List.SectionTitle><List.Label>{new Date(batch.date).toLocaleDateString("fr-FR", { day: "numeric", month: "long" })}</List.Label></List.SectionTitle>
      {batch.changes.map((item, index) => <List.Item key={`${item.lessonId}-${index}`} onPress={() => {
        router.dismissTo({ pathname: "/(tabs)/calendar", params: { focusDate: String(item.time), open: String(Date.now()) } });
      }}>
        <Typography>{describeTimetableChange(item)}</Typography>
        <Typography variant="caption" color="primary">Voir le jour dans l’emploi du temps</Typography>
      </List.Item>)}
    </List.Section>)}
  </List>;
}
