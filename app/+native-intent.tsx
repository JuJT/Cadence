const ALLOWED_DEEPLINKS_SCHEME = new Set<string>([])

export function redirectSystemPath({ path }: { path: string }) {
    if (path === "cadence://study" || path === "cadence://study/") return "/study"
    const scheme = path.split(":")[0].toLowerCase()
    return ALLOWED_DEEPLINKS_SCHEME.has(scheme) ? path : "/"
}
