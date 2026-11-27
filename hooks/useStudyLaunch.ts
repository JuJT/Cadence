import { useRef, useState } from "react";
import { Alert } from "react-native";

import { startStudy, StudySessionConflict, type SessionInput } from "@/stores/study";
import uuid from "@/utils/uuid/uuid";

const originPaths = {
  home: "/(tabs)",
  calendar: "/(tabs)/calendar",
  tasks: "/(tabs)/tasks",
  grades: "/(tabs)/grades",
} as const;

export type StudyOrigin = keyof typeof originPaths;

export function studyOrigin(path: unknown): StudyOrigin | undefined {
  if (path === "home" || path === "index" || path === "/") return "home";
  if (typeof path !== "string") return undefined;
  const [root] = path.replace(/^\//, "").split("/");
  if (root === "calendar" || root === "tasks" || root === "grades") return root;
  return undefined;
}

export function studyOriginPath(origin: StudyOrigin) {
  return originPaths[origin];
}

export function studyTimerHref(from?: StudyOrigin) {
  return {
    pathname: "/(tabs)/study",
    params: { section: "timer", open: uuid(), immersive: "1", ...(from ? { from } : {}) },
  } as const;
}

export function useStudyLaunch(open: () => void) {
  const locked = useRef(false);
  const [launching, setLaunching] = useState(false);

  const launch = async (request: SessionInput, attachTo?: string) => {
    if (locked.current) return;
    locked.current = true;
    setLaunching(true);
    try {
      await startStudy(request, attachTo);
      open();
    } catch (error) {
      if (error instanceof StudySessionConflict) {
        Alert.alert("Une séance est déjà en cours", request.task
          ? "Vous pouvez associer ce devoir à la séance en cours."
          : "Terminez la séance en cours avant d’en démarrer une autre.", [
          { text: "Annuler", style: "cancel" },
          { text: "Ouvrir la séance", onPress: open },
          ...(request.task ? [
            { text: "Associer le devoir", onPress: () => { void launch(request, error.sessionId); } },
          ] : []),
        ]);
      } else {
        Alert.alert("Révision", error instanceof Error ? error.message : "Impossible de démarrer la séance.");
      }
    } finally {
      locked.current = false;
      setLaunching(false);
    }
  };

  return { launch, launching };
}
