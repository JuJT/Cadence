import { Link } from "expo-router";
import { useIsFocused, useTheme } from "expo-router/react-navigation";
import { BusFront, ChevronRight } from "lucide-react-native";
import { useEffect, useState } from "react";
import { Pressable, View } from "react-native";

import { nextTransitDepartures, type TransitDeparture } from "@/services/cadenza/transit";
import { selectTravelHome } from "@/services/cadenza/travel-schedule";
import { useAccountStore } from "@/stores/account";
import { defaultTravelPreferences, useTravelStore } from "@/stores/travel";
import Typography from "@/ui/new/Typography";

export function TravelHomeEntry() {
  const { colors } = useTheme();
  const profile = useAccountStore(state => state.lastUsedAccount);
  const config = useTravelStore(state => profile ? state.profiles[profile] ?? defaultTravelPreferences : defaultTravelPreferences);
  const focused = useIsFocused();
  const home = selectTravelHome(config, new Date());
  const [service, setService] = useState<{ stopId: string; next?: TransitDeparture }>();

  useEffect(() => {
    if (!focused || !config.enabled || !home?.stop) return;
    let active = true;
    const stop = home.stop;
    const refresh = () => void nextTransitDepartures(stop).then(items => {
      if (active) setService({ stopId: stop.id, next: items.find(item => !item.cancelled) });
    }).catch(() => { if (active) setService(undefined); });
    refresh();
    const timer = setInterval(refresh, 60_000);
    return () => { active = false; clearInterval(timer); };
  }, [focused, config.enabled, home?.stop]);

  if (!config.enabled) return null;
  const next = service?.stopId === home?.stop.id ? service?.next : undefined;
  const description = next
    ? `${next.line} · ${new Date(next.time).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: home?.stop.tz })} · ${next.live ? "En direct" : "Horaire théorique"}`
    : home?.stop.name ?? "Choisir un point de départ";

  return (
    <Link href="/(modals)/travel" asChild>
      <Pressable accessibilityRole="button" style={{ flexDirection: "row", alignItems: "center", gap: 12,
        paddingHorizontal: 15, paddingVertical: 12, borderRadius: 22, backgroundColor: colors.card }}>
        <BusFront size={20} color={colors.primary} />
        <View style={{ flex: 1 }}>
          <Typography variant="title">Trajets</Typography>
          <Typography variant="caption" color="textSecondary">{description}</Typography>
        </View>
        <ChevronRight size={17} color={colors.primary} />
      </Pressable>
    </Link>
  );
}
