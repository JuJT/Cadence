import { addWeeks, startOfWeek } from "date-fns";
import { Stack } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useEffect, useState } from "react";

import { getManager } from "@/services/shared";
import type { CanteenMenu, Meal } from "@/services/shared/canteen";
import List from "@/ui/new/List";
import Typography from "@/ui/new/Typography";

const mealGroups: { key: keyof Meal; label: string }[] = [
  { key: "entry", label: "Entrée" }, { key: "main", label: "Plat" }, { key: "side", label: "Accompagnement" },
  { key: "cheese", label: "Fromage" }, { key: "dessert", label: "Dessert" }, { key: "drink", label: "Boisson" },
];

export default function CanteenMenuScreen() {
  const { colors } = useTheme();
  const [week, setWeek] = useState(0);
  const [menus, setMenus] = useState<CanteenMenu[]>();
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true;
    setMenus(undefined);
    setFailed(false);
    const manager = getManager(true);
    if (!manager) { setMenus([]); return; }
    const date = addWeeks(startOfWeek(new Date(), { weekStartsOn: 1 }), week);
    void manager.getWeeklyCanteenMenu(date).then(value => {
      if (active) setMenus(value.sort((a, b) => +a.date - +b.date));
    }).catch(() => { if (active) { setFailed(true); setMenus([]); } });
    return () => { active = false; };
  }, [week]);

  return <List contentInsetAdjustmentBehavior="automatic" safeHorizontalPadding={16} style={{ flex: 1, backgroundColor: colors.background }}>
    <Stack.Screen options={{ title: "Menu de la cantine", headerShown: true }} />
    <List.Section>
      <List.Item onPress={() => setWeek(value => value - 1)}><Typography>Semaine précédente</Typography></List.Item>
      <List.Item onPress={() => setWeek(0)}><Typography color={week === 0 ? "primary" : "textPrimary"}>Cette semaine</Typography></List.Item>
      <List.Item onPress={() => setWeek(value => value + 1)}><Typography>Semaine suivante</Typography></List.Item>
    </List.Section>
    {!menus?.length && <List.Section><List.Item><Typography color="textSecondary">
      {failed ? "Le menu est momentanément indisponible." : menus ? "Aucun menu publié pour cette semaine." : "Chargement…"}
    </Typography></List.Item></List.Section>}
    {menus?.map(menu => <List.Section key={menu.id}>
      <List.SectionTitle><List.Label>{new Date(menu.date).toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long" })}</List.Label></List.SectionTitle>
      {([menu.lunch, menu.dinner] as const).map((meal, index) => meal && <List.Item key={index}>
        <Typography variant="title">{index === 0 ? "Déjeuner" : "Dîner"}</Typography>
        {mealGroups.map(({ key, label }) => !!meal[key]?.length && <Typography key={key}>{label} · {meal[key]?.map(item => item.name).join(", ")}</Typography>)}
      </List.Item>)}
    </List.Section>)}
  </List>;
}
