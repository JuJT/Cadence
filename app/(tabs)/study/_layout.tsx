import { Stack } from "expo-router";
import { useScreenOptions } from "@/utils/theme/ScreenOptions";

export default function StudyLayout() {
  const screenOptions = useScreenOptions();
  return (
    <Stack screenOptions={screenOptions}>
      <Stack.Screen name="index" options={{ title: "Révision", headerLargeTitle: true, headerTransparent: false }} />
    </Stack>
  );
}
