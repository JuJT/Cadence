/** Normalize the public HTTPS base of a PRONOTE pupil portal. */
export function normalizePronoteAddress(input: string): string | undefined {
  try {
    const value = input.trim();
    if (!/^https:\/\//i.test(value) || /[\s\\]/.test(value)) return undefined;
    const url = new URL(value);
    if (url.username || url.password || url.port) return undefined;
    const host = url.hostname.toLowerCase();
    if (!host.includes(".") || !/^[a-z0-9.-]+$/.test(host) ||
        host === "localhost" || /\.(local|localhost|internal)$/.test(host) ||
        /^[0-9.]+$/.test(host)) return undefined;
    const path = url.pathname.replace(/\/+$/, "").replace(/\/(?:mobile\.)?eleve\.html$/i, "");
    if (!/^(?:\/[a-z0-9_-]+)*$/i.test(path)) return undefined;
    return url.origin + path;
  } catch {
    return undefined;
  }
}

export function parsePronoteQrCode(raw: string) {
  try {
    if (raw.length > 8192) return undefined;
    const payload: unknown = JSON.parse(raw);
    if (!payload || typeof payload !== "object" || !("jeton" in payload) || !("login" in payload) ||
        !("url" in payload) || typeof payload.jeton !== "string" || !payload.jeton ||
        typeof payload.login !== "string" || !payload.login || typeof payload.url !== "string") return undefined;
    const url = normalizePronoteAddress(payload.url);
    if (!url || /(?:parent|professeur|direction)\.html(?:[?#]|$)/i.test(payload.url)) return undefined;
    // Keep the access-space URL. Pawnote derives the account kind from this URL.
    const access = new URL(payload.url);
    const page = /\/(?:mobile\.)?eleve\.html$/i.test(access.pathname)
      ? access.pathname.slice(access.pathname.lastIndexOf("/"))
      : "/eleve.html";
    return { jeton: payload.jeton, login: payload.login, url: url + page };
  } catch {
    return undefined;
  }
}

export function isPronotePairingCode(code: string): boolean {
  return /^\d{4}$/.test(code);
}
