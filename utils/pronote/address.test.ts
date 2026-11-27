import { describe, expect, it } from "@jest/globals";
import { isPronotePairingCode, normalizePronoteAddress, parsePronoteQrCode } from "./address";

describe("PRONOTE student connection", () => {
  it("turns desktop and mobile student links into the same HTTPS base", () => {
    expect(normalizePronoteAddress(" https://schools.example/pronote/eleve.html?lang=fr ")).toBe("https://schools.example/pronote");
    expect(normalizePronoteAddress("https://schools.example/pronote/mobile.eleve.html")).toBe("https://schools.example/pronote");
  });
  it.each([
    "http://schools.example/pronote", "https://schools.example:8443/pronote",
    "https://reader:secret@schools.example/pronote", "https://local-school.local/pronote",
    "https://127.0.0.1/pronote", "https://schools.example/pronote/parent.html",
    "https://schools.example/pronote/other-login.html",
  ])("refuses %s for the pupil login", value => {
    expect(normalizePronoteAddress(value)).toBeUndefined();
  });
  it("verifies QR data and keeps the pupil access space", () => {
    const fields = { login: "fixture-user", jeton: "fixture-token" };
    expect(parsePronoteQrCode(JSON.stringify({ ...fields, url: "https://schools.example/pronote/mobile.eleve.html" }))).toEqual({
      ...fields, url: "https://schools.example/pronote/mobile.eleve.html",
    });
    expect(parsePronoteQrCode(JSON.stringify({ ...fields, url: "https://schools.example/pronote/parent.html" }))).toBeUndefined();
    expect(parsePronoteQrCode("not JSON")).toBeUndefined();
    expect(parsePronoteQrCode(JSON.stringify({ login: "fixture-user", url: "https://schools.example/pronote" }))).toBeUndefined();
    expect(isPronotePairingCode("0038")).toBe(true);
    expect(isPronotePairingCode("123")).toBe(false);
    expect(isPronotePairingCode("1A23")).toBe(false);
  });
});
