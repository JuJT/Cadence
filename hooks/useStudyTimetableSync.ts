import { useEffect } from "react";
import { AppState } from "react-native";

import { useAccountStore } from "@/stores/account";
import { refreshStudySurface } from "@/stores/study";

export function useStudyTimetableSync() {
  const profileId = useAccountStore(state => state.lastUsedAccount);

  useEffect(() => { refreshStudySurface(); }, [profileId]);

  useEffect(() => {
    const subscription = AppState.addEventListener("change", phase => {
      if (phase === "active") refreshStudySurface();
    });
    return () => subscription.remove();
  }, []);
}
