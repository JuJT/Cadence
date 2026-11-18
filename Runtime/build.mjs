import { build } from 'esbuild';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const result = await build({entryPoints:['src/entry.js'], bundle:true, platform:'browser', format:'iife',
  target:'safari17', minify:true, legalComments:'eof', write:false,
  define:{'process.env.NODE_ENV':'"production"'}, metafile:true});
const code=result.outputFiles[0].text;
await mkdir('../Resources/Pronote',{recursive:true});
await writeFile('../Resources/Pronote/pawnote.bundle.js',code);
await writeFile('../Resources/Pronote/runtime-manifest.json',JSON.stringify({library:'@blockshub/pawnote-lts',version:'1.6.4',
  sha256:createHash('sha256').update(code).digest('hex'),patch:'PapillonApp/Papillon, pinned source in Runtime/patches',
  bytes:Buffer.byteLength(code),license:'GPL-3.0-or-later'},null,2)+'\n');
console.log(`Pawnote browser bundle: ${Buffer.byteLength(code)} bytes`);
