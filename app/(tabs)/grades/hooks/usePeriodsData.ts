import { useCallback, useRef, useState } from "react";

import { useManagerSubscription } from "@/hooks/useManagerSubscription";
import { getManager, type AccountManager } from "@/services/shared";
import { gradePeriodKey, type Period } from "@/services/shared/grade";
import { Capabilities, type ServiceFailure } from "@/services/shared/types";
import { useAccountStore } from "@/stores/account";
import { getCurrentPeriod, sortGradePeriods } from "@/utils/grades/helper/period";
import { warn } from "@/utils/logger/logger";

export interface UsePeriodsDataResult {
  periods: Period[];
  currentPeriod: Period | undefined;
  setCurrentPeriod: (period: Period) => void;
  loading: boolean;
  refreshing: boolean;
  error: Error | null;
  failures: ServiceFailure[];
  refresh: () => Promise<void>;
}

export function usePeriodsData(): UsePeriodsDataResult {
  const accountId = useAccountStore(state => state.lastUsedAccount);
  const [snapshot, setSnapshot] = useState<{ accountId: string; periods: Period[] }>();
  const [selection, setSelection] = useState<{ accountId: string; key: string }>();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [failures, setFailures] = useState<ServiceFailure[]>([]);
  const request = useRef(0);

  const fetchPeriods = useCallback(async (manager: AccountManager, isRefresh = false) => {
    if (manager.getAccount().id !== accountId) return;
    const requestId = ++request.current;
    if (isRefresh) setRefreshing(true);
    else setLoading(true);
    setError(null);
    setFailures([]);

    try {
      const periods = sortGradePeriods(await manager.getGradesPeriods());
      if (request.current !== requestId) return;
      setFailures(manager.getFailures(Capabilities.GRADES));
      setSnapshot({ accountId, periods });
      setSelection(previous => previous?.accountId === accountId &&
        periods.some(period => gradePeriodKey(period) === previous.key) ? previous : undefined);
    } catch (e) {
      if (request.current !== requestId) return;
      warn(String(e), "usePeriodsData");
      setFailures(manager.getFailures(Capabilities.GRADES));
      setError(e instanceof Error ? e : new Error(String(e)));
    } finally {
      if (request.current === requestId) {
        setLoading(false);
        setRefreshing(false);
      }
    }
  }, [accountId]);

  const handleManager = useCallback((manager: AccountManager) => {
    void fetchPeriods(manager);
  }, [fetchPeriods]);

  const handleManagerUnavailable = useCallback(() => {
    request.current++;
    setLoading(false);
    setRefreshing(false);
    setError(new Error("Account manager unavailable"));
  }, []);

  useManagerSubscription(handleManager, handleManagerUnavailable);

  const setCurrentPeriod = useCallback((period: Period) => {
    setSelection({ accountId, key: gradePeriodKey(period) });
  }, [accountId]);

  const refresh = useCallback(async () => {
    const manager = getManager();
    if (!manager || manager.getAccount().id !== accountId) {
      handleManagerUnavailable();
      return;
    }
    await fetchPeriods(manager, true);
  }, [accountId, fetchPeriods, handleManagerUnavailable]);

  const periods = snapshot?.accountId === accountId ? snapshot.periods : [];
  const manual = selection?.accountId === accountId
    ? periods.find(period => gradePeriodKey(period) === selection.key)
    : undefined;

  return {
    periods,
    currentPeriod: manual ?? getCurrentPeriod(periods),
    setCurrentPeriod,
    loading,
    refreshing,
    error,
    failures,
    refresh,
  };
}
