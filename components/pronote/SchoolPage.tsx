import { Stack } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { PropsWithChildren, useEffect, useState } from "react";
import { ActivityIndicator, Alert, Linking, Pressable, RefreshControl, ScrollView, StyleSheet, View } from "react-native";
import HTMLView from "react-native-htmlview";

import { getManager, subscribeManagerUpdate } from "@/services/shared";
import { Attachment } from "@/services/shared/attachment";
import { useAccountStore } from "@/stores/account";
import Typography from "@/ui/new/Typography";

export function useSchoolManager() {
  const accountId = useAccountStore(state => state.lastUsedAccount);
  const [manager, setManager] = useState(() => getManager());
  const [revision, setRevision] = useState(0);
  useEffect(() => subscribeManagerUpdate(value => {
    setManager(value);
    setRevision(current => current + 1);
  }), []);
  return { manager: manager?.getAccount().id === accountId ? manager : null, revision, accountId };
}

export function SchoolPage({ title, loading, refresh, children }: PropsWithChildren<{
  title: string; loading?: boolean; refresh?: () => void;
}>) {
  const { colors } = useTheme();
  return (
    <>
      <Stack.Screen options={{ title, headerShown: true }} />
      <ScrollView style={{ backgroundColor: colors.background }} keyboardShouldPersistTaps="handled"
        contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.page}
        refreshControl={refresh ? <RefreshControl refreshing={loading === true} onRefresh={refresh} /> : undefined}>
        {loading && <ActivityIndicator color={colors.primary} />}
        {children}
      </ScrollView>
    </>
  );
}

export function SchoolCard({ children }: PropsWithChildren) {
  const { colors } = useTheme();
  return <View style={[styles.card, { backgroundColor: colors.card, borderColor: colors.border }]}>{children}</View>;
}

export function SchoolRow({ title, caption, onPress, selected }: {
  title: string; caption?: string; onPress: () => void; selected?: boolean;
}) {
  const { colors } = useTheme();
  return (
    <Pressable accessibilityRole="button" accessibilityState={selected === undefined ? undefined : { selected }}
      onPress={onPress} style={({ pressed }) => [styles.row, {
        backgroundColor: selected || pressed ? colors.background : colors.card,
        borderColor: colors.border,
      }]}>
      <Typography variant="title">{title}</Typography>
      {Boolean(caption) && <Typography variant="caption" color="textSecondary">{caption}</Typography>}
    </Pressable>
  );
}

export function openSchoolLink(value: string) {
  try {
    const address = new URL(value);
    if (address.protocol !== "https:" || address.username || address.password) throw new Error();
    void Linking.openURL(address.toString()).catch(() => Alert.alert("Lien indisponible", "Le document n’a pas pu être ouvert."));
  } catch {
    Alert.alert("Lien indisponible", "Le document ne possède pas d’adresse HTTPS valide.");
  }
}

export function SchoolAttachments({ files }: { files: Attachment[] }) {
  return files.map((attachment, index) => (
    <SchoolRow key={index + ":" + attachment.name} title={attachment.name || "Pièce jointe"}
      caption="Ouvrir le document" onPress={() => openSchoolLink(attachment.url)} />
  ));
}

export function SchoolContent({ content }: { content: string }) {
  const { colors } = useTheme();
  const contentStyle = { color: colors.text, fontSize: 16 };
  if (!content.trim()) return null;
  if (!/<[a-z][\s\S]*>/i.test(content)) return <Typography>{content}</Typography>;
  const style = { p: contentStyle, div: contentStyle, a: { color: colors.primary, textDecorationLine: "underline" as const } };
  return (
    <HTMLView
      value={content} stylesheet={style} onLinkPress={openSchoolLink}
      renderNode={node => ["img", "iframe", "script", "style", "video", "audio", "object"].includes(node.name) ? null : undefined}
    />
  );
}

const styles = StyleSheet.create({
  page: { gap: 12, paddingHorizontal: 16, paddingTop: 16, paddingBottom: 32, flexGrow: 1 },
  card: { padding: 14, gap: 10, borderRadius: 16, borderWidth: StyleSheet.hairlineWidth },
  row: { padding: 13, gap: 3, borderWidth: StyleSheet.hairlineWidth, minHeight: 48, borderRadius: 13, justifyContent: "center" },
});
