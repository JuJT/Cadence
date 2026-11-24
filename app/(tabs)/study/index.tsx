import DateTimePicker from "@react-native-community/datetimepicker";
import { File, Paths } from "expo-file-system";
import { Stack, router, useLocalSearchParams } from "expo-router";
import { ChevronRight, Headphones, Pause, Play, Square } from "lucide-react-native";
import React, { useEffect, useState, type ReactNode } from "react";
import {
  ActivityIndicator, Alert, Linking, Modal, Platform, Pressable, ScrollView, Share, StyleSheet, TextInput, View,
} from "react-native";

import { StudyClock } from "@/components/StudyEntry";
import { getHomeworkById, updateHomeworkIsDone } from "@/database/useHomework";
import { useStudyColors } from "@/hooks/useStudyColors";
import { getManager } from "@/services/shared";
import {
  addPastStudy, closeStudyTask, initializeStudy, removeStudySession, restoreStudyBackup, retryStudyLoad,
  runTimerAction, saveStudySubject, startStudy, updateStudySession, useStudyStore,
} from "@/stores/study";
import {
  durationText, elapsedSeconds, getActiveSession, isPaused, studyRange, studyTotals,
  type StudyKind, type StudySession, type StudyState, type StudySubject,
} from "@/stores/study/model";
import Typography from "@/ui/new/Typography";

const kindTitle = { course: "Cours", revision: "Révision" };
const sections = [
  { id: "timer", label: "Chronomètre" },
  { id: "stats", label: "Statistiques" },
  { id: "history", label: "Historique" },
] as const;
type Section = typeof sections[number]["id"];

function Pill({ label, onPress, selected, disabled }: { label: string; onPress: () => void; selected?: boolean; disabled?: boolean }) {
  const colors = useStudyColors();
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityState={{ selected, disabled }}
      style={({ pressed }) => [
        styles.pill, { backgroundColor: selected ? colors.tint + "1D" : colors.card, borderColor: selected ? colors.tint : colors.border,
          opacity: disabled ? 0.4 : pressed ? 0.7 : 1 },
      ]}
    >
      <Typography color={selected ? "primary" : "textPrimary"} variant="body2" weight="semibold">{label}</Typography>
    </Pressable>
  );
}

function Card({ children }: { children: ReactNode }) {
  const colors = useStudyColors();
  return <View style={[styles.card, { backgroundColor: colors.card, borderColor: colors.border }]}>{children}</View>;
}

function Action({ title, icon, onPress, primary, disabled }: {
  title: string; icon?: ReactNode; onPress: () => void; primary?: boolean; disabled?: boolean;
}) {
  const colors = useStudyColors();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.action, { backgroundColor: primary ? colors.tint : colors.tint + "13",
          opacity: disabled ? 0.45 : pressed ? 0.75 : 1 },
      ]}
    >
      {icon}
      <Typography variant="body1" weight="semibold" color={primary ? "#FFFFFF" : "primary"}>{title}</Typography>
    </Pressable>
  );
}

function Field({ label, value, onChangeText, multiline, numeric }: {
  label: string; value: string; onChangeText: (value: string) => void; multiline?: boolean; numeric?: boolean;
}) {
  const colors = useStudyColors();
  return (
    <View style={{ gap: 4 }}>
      <Typography variant="caption" color="textSecondary">{label}</Typography>
      <TextInput
        accessibilityLabel={label}
        value={value}
        onChangeText={onChangeText}
        multiline={multiline}
        keyboardType={numeric ? "numeric" : "default"}
        style={[styles.field, { color: colors.text, borderColor: colors.border, minHeight: multiline ? 86 : 46 }]}
      />
    </View>
  );
}

function Sheet({ title, close, children }: { title: string; close: () => void; children: ReactNode }) {
  const colors = useStudyColors();
  return (
    <Modal visible animationType="slide" presentationStyle={Platform.OS === "ios" ? "pageSheet" : "fullScreen"} onRequestClose={close}>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.page} style={{ backgroundColor: colors.background }}>
        <Typography variant="h3" accessibilityRole="header">{title}</Typography>
        {children}
        <Action title="Fermer" onPress={close} />
      </ScrollView>
    </Modal>
  );
}

function showFailure(error: unknown) {
  Alert.alert("Révision", error instanceof Error ? error.message : "L’opération n’a pas pu être effectuée.");
}

function openMusic() {
  const open = (url: string) => { void Linking.openURL(url).catch(showFailure); };
  Alert.alert("Musique", "Ouvrez votre lecteur pendant la séance.", [
    { text: "Apple Music", onPress: () => open("https://music.apple.com/") },
    { text: "Spotify", onPress: () => open("https://open.spotify.com/") },
    { text: "Annuler", style: "cancel" },
  ]);
}

export default function StudyScreen() {
  const colors = useStudyColors();
  const { section, open } = useLocalSearchParams<{ section?: Section; open?: string }>();
  const [screen, setScreen] = useState<Section>(section ?? "timer");
  const [editing, setEditing] = useState<StudySession>();
  const [subjects, setSubjects] = useState(false);
  const [showBackups, setShowBackups] = useState(false);
  const data = useStudyStore(state => state.data);
  const status = useStudyStore(state => state.status);
  const loadError = useStudyStore(state => state.error);
  const active = getActiveSession(data);

  useEffect(() => { void initializeStudy(); }, []);
  useEffect(() => {
    if (sections.some(item => item.id === section)) setScreen(section!);
  }, [section, open]);

  return (
    <ScrollView style={{ backgroundColor: colors.overground }}
      contentContainerStyle={styles.page} contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled">
      <Stack.Screen options={{ title: "Révision" }} />
      <View style={styles.wrap}>
        {sections.map(item => <Pill key={item.id} label={item.label} selected={screen === item.id} onPress={() => setScreen(item.id)} />)}
      </View>
      {status === "loading" && <ActivityIndicator color={colors.tint} />}
      {status === "error" && (
        <Card>
          <Typography variant="title">Suivi indisponible</Typography>
          <Typography>{loadError}</Typography>
          <Action title="Réessayer" onPress={() => { void retryStudyLoad(); }} />
          <Action title="Restaurer une sauvegarde" onPress={() => setShowBackups(true)} />
        </Card>
      )}
      {status === "ready" && screen === "timer" && (active
        ? <ActiveTimer session={active} subject={data.subjects.find(subject => subject.id === active.subjectId)}
          edit={() => setEditing(active)} stats={() => setScreen("stats")} />
        : <SessionForm data={data} manageSubjects={() => setSubjects(true)} />)}
      {status === "ready" && screen === "stats" && <Stats data={data} />}
      {status === "ready" && screen === "history" && <History data={data} edit={setEditing} exportData={() => setShowBackups(true)} />}
      {editing && <EditSession session={editing} close={() => setEditing(undefined)} />}
      {subjects && <Subjects data={data} close={() => setSubjects(false)} />}
      {showBackups && <Backups data={data} close={() => setShowBackups(false)} />}
    </ScrollView>
  );
}

function ActiveTimer({ session, subject, edit, stats }: {
  session: StudySession; subject?: StudySubject; edit: () => void; stats: () => void;
}) {
  const colors = useStudyColors();
  const paused = isPaused(session);
  const completeTask = async () => {
    try {
      const routeId = session.task?.routeId;
      if (routeId) {
        const homework = await getHomeworkById(routeId);
        if (homework && !homework.custom) await getManager()?.setHomeworkCompletion(homework, true);
        await updateHomeworkIsDone(routeId, true);
      }
      await closeStudyTask(true);
    } catch (error) { showFailure(error); }
  };
  const finish = () => Alert.alert("Terminer la séance ?", "Le temps mesuré sera ajouté à votre historique.", [
    { text: "Annuler", style: "cancel" },
    { text: "Terminer et enregistrer", onPress: () => { void runTimerAction("finish").catch(showFailure); } },
  ]);
  return (
    <>
      <Card>
        <Typography variant="caption" weight="bold" color="primary">{paused ? "EN PAUSE" : kindTitle[session.kind]}</Typography>
        <Typography variant="h3" accessibilityRole="header">{subject?.name ?? "Matière archivée"}</Typography>
        {!!session.title && session.title !== subject?.name && <Typography color="textSecondary">{session.title}</Typography>}
        <StudyClock session={session} style={{ fontSize: 46, color: colors.tint, textAlign: "center", marginVertical: 12 }} />
        <View style={styles.wrap}>
          <Action title={paused ? "Reprendre" : "Pause"}
            icon={paused ? <Play size={17} color={colors.tint} /> : <Pause size={17} color={colors.tint} />}
            onPress={() => { void runTimerAction(paused ? "resume" : "pause").catch(showFailure); }} />
          <Action title="Terminer" primary icon={<Square size={15} color="#fff" />} onPress={finish} />
        </View>
      </Card>
      {session.task && (
        <Card>
          <Typography variant="title">Devoir associé</Typography>
          <Typography selectable>{session.task.title}</Typography>
          <View style={styles.wrap}>
            <Action title="Valider ce devoir" onPress={() => { void completeTask(); }} />
            <Action title="Détacher" onPress={() => { void closeStudyTask(false).catch(showFailure); }} />
            {!!session.task.routeId && <Action title="Ouvrir le devoir" onPress={() => router.navigate({
              pathname: "/(tabs)/tasks/[id]", params: { id: session.task!.routeId! },
            })} />}
          </View>
        </Card>
      )}
      <Card>
        <Action title="Statistiques" onPress={stats} />
        <Action title="Modifier le chapitre et les notes" onPress={edit} />
        <Action title="Musique" icon={<Headphones size={17} color={colors.tint} />} onPress={openMusic} />
      </Card>
    </>
  );
}

function SessionForm({ data, manageSubjects }: { data: StudyState; manageSubjects: () => void }) {
  const suggested = data.subjects.filter(subject => !subject.archived);
  const [kind, setKind] = useState<StudyKind>("revision");
  const [name, setName] = useState(suggested[0]?.name ?? "");
  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [previous, setPrevious] = useState(false);
  const [minutes, setMinutes] = useState("30");
  const [date, setDate] = useState(new Date());
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setBusy(true);
    try {
      const request = { subjectName: name, kind, title, notes };
      if (previous) {
        await addPastStudy(request, date.getTime(), Number(minutes.replace(",", ".")));
        Alert.alert("Séance enregistrée");
      } else await startStudy(request);
    } catch (error) { showFailure(error); }
    finally { setBusy(false); }
  };

  return (
    <Card>
      <Typography variant="title" accessibilityRole="header">{previous ? "Ajouter une séance passée" : "Nouvelle séance"}</Typography>
      <View style={styles.wrap}>
        <Pill label="Révision" selected={kind === "revision"} onPress={() => setKind("revision")} />
        <Pill label="Cours" selected={kind === "course"} onPress={() => setKind("course")} />
      </View>
      <Field label="Matière" value={name} onChangeText={setName} />
      {suggested.length > 0 && (
        <ScrollView horizontal keyboardShouldPersistTaps="handled" showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
          {suggested.map(subject => <Pill key={subject.id} label={subject.name} onPress={() => setName(subject.name)} selected={name === subject.name} />)}
        </ScrollView>
      )}
      <Field label="Chapitre ou objectif (facultatif)" value={title} onChangeText={setTitle} />
      {previous && (
        <>
          <Field label="Notes (facultatif)" value={notes} onChangeText={setNotes} multiline />
          <Field label="Durée en minutes" value={minutes} onChangeText={setMinutes} numeric />
          <Typography variant="caption" color="textSecondary">Fin de la séance</Typography>
          <DateTimePicker value={date} mode={Platform.OS === "ios" ? "datetime" : "date"} maximumDate={new Date()}
            onChange={(_, selected) => { if (selected) setDate(selected); }} />
        </>
      )}
      <Action title={previous ? "Enregistrer" : "Démarrer"} primary icon={<Play size={16} color="#fff" />}
        onPress={() => { void save(); }} disabled={busy || !name.trim()} />
      <Action title={previous ? "Utiliser le chronomètre" : "Ajouter une séance passée"} onPress={() => setPrevious(!previous)} />
      <Action title="Gérer les matières" onPress={manageSubjects} />
    </Card>
  );
}

function Stats({ data }: { data: StudyState }) {
  const colors = useStudyColors();
  const [period, setPeriod] = useState<"day" | "week" | "month">("week");
  const range = studyRange(period);
  const total = studyTotals(data, range);
  const bySubject = [...total.bySubject].sort(([, a], [, b]) => b - a);
  const sum = total.courseSeconds + total.revisionSeconds;
  return (
    <Card>
      <Typography variant="h4" accessibilityRole="header">Temps de travail</Typography>
      <View style={styles.wrap}>
        <Pill label="Aujourd’hui" selected={period === "day"} onPress={() => setPeriod("day")} />
        <Pill label="Semaine" selected={period === "week"} onPress={() => setPeriod("week")} />
        <Pill label="Mois" selected={period === "month"} onPress={() => setPeriod("month")} />
      </View>
      <Typography variant="h1" color="primary">{durationText(sum)}</Typography>
      <Typography>Révisions · {durationText(total.revisionSeconds)}</Typography>
      <Typography>Cours · {durationText(total.courseSeconds)}</Typography>
      <Typography color="textSecondary">{total.sessionCount} séance{total.sessionCount === 1 ? "" : "s"} chronométrée{total.sessionCount === 1 ? "" : "s"} ou ajoutée{total.sessionCount === 1 ? "" : "s"}</Typography>
      <Typography variant="title">Par matière</Typography>
      {bySubject.length === 0 && <Typography color="textSecondary">Aucun temps enregistré pour cette période.</Typography>}
      {bySubject.map(([subjectId, seconds]) => {
        const subject = data.subjects.find(item => item.id === subjectId);
        return (
          <View key={subjectId} style={{ gap: 5 }}>
            <View style={styles.row}>
              <Typography style={{ flex: 1 }}>{subject?.name ?? "Matière archivée"}</Typography>
              <Typography variant="body2" weight="semibold">{durationText(seconds)}</Typography>
            </View>
            <View style={{ backgroundColor: colors.border, height: 6, borderRadius: 8 }}>
              <View style={{ backgroundColor: subject?.color ?? colors.tint, width: `${Math.round(seconds / sum * 100)}%`, height: 6, borderRadius: 8 }} />
            </View>
          </View>
        );
      })}
    </Card>
  );
}

function History({ data, edit, exportData }: { data: StudyState; edit: (session: StudySession) => void; exportData: () => void }) {
  const { colors } = useTheme();
  const [filter, setFilter] = useState<StudyKind>();
  const [limit, setLimit] = useState(35);
  const sessions = data.sessions.filter(session => session.endedAt !== undefined && (!filter || session.kind === filter))
    .sort((a, b) => b.startedAt - a.startedAt);
  return (
    <>
      <Card>
        <Typography variant="h4" accessibilityRole="header">Séances enregistrées</Typography>
        <View style={styles.wrap}>
          <Pill label="Toutes" selected={!filter} onPress={() => setFilter(undefined)} />
          <Pill label="Cours" selected={filter === "course"} onPress={() => setFilter("course")} />
          <Pill label="Révisions" selected={filter === "revision"} onPress={() => setFilter("revision")} />
        </View>
        {sessions.length === 0 && <Typography color="textSecondary">Aucune séance enregistrée.</Typography>}
        {sessions.slice(0, limit).map(session => (
          <Pressable key={session.id} accessibilityRole="button" onPress={() => edit(session)} style={[styles.row, styles.historyItem, { borderColor: colors.border }]}>
            <View style={{ flex: 1 }}>
              <Typography variant="title">{data.subjects.find(subject => subject.id === session.subjectId)?.name ?? "Matière archivée"}</Typography>
              <Typography color="textSecondary" variant="caption">{new Date(session.startedAt).toLocaleDateString("fr-FR")} · {kindTitle[session.kind]}</Typography>
              {!!session.title && <Typography>{session.title}</Typography>}
            </View>
            <Typography weight="semibold" color="primary">{durationText(elapsedSeconds(session))}</Typography>
            <ChevronRight color={colors.tint} size={16} />
          </Pressable>
        ))}
        {sessions.length > limit && <Action title="Afficher plus" onPress={() => setLimit(limit + 35)} />}
      </Card>
      <Action title="Sauvegarde JSON et export CSV" onPress={exportData} />
    </>
  );
}

function EditSession({ session, close }: { session: StudySession; close: () => void }) {
  const [title, setTitle] = useState(session.title);
  const [notes, setNotes] = useState(session.notes);
  return (
    <Sheet title="Modifier la séance" close={close}>
      <Card>
        <Field label="Chapitre ou objectif" value={title} onChangeText={setTitle} />
        <Field label="Notes" value={notes} onChangeText={setNotes} multiline />
        <Action title="Enregistrer" primary onPress={() => { void updateStudySession(session.id, title, notes).then(close).catch(showFailure); }} />
        {session.endedAt !== undefined && <Action title="Supprimer cette séance" onPress={() => Alert.alert("Supprimer la séance ?", "", [
          { text: "Annuler", style: "cancel" },
          { text: "Supprimer", style: "destructive", onPress: () => { void removeStudySession(session.id).then(close).catch(showFailure); } },
        ])} />}
      </Card>
    </Sheet>
  );
}

function Subjects({ data, close }: { data: StudyState; close: () => void }) {
  const [id, setId] = useState<string>();
  const [name, setName] = useState("");
  const [aliases, setAliases] = useState("");
  const [archived, setArchived] = useState(false);
  const choose = (subject?: StudySubject) => {
    setId(subject?.id);
    setName(subject?.name ?? "");
    setAliases(subject?.aliases.join(", ") ?? "");
    setArchived(subject?.archived ?? false);
  };
  return (
    <Sheet title="Matières" close={close}>
      <View style={styles.wrap}>
        <Pill label="+ Nouvelle" onPress={() => choose()} selected={!id} />
        {data.subjects.map(subject => <Pill key={subject.id} label={subject.name + (subject.archived ? " (archivée)" : "")}
          onPress={() => choose(subject)} selected={id === subject.id} />)}
      </View>
      <Card>
        <Field label="Nom de la matière" value={name} onChangeText={setName} />
        <Field label="Alias, séparés par des virgules" value={aliases} onChangeText={setAliases} />
        {!!id && <Pill label={archived ? "Matière archivée" : "Archiver"} selected={archived} onPress={() => setArchived(!archived)} />}
        <Action title="Enregistrer" primary disabled={!name.trim()} onPress={() => {
          void saveStudySubject(id, name, aliases, archived).then(close).catch(showFailure);
        }} />
      </Card>
    </Sheet>
  );
}

function Backups({ data, close }: { data: StudyState; close: () => void }) {
  const [backup, setBackup] = useState("");
  const share = async (type: "json" | "csv") => {
    try {
      const columns = ["Matière", "Type", "Début", "Fin", "Secondes", "Chapitre", "Notes"];
      const rows = data.sessions.map(session => [
        data.subjects.find(subject => subject.id === session.subjectId)?.name ?? "",
        kindTitle[session.kind], new Date(session.startedAt).toISOString(),
        session.endedAt !== undefined ? new Date(session.endedAt).toISOString() : "",
        String(Math.round(elapsedSeconds(session))), session.title, session.notes,
      ]);
      const csv = [columns, ...rows].map(row => row.map(value => '"' + value.replaceAll('"', '""') + '"').join(";")).join("\r\n");
      const contents = type === "json" ? JSON.stringify(data, null, 2) : "\uFEFF" + csv;
      if (Platform.OS === "ios") {
        const file = new File(Paths.cache, "Cadenza-seances." + type);
        file.create({ overwrite: true });
        file.write(contents);
        await Share.share({ url: file.uri });
      } else {
        await Share.share({ message: contents });
      }
    } catch (error) { showFailure(error); }
  };
  return (
    <Sheet title="Sauvegardes" close={close}>
      <Card>
        <Action title="Partager la sauvegarde JSON" onPress={() => { void share("json"); }} />
        <Action title="Exporter les séances en CSV" onPress={() => { void share("csv"); }} />
      </Card>
      <Card>
        <Typography variant="title">Restaurer le suivi</Typography>
        <Field label="Collez le contenu du fichier JSON Cadenza" value={backup} onChangeText={setBackup} multiline />
        <Action title="Restaurer" disabled={!backup.trim()} onPress={() => Alert.alert("Restaurer cette sauvegarde ?",
          "Cette opération remplacera le suivi des séances sur cet appareil.", [
            { text: "Annuler", style: "cancel" },
            { text: "Restaurer", style: "destructive", onPress: () => { void restoreStudyBackup(backup).then(close).catch(showFailure); } },
          ])} />
      </Card>
    </Sheet>
  );
}

const styles = StyleSheet.create({
  page: { paddingHorizontal: 15, paddingTop: 14, paddingBottom: 34, gap: 14, width: "100%", maxWidth: 740, alignSelf: "center" },
  card: { borderRadius: 22, borderWidth: StyleSheet.hairlineWidth, padding: 16, gap: 12 },
  pill: { minHeight: 44, borderRadius: 22, borderWidth: StyleSheet.hairlineWidth, paddingHorizontal: 12, paddingVertical: 8, justifyContent: "center" },
  action: { minHeight: 46, borderRadius: 18, paddingHorizontal: 13, paddingVertical: 10, alignItems: "center", flexDirection: "row", justifyContent: "center", gap: 7 },
  field: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, paddingHorizontal: 10, paddingVertical: 10, fontSize: 16, textAlignVertical: "top" },
  wrap: { flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: 8 },
  row: { flexDirection: "row", alignItems: "center", gap: 8 },
  historyItem: { paddingVertical: 8, minHeight: 52, borderBottomWidth: StyleSheet.hairlineWidth },
});
