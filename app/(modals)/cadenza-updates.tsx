import Constants from "expo-constants";
import { File, Paths } from "expo-file-system";
import { Stack } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useEffect, useRef, useState } from "react";
import { Linking, Platform, Share } from "react-native";

import { verifyUpdateFile } from "@/modules/cadenza-study";
import { fetchCadenzaRelease, type CadenzaRelease } from "@/services/cadenza/app-release";
import List from "@/ui/new/List";
import Typography from "@/ui/new/Typography";

export default function CadenzaUpdates() {
  const { colors } = useTheme();
  const installed = Constants.expoConfig?.version ?? "0.8.0";
  const [release, setRelease] = useState<CadenzaRelease | null>();
  const [status, setStatus] = useState("");
  const [saving, setSaving] = useState(false);
  const [checking, setChecking] = useState(false);
  const request = useRef<AbortController | null>(null);

  const check = async () => {
    request.current?.abort();
    const current = new AbortController();
    request.current = current;
    const timeout = setTimeout(() => current.abort(), 15_000);
    setChecking(true);
    setStatus("");
    try {
      const result = await fetchCadenzaRelease(installed, current.signal);
      if (request.current === current) setRelease(result);
    } catch {
      if (request.current === current) setStatus("La vérification a échoué. Tu peux réessayer.");
    } finally {
      clearTimeout(timeout);
      if (request.current === current) setChecking(false);
    }
  };

  useEffect(() => {
    void check();
    return () => { request.current?.abort(); request.current = null; };
  }, [installed]);

  const save = async (asset: NonNullable<CadenzaRelease["asset"]>) => {
    if (saving) return;
    setSaving(true);
    setStatus("");
    const destination = new File(Paths.cache, asset.name);
    try {
      const installer = await File.downloadFileAsync(asset.url, destination, { idempotent: true });
      if (!await verifyUpdateFile(installer.uri, asset.size, asset.sha256)) {
        if (installer.exists) installer.delete();
        throw new Error("Incoherent installer");
      }
      await Share.share({ url: installer.uri });
    } catch {
      setStatus("Le téléchargement a échoué. Tu peux partager le lien vers le PC.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <List contentInsetAdjustmentBehavior="automatic" safeHorizontalPadding={16} style={{ flex: 1, backgroundColor: colors.background }}>
      <Stack.Screen options={{ title: "Mises à jour Cadenza", headerShown: true }} />
      <List.Section>
        <List.Item><Typography variant="title">Version {installed}</Typography></List.Item>
        <List.Item onPress={checking || saving ? undefined : () => { void check(); }}>
          <Typography>{checking ? "Vérification…" : "Rechercher une mise à jour"}</Typography>
        </List.Item>
        {release === null && !checking && !status && <List.Item><Typography color="textSecondary">Cadenza est à jour.</Typography></List.Item>}
        {!!status && <List.Item><Typography color="textSecondary">{status}</Typography></List.Item>}
      </List.Section>
      {release && <List.Section>
        <List.SectionTitle><List.Label>Version {release.version}</List.Label></List.SectionTitle>
        {!!release.notes && <List.Item><Typography color="textSecondary">{release.notes}</Typography></List.Item>}
        {release.asset && <>
          {Platform.OS === "ios" && <List.Item onPress={saving || checking ? undefined : () => { if (release.asset) void save(release.asset); }}>
            <Typography>{saving ? "Téléchargement…" : "Télécharger puis partager l’IPA"}</Typography>
          </List.Item>}
          <List.Item onPress={() => { if (release.asset) void Share.share({ message: release.asset.url }); }}>
            <Typography>Partager le lien vers le PC</Typography>
          </List.Item>
        </>}
        <List.Item onPress={() => { void Linking.openURL(release.page); }}><Typography>Voir cette version sur GitHub</Typography></List.Item>
      </List.Section>}
      <List.Section>
        <List.Item>
          <Typography variant="title">Installer avec Sideloadly</Typography>
          <Typography color="textSecondary">Installe l’IPA par-dessus Cadenza sur ton PC avec le même compte et le même identifiant, en conservant les extensions.</Typography>
        </List.Item>
      </List.Section>
    </List>
  );
}
