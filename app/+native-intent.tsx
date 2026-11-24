export function redirectSystemPath({ path }: { path: string }) {
  const link = path.match(/^cadence:\/\/\/?(study|calendar|tasks)\/?$/);
  if (link) return `/${link[1]}`;

  const detail = path.match(/^cadence:\/\/\/?(course|tasks)\/([\w.,:@+\-]+)$/);
  return detail ? `/${detail[1]}/${encodeURIComponent(detail[2])}` : "/";
}
