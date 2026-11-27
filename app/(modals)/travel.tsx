import { addDays, startOfWeek } from "date-fns";
import { Directory, File, Paths } from "expo-file-system";
import * as ImagePicker from "expo-image-picker";
import * as Location from "expo-location";
import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, Alert, Image, Linking, Platform, Pressable, ScrollView, StyleSheet, TextInput, View } from "react-native";

import { getWeekNumberFromDate } from "@/database/useHomework";
import { useTimetable } from "@/database/useTimetable";
import { importTransitPass } from "@/modules/cadenza-study";
import { shouldOfferTimetableAlerts } from "@/services/cadenza/timetable-alerts";
import { findTransitStops, getFrenchTransitNetworks, nextTransitDepartures, planTransitJourney,
  type TransitDeparture, type TransitJourney, type TransitNetwork, type TransitStop } from "@/services/cadenza/transit";
import { dayKey, selectTravelHome, travelTime, type TransitHome } from "@/services/cadenza/travel-schedule";
import { CourseStatus, CourseType } from "@/services/shared/timetable";
import { useAccountStore } from "@/stores/account";
import { defaultTravelPreferences, useTravelStore } from "@/stores/travel";
import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";
import uuid from "@/utils/uuid/uuid";

const workdays = [1, 2, 3, 4, 5];
const days = [[1, "Lun."], [2, "Mar."], [3, "Mer."], [4, "Jeu."], [5, "Ven."], [6, "Sam."], [0, "Dim."]] as const;
const modeLabels: Record<string, string> = { WALK: "À pied", BUS: "Bus", TRAM: "Tram", SUBWAY: "Métro", RAIL: "Train", REGIONAL_RAIL: "Train", FERRY: "Bateau" };
const walletHelp = "https://support.apple.com/fr-fr/118581";

function timeLabel(time: string | Date, tz?: string) {
  return new Date(time).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: tz });
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  const { colors } = useTheme();
  return <View style={[styles.card, { backgroundColor: colors.card }]}>
    <Typography variant="h5">{title}</Typography>{children}
  </View>;
}

function Choice({ title, chosen, onPress }: { title: string; chosen?: boolean; onPress: () => void }) {
  const { colors } = useTheme();
  return <Pressable accessibilityRole="button" accessibilityState={{ selected: chosen }} onPress={onPress}
    style={[styles.choice, { borderColor: chosen ? colors.primary : colors.border }]}>
    <Typography variant="caption" color={chosen ? "primary" : "textPrimary"}>{title}</Typography>
  </Pressable>;
}

function Input({ value, onChangeText, placeholder }: { value: string; onChangeText: (text: string) => void; placeholder: string }) {
  const { colors } = useTheme();
  return <TextInput value={value} onChangeText={onChangeText} placeholder={placeholder} accessibilityLabel={placeholder}
    placeholderTextColor={`${String(colors.text)}88`} style={[styles.input, { color: colors.text, borderColor: colors.border }]} />;
}

export default function TravelScreen() {
  const router = useRouter();
  const { colors } = useTheme();
  const { onboarding } = useLocalSearchParams<{ onboarding?: string }>();
  const profile = useAccountStore(state => state.lastUsedAccount) ?? "";
  const account = useAccountStore(state => state.accounts.find(item => item.id === profile));
  const config = useTravelStore(state => state.profiles[profile] ?? defaultTravelPreferences);
  const change = useTravelStore(state => state.update);
  const [section, setSection] = useState(onboarding === "1" || !config.enabled ? "setup" : "journey");
  const [searchFor, setSearchFor] = useState<"school" | "home">();
  const [search, setSearch] = useState("");
  const [hits, setHits] = useState<TransitStop[]>([]);
  const [loadingStops, setLoadingStops] = useState(false);
  const searchRequest = useRef(0);
  const [editing, setEditing] = useState<TransitHome>();
  const [dateOffset, setDateOffset] = useState(0);
  const [direction, setDirection] = useState<"outbound" | "return">("outbound");
  const [requestedTime, setRequestedTime] = useState("");
  const [departures, setDepartures] = useState<TransitDeparture[]>([]);
  const [journeys, setJourneys] = useState<TransitJourney[]>([]);
  const [loadingRoutes, setLoadingRoutes] = useState(false);
  const [refreshed, setRefreshed] = useState<Date>();
  const [networks, setNetworks] = useState<TransitNetwork[]>([]);
  const [networkFilter, setNetworkFilter] = useState("");
  const [networkCount, setNetworkCount] = useState(20);
  const [error, setError] = useState("");
  const travelDate = addDays(new Date(), dateOffset);
  const home = selectTravelHome(config, travelDate);
  const timetable = useTimetable(0, getWeekNumberFromDate(travelDate), travelDate);

  useEffect(() => {
    setJourneys([]);
    setDepartures([]);
    setRefreshed(undefined);
    setError("");
    setLoadingRoutes(false);
  }, [home?.id, config.school?.id, direction, dateOffset]);

  useEffect(() => {
    if (section !== "networks") return;
    let active = true;
    void getFrenchTransitNetworks().then(items => { if (active) setNetworks(items); })
      .catch(() => { if (active) setError("Le catalogue est indisponible pour le moment."); });
    return () => { active = false; };
  }, [section]);

  const showSection = (value: string) => { setError(""); setSection(value); };
  const dismiss = async () => {
    change(profile, { configured: true });
    if (onboarding === "1" && await shouldOfferTimetableAlerts().catch(() => false)) {
      router.replace({ pathname: "/(modals)/cadenza-alerts", params: { onboarding: "1" } });
    } else if (router.canGoBack()) router.back();
    else router.replace("/(tabs)");
  };

  const chooseStop = (kind: "school" | "home") => {
    searchRequest.current++;
    setError(""); setHits([]); setSearch(""); setSearchFor(kind);
  };
  const searchStops = async (nearby = false) => {
    const requestId = ++searchRequest.current;
    setLoadingStops(true); setError("");
    try {
      let location;
      if (nearby) {
        const permission = await Location.requestForegroundPermissionsAsync();
        if (!permission.granted) throw new Error("Tu peux chercher un arrêt par son nom sans partager ta position.");
        location = (await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced })).coords;
      }
      const list = await findTransitStops(search, location);
      if (requestId === searchRequest.current) setHits(list);
    } catch (cause) {
      if (requestId === searchRequest.current) setError(cause instanceof Error ? cause.message : "La recherche a échoué.");
    } finally {
      if (requestId === searchRequest.current) setLoadingStops(false);
    }
  };
  const acceptStop = (stop: TransitStop) => {
    if (searchFor === "school") change(profile, { school: stop, enabled: true });
    else setEditing(previous => previous ? { ...previous, stop } : { id: uuid(), label: "Domicile", stop, week: "all", days: workdays });
    setSearchFor(undefined);
    setError("");
  };
  const saveHome = () => {
    if (!editing?.label.trim() || !editing.days.length) return;
    const saved = { ...editing, label: editing.label.trim() };
    change(profile, old => ({ enabled: true, homes: old.homes.some(item => item.id === saved.id)
      ? old.homes.map(item => item.id === saved.id ? saved : item) : [...old.homes, saved] }));
    setEditing(undefined);
  };
  const journeysRequest = useRef(0);
  useEffect(() => () => { journeysRequest.current++; }, [home?.id, config.school?.id, direction, dateOffset]);
  const loadRoutes = async () => {
    if (!home || !config.school) return;
    const requestId = ++journeysRequest.current;
    setLoadingRoutes(true); setError("");
    const services = new Set(account?.services.map(service => service.id));
    const courses = timetable.flatMap(day => day.courses).filter(course =>
      dayKey(course.from) === dayKey(travelDate) && services.has(course.createdByAccount) &&
      course.type === CourseType.LESSON && course.status !== CourseStatus.CANCELED)
      .map(course => ({ start: course.from.getTime(), end: course.to.getTime() }));
    const now = new Date(travelDate);
    if (dateOffset !== 0) now.setHours(7, 0, 0, 0);
    const suggested = travelTime(direction, courses, config.arrivalBuffer, now);
    const custom = requestedTime.trim().match(/^([01]?\d|2[0-3])[:h]([0-5]\d)$/);
    if (requestedTime.trim() && !custom) {
      setError("Indique une heure comme 07:45."); setLoadingRoutes(false); return;
    }
    const time = custom ? new Date(travelDate) : suggested.time;
    if (custom) time.setHours(Number(custom[1]), Number(custom[2]), 0, 0);
    const [from, to] = direction === "outbound" ? [home.stop, config.school] : [config.school, home.stop];
    const [routes, next] = await Promise.allSettled([planTransitJourney(from, to, time, !custom && suggested.arriveBy),
      dateOffset === 0 ? nextTransitDepartures(from) : Promise.resolve([])]);
    if (requestId !== journeysRequest.current) return;
    setJourneys(routes.status === "fulfilled" ? routes.value : []);
    setDepartures(next.status === "fulfilled" ? next.value : []);
    setRefreshed(new Date());
    if (routes.status === "rejected" || next.status === "rejected") setError("Certaines données de ce trajet sont indisponibles. Réessaie ou consulte le réseau dans le catalogue.");
    else if (!routes.value.length) setError("Aucun itinéraire trouvé à cette heure.");
    setLoadingRoutes(false);
  };

  const addCard = async (camera: boolean) => {
    try {
      if (camera && !(await ImagePicker.requestCameraPermissionsAsync()).granted) return;
      const picker = camera ? ImagePicker.launchCameraAsync : ImagePicker.launchImageLibraryAsync;
      const result = await picker({ mediaTypes: ["images"], quality: 0.7 });
      if (result.canceled) return;
      const id = uuid();
      const directory = new Directory(Paths.document, "cadenza-transit-cards");
      directory.create({ idempotent: true, intermediates: true });
      const copy = new File(directory, `${id}.jpg`);
      new File(result.assets[0].uri).copy(copy);
      change(profile, old => ({ cards: [...old.cards, { id, name: `Carte ${old.cards.length + 1}`, image: copy.name }] }));
    } catch { setError("Impossible d’enregistrer la photo de cette carte."); }
  };
  const openLink = (url: string) => {
    if (!/^https:\/\//i.test(url)) return;
    void Linking.openURL(url).catch(() => setError("Ce lien est indisponible."));
  };

  return <ScrollView style={{ flex: 1, backgroundColor: colors.background }} contentInsetAdjustmentBehavior="automatic"
    contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Stack.Screen options={{ title: "Transports", headerShown: true }} />
    <View style={styles.row}>
      <Choice title="Trajets" chosen={section === "journey"} onPress={() => showSection("journey")} />
      <Choice title="Configuration" chosen={section === "setup"} onPress={() => showSection("setup")} />
      <Choice title="Mes titres" chosen={section === "cards"} onPress={() => showSection("cards")} />
      <Choice title="Réseaux" chosen={section === "networks"} onPress={() => showSection("networks")} />
    </View>
    {!!error && <Typography accessibilityRole="alert" color="textSecondary">{error}</Typography>}
    {section === "setup" && <>
      <Card title="Trajets quotidiens">
        {onboarding === "1" && <Typography>Ajoute les arrêts de ton lycée et de ton domicile pour retrouver tes horaires de bus, de métro ou de train.</Typography>}
        <Button label={config.school ? `Lycée · ${config.school.name}` : "Choisir l’arrêt du lycée"} onPress={() => chooseStop("school")} />
        {config.homes.map(item => <View key={item.id} style={styles.row}>
          <Choice title={`${item.label} · ${item.stop.name}`} onPress={() => setEditing(item)} />
          <Choice title="Supprimer" onPress={() => change(profile, old => ({ homes: old.homes.filter(entry => entry.id !== item.id) }))} />
        </View>)}
        <Button label="Ajouter un domicile ou un arrêt favori" onPress={() => { setEditing(undefined); chooseStop("home"); }} />
        <View style={styles.row}>{[5, 10, 15, 20].map(value => <Choice key={value} title={`${value} min avant le cours`}
          chosen={value === config.arrivalBuffer} onPress={() => change(profile, { arrivalBuffer: value })} />)}</View>
        {config.homes.some(item => item.week !== "all") && <Choice title="Cette semaine est la semaine A"
          chosen={config.weekA === dayKey(startOfWeek(new Date(), { weekStartsOn: 1 }))}
          onPress={() => change(profile, { weekA: dayKey(startOfWeek(new Date(), { weekStartsOn: 1 })) })} />}
        {onboarding !== "1" && <Button label={config.enabled ? "Masquer Trajets sur l’accueil" : "Afficher Trajets sur l’accueil"}
          onPress={() => change(profile, { enabled: !config.enabled, configured: true })} />}
      </Card>
      {searchFor && <Card title={searchFor === "school" ? "Arrêt du lycée" : "Arrêt près du domicile"}>
        <Input value={search} onChangeText={setSearch} placeholder="Nom de l’arrêt ou de la gare" />
        <View style={styles.row}>
          <Choice title="Rechercher" onPress={() => { if (search.trim().length >= 2 && !loadingStops) void searchStops(); }} />
          <Choice title="Autour de moi" onPress={() => { if (!loadingStops) void searchStops(true); }} />
          <Choice title="Annuler" onPress={() => { searchRequest.current++; setSearchFor(undefined); setLoadingStops(false); }} />
        </View>
        {loadingStops && <ActivityIndicator color={colors.primary} />}
        {hits.map(stop => <Choice key={stop.id} title={stop.area ? `${stop.name} · ${stop.area}` : stop.name} onPress={() => acceptStop(stop)} />)}
      </Card>}
      {editing && <Card title="Domicile">
        <Input value={editing.label} onChangeText={label => setEditing({ ...editing, label })} placeholder="Nom du domicile" />
        <Choice title={editing.stop.name} onPress={() => chooseStop("home")} />
        <View style={styles.row}>{days.map(([value, label]) => <Choice key={value} title={label} chosen={editing.days.includes(value)}
          onPress={() => setEditing({ ...editing, days: editing.days.includes(value) ? editing.days.filter(day => day !== value) : [...editing.days, value] })} />)}</View>
        <View style={styles.row}>{(["all", "A", "B"] as const).map(week => <Choice key={week} title={week === "all" ? "Chaque semaine" : `Semaine ${week}`}
          chosen={editing.week === week} onPress={() => setEditing({ ...editing, week })} />)}</View>
        <Button label="Enregistrer le domicile" onPress={saveHome} />
      </Card>}
      {onboarding === "1" && <Button label={config.enabled ? "Continuer" : "Passer les transports"} onPress={() => { void dismiss(); }} />}
    </>}
    {section === "journey" && <>
      <Card title="Aller et retour">
        <View style={styles.row}>
          <Choice title="Jour précédent" onPress={() => setDateOffset(value => Math.max(-7, value - 1))} />
          <Typography>{travelDate.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" })}</Typography>
          <Choice title="Jour suivant" onPress={() => setDateOffset(value => Math.min(14, value + 1))} />
        </View>
        <View style={styles.row}>
          <Choice title="Aller au lycée" chosen={direction === "outbound"} onPress={() => setDirection("outbound")} />
          <Choice title="Rentrer" chosen={direction === "return"} onPress={() => setDirection("return")} />
        </View>
        {config.homes.length > 0 && <View style={styles.row}>{config.homes.map(item => <Choice key={item.id} title={item.label}
          chosen={home?.id === item.id} onPress={() => change(profile, { override: { date: dayKey(travelDate), homeId: item.id } })} />)}</View>}
        <Typography color="textSecondary">{home && config.school ? `${home.stop.name} ↔ ${config.school.name}` : "Choisis le lycée et un domicile pour ce jour."}</Typography>
        {home && config.school ? <>
          <Input value={requestedTime} onChangeText={setRequestedTime} placeholder="Heure de départ (facultative, 07:45)" />
          <Button label={loadingRoutes ? "Recherche…" : "Calculer le trajet"} onPress={() => { if (!loadingRoutes) void loadRoutes(); }} />
        </> : <Button label="Ouvrir la configuration" onPress={() => showSection("setup")} />}
      </Card>
      {departures.length > 0 && <Card title="Prochains passages">{departures.map(item => <View key={item.id} style={styles.departure}>
        <View style={{ flex: 1 }}><Typography variant="title">{item.line} {item.headsign}</Typography>
          <Typography color="textSecondary" variant="caption">{item.cancelled ? "Supprimé" : item.live ? "Temps réel" : "Horaire théorique"}</Typography></View>
        <Typography weight="bold">{timeLabel(item.time, (direction === "outbound" ? home?.stop : config.school)?.tz)}</Typography>
      </View>)}</Card>}
      {journeys.map(item => <Card key={item.id} title={`${timeLabel(item.departure, home?.stop.tz)} → ${timeLabel(item.arrival, config.school?.tz)}`}>
        <Typography color="textSecondary">{item.transfers > 0 ? `${item.transfers} correspondance${item.transfers > 1 ? "s" : ""}` : "Trajet direct"}</Typography>
        {item.legs.map((leg, index) => <View key={`${leg.departure}-${index}`}>
          <Typography variant="title">{leg.line || modeLabels[leg.mode] || "Transport"} · {leg.from} → {leg.to}</Typography>
          <Typography variant="caption" color="textSecondary">{timeLabel(leg.departure, home?.stop.tz)} – {timeLabel(leg.arrival, config.school?.tz)}{leg.direction ? ` · Direction ${leg.direction}` : ""}
            {leg.mode !== "WALK" ? ` · ${leg.cancelled ? "Supprimé" : leg.live ? "Temps réel" : "Horaire théorique"}` : ""}</Typography>
        </View>)}
      </Card>)}
      {!!refreshed && <Typography variant="caption" color="textSecondary">Transitous · Actualisé à {timeLabel(refreshed)}</Typography>}
    </>}
    {section === "cards" && <Card title="Mes titres">
      <Typography color="textSecondary">Garde ici une photo de ta carte. Pour voyager, utilise le titre émis par ton réseau.</Typography>
      {config.cards.map(card => <View key={card.id} style={styles.cardItem}>
        <Typography variant="title">{card.name}</Typography>
        <Image resizeMode="contain" source={{ uri: new File(Paths.document, "cadenza-transit-cards", card.image).uri }} style={{ width: "100%", height: 155 }} />
        <Choice title="Retirer cette photo" onPress={() => Alert.alert("Retirer cette photo ?", undefined, [
          { text: "Annuler", style: "cancel" }, { text: "Retirer", style: "destructive", onPress: () => {
            const file = new File(Paths.document, "cadenza-transit-cards", card.image);
            if (file.exists) file.delete();
            change(profile, old => ({ cards: old.cards.filter(item => item.id !== card.id) }));
          } },
        ])} />
      </View>)}
      <Button label="Photographier une carte" onPress={() => { void addCard(true); }} />
      <Button label="Importer la photo d’une carte" onPress={() => { void addCard(false); }} />
      {Platform.OS === "ios" && <Button label="Ouvrir un fichier officiel .pkpass" onPress={() => { void importTransitPass().catch(() => setError("Ce fichier n’a pas pu être ouvert dans Cartes.")); }} />}
      <Button label="Ajouter ou recharger Navigo" onPress={() => openLink(walletHelp)} />
    </Card>}
    {section === "networks" && <Card title="Réseaux de France">
      <Input value={networkFilter} onChangeText={value => { setNetworkFilter(value); setNetworkCount(20); }} placeholder="Réseau, région ou ville" />
      {networks.filter(item => `${item.name} ${item.area}`.toLocaleLowerCase("fr-FR").includes(networkFilter.trim().toLocaleLowerCase("fr-FR")))
        .slice(0, networkCount).map(item => <Pressable accessibilityRole="link" key={item.id} onPress={() => openLink(item.url)}>
          <Typography variant="title">{item.name}</Typography>
          <Typography variant="caption" color="textSecondary">{item.area} · {item.realtimePublished ? "Flux temps réel publié" : "Horaires théoriques publiés"}</Typography>
        </Pressable>)}
      {networks.length > networkCount && <Button label="Afficher plus de réseaux" onPress={() => setNetworkCount(value => value + 20)} />}
      <Choice title="Catalogue transport.data.gouv.fr" onPress={() => openLink("https://transport.data.gouv.fr/")} />
      <Choice title="Sources Transitous et OpenStreetMap" onPress={() => openLink("https://transitous.org/sources/")} />
    </Card>}
  </ScrollView>;
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingBottom: 36, gap: 12, width: "100%", maxWidth: 680, alignSelf: "center" },
  card: { padding: 17, borderRadius: 24, gap: 12 },
  row: { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 8 },
  choice: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 18, minHeight: 40, justifyContent: "center", paddingHorizontal: 11, paddingVertical: 6 },
  input: { minHeight: 44, padding: 11, borderWidth: StyleSheet.hairlineWidth, borderRadius: 13, fontSize: 16 },
  departure: { flexDirection: "row", gap: 10, alignItems: "center" },
  cardItem: { gap: 8, alignItems: "flex-start" },
});
