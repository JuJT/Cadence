import { beforeEach, describe, expect, it, jest } from "@jest/globals";
import {
  DoubleAuthMode, SecurityError, SessionHandle, finishLoginManually, securityCheckPIN, securitySave,
} from "@blockshub/pawnote-lts";

import { resolvePronoteChallenge } from "./sign-in";

jest.mock("@/stores/account", () => ({ useAccountStore: { getState: jest.fn() } }));
jest.mock("@blockshub/pawnote-lts", () => ({
  DoubleAuthMode: { MGDA_SaisieCodePIN: 3 },
  finishLoginManually: jest.fn(),
  securityCheckCustomPassword: jest.fn(),
  securityCheckPIN: jest.fn(),
  securitySave: jest.fn(),
}));

const session = {} as SessionHandle;
const context = { authentication: {}, identity: {}, initialUsername: "fixture" };
function challenge(overrides: Partial<SecurityError["handle"]>): SecurityError {
  return { handle: { availableSecurityModes: [], context, ...overrides } } as SecurityError;
}

describe("PRONOTE security challenge", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("saves the newly requested PIN and mode without verifying it as a preexisting code", async () => {
    const mode = DoubleAuthMode.MGDA_SaisieCodePIN;
    const verification = challenge({ shouldCustomDoubleAuth: true, availableSecurityModes: [mode] });
    await resolvePronoteChallenge(session, verification, { mode, pin: "0316" });
    expect(securityCheckPIN).not.toHaveBeenCalled();
    expect(securitySave).toHaveBeenCalledWith(session, verification.handle, { mode, pin: "0316" });
    expect(finishLoginManually).toHaveBeenCalledWith(session, context.authentication, context.identity, "fixture");
  });

  it("does not save or authenticate again when the preexisting PIN is refused", async () => {
    jest.mocked(securityCheckPIN).mockResolvedValueOnce(false);
    await expect(resolvePronoteChallenge(session, challenge({ shouldEnterPIN: true }), { pin: "0316" })).rejects.toThrow();
    expect(securityCheckPIN).toHaveBeenCalledWith(session, "0316");
    expect(securitySave).not.toHaveBeenCalled();
    expect(finishLoginManually).not.toHaveBeenCalled();
  });
});
