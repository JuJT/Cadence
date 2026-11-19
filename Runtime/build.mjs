import { build } from 'esbuild';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname } from 'node:path';
import {applyNewsCompatibility,newsCompatibilityID,newsProtocolProvenance} from './news-compatibility.mjs';
const patchManifest=JSON.parse(await readFile('patches/manifest.json','utf8'));
const runtimePackage=JSON.parse(await readFile('package.json','utf8'));
const sdkSourceHash=patchManifest.files['node_modules/@blockshub/pawnote-lts/dist/index.mjs'].patched;
let compatibilityApplied=false;
const result = await build({entryPoints:['src/entry.js'], bundle:true, platform:'browser', format:'iife',
  target:'safari17', minify:true, legalComments:'eof', write:false,
  define:{'process.env.NODE_ENV':'"production"'}, metafile:true,
  plugins:[{name:newsCompatibilityID,setup(build){
    build.onLoad({filter:/[\\/]@blockshub[\\/]pawnote-lts[\\/]dist[\\/]index\.mjs$/},async args=>{
      const source=await readFile(args.path,'utf8');
      if(createHash('sha256').update(source).digest('hex')!==sdkSourceHash)throw Error('Unpinned Pawnote SDK input');
      compatibilityApplied=true;
      return {contents:applyNewsCompatibility(source),loader:'js',resolveDir:dirname(args.path)};
    });
  }}]});
if(!compatibilityApplied)throw Error('Pawnote news compatibility was not applied');
const code=result.outputFiles[0].text;
await mkdir('../Resources/Pronote',{recursive:true});
await writeFile('../Resources/Pronote/pawnote.bundle.js',code);
await writeFile('../Resources/Pronote/runtime-manifest.json',JSON.stringify({library:'@blockshub/pawnote-lts',version:'1.6.4',
  runtimeVersion:runtimePackage.version,
  sha256:createHash('sha256').update(code).digest('hex'),patch:'PapillonApp/Papillon, pinned source in Runtime/patches',
  bytes:Buffer.byteLength(code),license:'GPL-3.0-or-later',sdkSourceHash,
  compatibility:{id:newsCompatibilityID,source:'https://demo.index-education.net/pronote/eleve.html',protocol:newsProtocolProvenance,
    news2026Empty:'supported',news2026Nonempty:'lazy read-only detail; optional recipient metadata does not block reading; unrecognized content forms preserve cache with an explicit error'}},null,2)+'\n');
console.log(`Pawnote browser bundle: ${Buffer.byteLength(code)} bytes`);
