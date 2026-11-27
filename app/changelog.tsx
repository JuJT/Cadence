import AsyncStorage from "@react-native-async-storage/async-storage";
import { Papicons } from "@getpapillon/papicons";
import { router, Stack, useLocalSearchParams } from "expo-router";
import { useTheme } from "expo-router/react-navigation";
import { useState } from "react";
import { Image, ScrollView, View } from "react-native";

import { CADENZA_BLUE, CADENZA_RELEASE_KEY } from "@/constants/Cadenza";
import { installedCadenzaVersionLabel } from "@/services/cadenza/installed-version";
import Button from "@/ui/new/Button";
import Typography from "@/ui/new/Typography";

const changes = [
  {
    icon: "Clock",
    title: "Un chronomètre plein écran",
    description: "Lance une séance depuis un cours, un devoir ou l’onglet Révision. Réduis le chronomètre pour naviguer pendant la séance.",
  },
  {
    icon: "Grades",
    title: "Des statistiques de travail plus précises",
    description: "Retrouve séparément les révisions, les cours chronométrés et les heures issues de ton emploi du temps.",
  },
  {
    icon: "Calendar",
    title: "Tes notes de la période en cours",
    description: "Cadenza ouvre les notes du trimestre ou du semestre en cours. Tu peux consulter une autre période depuis le calendrier des notes.",
  },
  {
    icon: "Paper",
    title: "Plus de services PRONOTE",
    description: "Retrouve le cahier de textes dans Cours, les discussions et les sondages sur l’accueil, et les compétences et bulletins dans Notes selon les droits de ton compte.",
  },
  {
    icon: "MapPin",
    title: "Tes trajets et tes arrêts favoris",
    description: "Consulte les prochains passages et prépare l’aller ou le retour du lycée selon ton emploi du temps et ton domicile du jour.",
  },
  {
    icon: "Palette",
    title: "Des matières plus faciles à personnaliser",
    description: "Le nom de la matière, les couleurs et les emojis sont accessibles depuis le même écran.",
  },
  {
    icon: "Check",
    title: "Un démarrage plus régulier",
    description: "Le nouveau logo d’ouverture laisse place à l’accueil dès que l’écran est prêt.",
  },
] as const;

export default function ChangelogScreen() {
  const { colors } = useTheme();
  const { automatic } = useLocalSearchParams<{ automatic?: string }>();
  const [closing, setClosing] = useState(false);

  const close = async () => {
    if (closing) return;
    setClosing(true);
    try {
      if (automatic === "1") await AsyncStorage.setItem(CADENZA_RELEASE_KEY, "1");
    } finally {
      if (router.canGoBack()) router.back();
      else router.replace("/(tabs)");
    }
  };

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.background }}
      contentContainerStyle={{ flexGrow: 1, padding: 22, gap: 22 }}
      contentInsetAdjustmentBehavior="automatic"
    >
      <Stack.Screen options={{ title: "Nouveautés", gestureEnabled: automatic !== "1", headerBackVisible: automatic !== "1" }} />
      <View style={{ alignItems: "center", gap: 8, paddingVertical: 10 }}>
        <Image
          source={require("../assets/images/splash-mark.png")}
          style={{ width: 82, height: 82 }}
          accessibilityIgnoresInvertColors
        />
        <Typography variant="h2" align="center">Du nouveau dans Cadenza</Typography>
        <Typography color="textSecondary" align="center">{installedCadenzaVersionLabel}</Typography>
      </View>
      <View style={{ gap: 16 }}>
        {changes.map(change => (
          <View key={change.title} style={{ flexDirection: "row", alignItems: "flex-start", gap: 14 }}>
            <View style={{ width: 42, height: 42, borderRadius: 13, alignItems: "center", justifyContent: "center", backgroundColor: "#2776F820" }}>
              <Papicons name={change.icon} size={22} color={CADENZA_BLUE} />
            </View>
            <View style={{ flex: 1, gap: 4 }}>
              <Typography variant="title">{change.title}</Typography>
              <Typography color="textSecondary">{change.description}</Typography>
            </View>
          </View>
        ))}
      </View>
      <Button
        label={automatic === "1" ? "Continuer" : "Fermer"}
        fullWidth
        disabled={closing}
        onPress={() => { void close().catch(() => {}); }}
      />
    </ScrollView>
  );
}
