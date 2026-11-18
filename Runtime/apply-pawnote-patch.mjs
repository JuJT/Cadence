import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const hash = text => createHash('sha256').update(text).digest('hex');
const manifest = JSON.parse(await readFile('patches/manifest.json','utf8'));
const patch = await readFile('patches/@blockshub+pawnote-lts+1.6.4.patch','utf8');
if (hash(patch) !== manifest.patchSHA256) throw Error('Pawnote patch integrity mismatch');
for (const part of patch.split(/^diff --git /m).slice(1)) {
  const name = part.match(/^a\/(\S+) b\/(\S+)/)?.[2];
  if (!/^node_modules\/@blockshub\/pawnote-lts\/dist\/index\.(?:js|mjs|d\.ts|d\.mts)$/.test(name ?? '')) throw Error('Unexpected patch path');
  const bytes = await readFile(name);
  const expected = manifest.files[name];
  if (!expected) throw Error('Unpinned patch file');
  if (hash(bytes) === expected.patched) continue;
  if (hash(bytes) !== expected.original) throw Error('Pawnote input changed');
  const original = bytes.toString('utf8').split('\n');
  const lines = part.split('\n'), output=[];
  let cursor=0;
  for (let i=0;i<lines.length;i++) {
    const match=lines[i].match(/^@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@/);
    if (!match) continue;
    const start=Number(match[1])-1;
    if (start<cursor) throw Error('Overlapping patch');
    output.push(...original.slice(cursor,start));cursor=start;
    while (++i < lines.length && !lines[i].startsWith('@@ ')) {
      const line=lines[i], prefix=line[0], value=line.slice(1);
      if (prefix===' ' || prefix==='-') {
        if (original[cursor] !== value) throw Error('Pawnote patch context changed');
        if (prefix===' ') output.push(value);
        cursor++;
      } else if (prefix==='+') output.push(value);
      else if (line.startsWith('\\ No newline')) continue;
      else if (line==='') break;
      else throw Error('Unsupported patch format');
    }
    i--;
  }
  output.push(...original.slice(cursor));
  const patched=output.join('\n');
  if (hash(patched)!==expected.patched) throw Error('Pawnote result integrity mismatch');
  await writeFile(name,patched);
}
console.log('Verified Papillon Pawnote compatibility patch applied.');
