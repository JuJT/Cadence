export type CadenzaRelease = {
  version: string;
  page: string;
  notes: string;
  asset?: { name: string; url: string; size: number; sha256?: string };
};

const repository = "https://github.com/JuJT/Cadence";
const latest = "https://api.github.com/repos/JuJT/Cadence/releases/latest";

type GitHubAsset = { name?: string; browser_download_url?: string; state?: string; size: number; digest?: string };
type GitHubRelease = { tag_name?: string; html_url?: string; draft?: boolean; prerelease?: boolean; body?: string; assets?: GitHubAsset[] };

function versionParts(value: string) {
  if (!/^\d+\.\d+\.\d+$/.test(value)) throw new Error("Version invalide");
  const parts = value.split(".").map(Number);
  if (parts.some(part => !Number.isSafeInteger(part))) throw new Error("Version invalide");
  return parts;
}

export async function fetchCadenzaRelease(installed: string, signal?: AbortSignal): Promise<CadenzaRelease | null> {
  const response = await fetch(latest, { signal, headers: { Accept: "application/vnd.github+json" } });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub ${response.status}`);
  const release = await response.json() as GitHubRelease;
  const tag = typeof release.tag_name === "string" ? release.tag_name : "";
  const version = tag.replace(/^v/, "");
  const remote = versionParts(version);
  const local = versionParts(installed);
  const page = `${repository}/releases/tag/${tag}`;
  if (release.draft || release.prerelease || release.html_url !== page) throw new Error("Version invalide");
  const difference = remote.findIndex((part, index) => part !== local[index]);
  if (difference < 0 || remote[difference] < local[difference]) return null;
  const name = `Cadenza-iPhone-${version}.ipa`;
  const url = `${repository}/releases/download/${tag}/${name}`;
  const installer = Array.isArray(release.assets) && release.assets.find(asset => asset.name === name &&
    asset.browser_download_url === url && asset.state === "uploaded" && Number.isSafeInteger(asset.size) && asset.size > 0);
  return {
    version, page,
    notes: typeof release.body === "string" ? release.body.slice(0, 12_000) : "",
    asset: installer ? { name, url, size: installer.size,
      sha256: installer.digest && /^sha256:[0-9a-f]{64}$/.test(installer.digest) ? installer.digest.slice(7) : undefined } : undefined,
  };
}
