import {
  DoubleAuthMode,
  finishLoginManually,
  RefreshInformation,
  SecurityError,
  securityCheckCustomPassword,
  securityCheckPIN,
  securitySave,
  SessionHandle,
} from "@blockshub/pawnote-lts";

import { useAccountStore } from "@/stores/account";
import { Services } from "@/stores/account/types";
import { GetIdentityFromPronoteUsername } from "@/utils/pronote/name";

export async function resolvePronoteChallenge(
  session: SessionHandle, error: SecurityError,
  input: { mode?: DoubleAuthMode; pin?: string; password?: string; deviceName?: string },
): Promise<RefreshInformation> {
  const { handle } = error;
  const options: Parameters<typeof securitySave>[2] = {};
  if (handle.shouldCustomDoubleAuth) {
    if (input.mode === undefined || !handle.availableSecurityModes.includes(input.mode)) {
      throw new Error("Choisissez une méthode proposée par PRONOTE.");
    }
    options.mode = input.mode;
  }
  if (handle.shouldEnterPIN || input.mode === DoubleAuthMode.MGDA_SaisieCodePIN) {
    if (!input.pin || !/^\d{4}$/.test(input.pin) ||
        (handle.shouldEnterPIN && !await securityCheckPIN(session, input.pin))) {
      throw new Error("Vérifiez le code de sécurité à 4 chiffres.");
    }
    options.pin = input.pin;
  }
  if (handle.shouldCustomPassword) {
    if (!input.password || !await securityCheckCustomPassword(session, input.password)) {
      throw new Error("Le nouveau mot de passe ne respecte pas les règles de PRONOTE.");
    }
    options.password = input.password;
  }
  if (handle.shouldEnterSource || handle.shouldEnterPIN) {
    const name = input.deviceName?.trim().slice(0, 30) || "Cadenza";
    options.deviceName = name;
  }
  await securitySave(session, handle, options);
  const { authentication, identity, initialUsername } = handle.context;
  return finishLoginManually(session, authentication, identity, initialUsername);
}

export function storePronoteLogin(
  session: SessionHandle, refresh: RefreshInformation, deviceUUID: string,
  relink?: { accountId: string; serviceId: string },
) {
  const student = session.userResource ?? session.user.resources[0];
  if (!student || !refresh.token || !refresh.url || !refresh.username) {
    throw new Error("Le compte PRONOTE n’a pas pu être enregistré.");
  }
  const store = useAccountStore.getState();
  const auth = {
    accessToken: refresh.token,
    refreshToken: refresh.token,
    additionals: {
      instanceURL: refresh.url,
      kind: refresh.kind,
      username: refresh.username,
      navigatorIdentifier: refresh.navigatorIdentifier,
      deviceUUID,
    },
  };
  if (relink) {
    store.updateServiceAuthData(relink.serviceId, auth);
    store.setLastUsedAccount(relink.accountId);
    return;
  }
  const now = new Date().toISOString();
  const { firstName, lastName } = GetIdentityFromPronoteUsername(session.user.name);
  store.addAccount({
    id: deviceUUID, firstName, lastName, schoolName: student.establishmentName, className: student.className,
    services: [{ id: deviceUUID, auth, serviceId: Services.PRONOTE, createdAt: now, updatedAt: now }],
    createdAt: now, updatedAt: now,
  });
  store.setLastUsedAccount(deviceUUID);
}
