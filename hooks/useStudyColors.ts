import { useTheme } from "expo-router/react-navigation";

import type { createDefaultTheme } from "@/utils/theme/Theme";

export function useStudyColors() {
  return (useTheme() as ReturnType<typeof createDefaultTheme>).colors;
}
