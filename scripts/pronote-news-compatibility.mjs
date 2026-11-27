// Index Education's public PRONOTE 2026 client now receives listeNatures.
// The public demo's empty reception list has been checked over the real API.
// Its public eleve_defer.js documents request kinds 0 (list) and 1 (detail),
// merging detailsActualite into the selected raw item, and nature as category.
// Details stay lazy. Unknown shapes fail instead of fabricating empty content.
export const newsCompatibilityID='cadenza-pronote2026-recipient-news-v4';
// Public publisher asset, inspected without authentication. No school rows are
// copied into this adapter or its entirely synthetic test fixtures.
export const newsProtocolProvenance=Object.freeze({
  sourceURL:'https://demo.index-education.net/pronote/E_3_C_26A61756062CEBB94B47B3C6829978280DB11D70F4823EE0434C06DDCB7796AA_L_1036/eleve_defer.js',
  sourceSHA256:'ebcc104485a3f99a30600e67c871a235d24ad06c4450c75e6948f127f3c4fa42',
  inspectedAtUTC:'2026-11-19',providerVersion:'2026.2.8',
  readRecipientReference:'https://github.com/bain3/pronotepy/blob/0a71edade4b1795b7a429e50177656c23d3d1f36/pronotepy/dataClasses.py'
});
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

const before='const t=e.listeCategories.V.map(ft);return{categories:t,items:e.listeModesAff[0].listeActualites.V.map';
const after='const __cadenzaCategories=e.listeNatures?.V===null?{V:[]}:(e.listeNatures??e.listeCategories??(e.listeNatures===null?{V:[]}:undefined)),__cadenzaModes=e.listeModesAff;'+
  'if(!__cadenzaCategories||!Array.isArray(__cadenzaCategories.V)||!Array.isArray(__cadenzaModes)||'+
  '!__cadenzaModes.every(v=>v&&v.listeActualites&&Array.isArray(v.listeActualites.V)))throw Error("UnsupportedNewsFormat");'+
  'if(e.listeNatures!==undefined)return __cadenzaModernNewsList(e,s);'+
  'if(!__cadenzaModes.length)return{categories:__cadenzaCategories.V.map(ft),items:[]};'+
  'const t=__cadenzaCategories.V.map(ft);return{categories:t,items:__cadenzaModes[0].listeActualites.V.map';

// These helpers are appended inside the already hash-verified Pawnote module,
// reusing its queue, authenticated RequestFN and decoders, never new crypto.
export const newsCompatibilityHelpers=String.raw`
const __cadenzaNewsRefs=new WeakMap();
function __cadenzaNewsFailure(){throw Error("UnsupportedNewsFormat");}
function __cadenzaNewsObject(v){return v!==null&&typeof v==="object"&&!Array.isArray(v);}
function __cadenzaNewsList(v){if(!__cadenzaNewsObject(v)||!Array.isArray(v.V))return __cadenzaNewsFailure();return v.V;}
function __cadenzaNewsID(v){if(typeof v!=="string"&&!(typeof v==="number"&&Number.isFinite(v)))return __cadenzaNewsFailure();const s=String(v);if(!s.length)return __cadenzaNewsFailure();return s;}
function __cadenzaNewsDate(v){if(!__cadenzaNewsObject(v)||typeof v.V!=="string")return __cadenzaNewsFailure();const date=le(v.V);if(!(date instanceof Date)||!Number.isFinite(date.getTime()))return __cadenzaNewsFailure();return date;}
// The read endpoint expects an unwrapped recipient identity. A list row's
// display metadata (or its typed public.V wrapper) is not a request payload.
function __cadenzaNewsReference(row,session){
  const target=row.public?.V??row.public;
  const account=session.user;
  const recipient=target?.N!=null&&Number.isInteger(target.G)?{N:target.N,G:target.G}:
    account?.id!=null&&Number.isInteger(account.kind)?{N:account.id,G:account.kind}:null;
  if(!recipient)return __cadenzaNewsFailure();
  return {N:row.N,genrePublic:Number.isInteger(row.genrePublic)?row.genrePublic:recipient.G,public:recipient};
}
function __cadenzaModernNewsList(raw,session){
  const categories=(raw.listeNatures==null||raw.listeNatures.V===null?[]:__cadenzaNewsList(raw.listeNatures)).filter(value=>value!=null).map(value=>{
    if(!__cadenzaNewsObject(value)||typeof value.N!=="string"||typeof value.L!=="string")return __cadenzaNewsFailure();return ft(value);
  });
  const refs=new Map(),items=[];
  for(const mode of raw.listeModesAff){
    if(!__cadenzaNewsObject(mode)||!Number.isInteger(mode.G)||mode.G!==0)return __cadenzaNewsFailure();
    for(const item of __cadenzaNewsList(mode.listeActualites)){
      if(!__cadenzaNewsObject(item)||(!item.estInformation&&!item.estSondage))return __cadenzaNewsFailure();
      const id=__cadenzaNewsID(item.N);
      if(refs.has(id))return __cadenzaNewsFailure();
      const result={id,is:item.estInformation?"information":"survey",detailsRequired:true};
      if(typeof item.L==="string")result.title=item.L;
      if(typeof item.auteur==="string")result.author=item.auteur;
      if(typeof item.lue==="boolean")result.read=item.lue;
      for(const [source,target]of [["dateCreation","creationDate"],["dateDebut","startDate"],["dateFin","endDate"]]){
        if(item[source]?.V!=null)result[target]=__cadenzaNewsDate(item[source]);
      }
      const nature=item.nature;
      if(nature!=null&&nature.V!=null&&nature.V.N!=null){
        if(!__cadenzaNewsObject(nature)||!__cadenzaNewsObject(nature.V)||typeof nature.V.N!=="string")return __cadenzaNewsFailure();
        const category=categories.find(c=>c.id===nature.V.N);if(category)result.category=category;
      }
      refs.set(id,{raw:item,mode:mode.G,categories,decoded:null});items.push(result);
    }
  }
  __cadenzaNewsRefs.set(session,refs);return{categories,items};
}
function __cadenzaDecodeNewsQuestions(item,session){
  const questions=__cadenzaNewsList(item.listeQuestions);
  if(item.estInformation&&!questions.length)return __cadenzaNewsFailure();
  return questions.map(question=>{
    if(!__cadenzaNewsObject(question))return __cadenzaNewsFailure();
    const kind=question.genreReponse,content=question.texte?.V??question.texte;
    const files=question.listePiecesJointes?.V==null?[]:__cadenzaNewsList(question.listePiecesJointes).filter(value=>value!=null);
    if(typeof content!=="string"&&!files.length&&typeof question.titre!=="string")return __cadenzaNewsFailure();
    const rawChoices=question.listeChoix?.V==null?[]:__cadenzaNewsList(question.listeChoix).filter(value=>value!=null);
    const reply=__cadenzaNewsObject(question.reponse?.V)?question.reponse.V:null;
    const result={kind,content:typeof content==="string"?content:"",fullTitle:question.L,title:question.titre,position:question.rang,
      attachments:files.map(file=>De(file,session)),choices:rawChoices.map(choice=>({value:choice.L,position:choice.rang,isTextInput:!!choice.estReponseLibre}))};
    if(question.N!=null)result.id=__cadenzaNewsID(question.N);
    // Read-only articles do not require recipient/answer metadata. Do not
    // manufacture an acknowledgment when the server has not supplied it.
    if(reply){
      if(typeof reply.avecReponse==="boolean")result.answered=reply.avecReponse;
      if(typeof reply.estReponseAttendue==="boolean")result.shouldAnswer=reply.estReponseAttendue;
      if(reply.N!=null)result.answerID=__cadenzaNewsID(reply.N);
      if(reply.reponduLe?.V!=null)result.answerDate=__cadenzaNewsDate(reply.reponduLe);
      if(typeof reply.valeurReponse==="string")result.textInputAnswer=reply.valeurReponse;
    }
    return result;
  });
}
function __cadenzaDecodeModernNews(item,session,categories){
  const questions=__cadenzaDecodeNewsQuestions(item,session);
  const result={id:__cadenzaNewsID(item.N),is:item.estInformation?"information":"survey",title:item.L,
    author:item.auteur,read:item.lue,detailsRequired:false};
  const categoryID=item.nature?.V?.N??item.categorie?.V?.N;
  if(categoryID!==undefined)result.category=categories.find(c=>String(c.id)===String(categoryID));
  for(const [source,target]of [["dateCreation","creationDate"],["dateDebut","startDate"],["dateFin","endDate"]]){
    if(item[source]?.V!=null)result[target]=__cadenzaNewsDate(item[source]);
  }
  if(__cadenzaNewsObject(item.public)&&"V"in item.public)result.public=item.public.V;
  if(item.estInformation){
    const question=questions[0];result.question=question;
    result.content=questions.map(part=>part.content||part.title).filter(Boolean).join("\n\n");
    result.attachments=questions.flatMap(part=>part.attachments);
    if(typeof question.answered==="boolean")result.acknowledged=question.answered;
    if(question.answerDate!==undefined)result.acknowledgedDate=question.answerDate;
    // Pawnote's write serializer needs a numeric answer ID and public.G. A
    // readable article is not sufficient authorization metadata for that write.
    const validAnswer=typeof question.answerID==="string"&&/^\d+$/.test(question.answerID)&&Number.isSafeInteger(Number(question.answerID));
    result.acknowledgementAvailable=questions.length===1&&question.id!=null&&question.kind===0&&typeof question.answered==="boolean"&&typeof question.shouldAnswer==="boolean"&&validAnswer&&
      __cadenzaNewsObject(result.public)&&Number.isInteger(result.public.G);
    result.needToAcknowledge=result.acknowledgementAvailable&&question.shouldAnswer===true;
  }else{result.questions=questions;result.isAnonymous=item.reponseAnonyme;}
  return result;
}
async function __cadenzaNewsDetail(session,id){
  const record=__cadenzaNewsRefs.get(session)?.get(String(id));
  if(!record)throw Error("MissingResource");
  if(record.decoded)return record.decoded;
  let item={...record.raw};
  if(!Array.isArray(item.listeQuestions?.V)||!item.listeQuestions.V.length){
    const properties=ne(session),request=new ae(session,"PageActualites",{
      [properties.signature]:{onglet:Q.News},
      [properties.data]:{genreRequeteActualite:1,modeAffActu:record.mode,actualite:__cadenzaNewsReference(item,session)}
    });
    const response=(await request.send()).data[properties.data];
    if(!__cadenzaNewsObject(response)||(response.genreRequeteActualite!=null&&response.genreRequeteActualite!==1)||!__cadenzaNewsObject(response.detailsActualite))return __cadenzaNewsFailure();
    item={...item,...response.detailsActualite};
  }
  if(__cadenzaNewsID(item.N)!==String(id))return __cadenzaNewsFailure();
  if(!item.estInformation&&!item.estSondage)return __cadenzaNewsFailure();
  try{
    const decoded=__cadenzaDecodeModernNews(item,session,record.categories);
    record.decoded=decoded;return decoded;
  }catch(_error){return __cadenzaNewsFailure();}
}
`;


// Installs alongside the existing token rotation patch in both SDK entrypoints.
// Current aliases are from @blockshub/pawnote-lts 1.6.4's published bundles.
const require = createRequire(import.meta.url);
const sdkRoot = dirname(require.resolve("@blockshub/pawnote-lts"));
const artifacts = [
  {
    file: "index.mjs",
    aliases: {},
    exportCode: "export {__cadenzaNewsDetail as cadenzaNewsDetail};",
    bulletin: { readName: "_s", pdfName: "xs", exportCode: "export {cadenzaGradebookOverview};" },
  },
  {
    file: "index.js",
    aliases: {ft:"xs", le:"te", De:"ue", ne:"W", ae:"Y", Q:"G"},
    exportCode: "exports.cadenzaNewsDetail=__cadenzaNewsDetail;",
    bulletin: { readName: "exports.gradebook", pdfName: "as", exportCode: "exports.cadenzaGradebookOverview=cadenzaGradebookOverview;" },
  },
];
// The bulletin service list can omit class statistics and group titles when
// the school hides them. PRONOTE's public 2026.2.8 demo exercises that case.
export const gradebookOverviewDecoder = String.raw`
function __cadenzaDecodeGradebook(data) {
  if (!data || Object.keys(data).length === 0 || data.message) return null;
  const subjects = data.ListeServices?.V;
  const remarks = data.ObjetListeAppreciations?.V?.ListeAppreciations?.V;
  if (!Array.isArray(subjects) && !Array.isArray(remarks)) {
    throw new Error("UnsupportedGradebookFormat");
  }
  function optionalNumber(wrapper) {
    const raw = wrapper?.V;
    if (typeof raw !== "number" && (typeof raw !== "string" || !raw.trim())) return undefined;
    const value = Number(String(raw).trim().replace(",", "."));
    return Number.isFinite(value) ? value : undefined;
  }
  return {
    overall: (Array.isArray(remarks) ? remarks : []).flatMap(remark =>
      typeof remark?.L === "string" && remark.L.trim()
        ? [{ name: typeof remark.Intitule === "string" ? remark.Intitule : "", value: remark.L }]
        : []
    ),
    subjects: (Array.isArray(subjects) ? subjects : []).flatMap(subject => {
      if (!subject || typeof subject !== "object") return [];
      const name = [subject.Matiere?.V?.L, subject.L, subject.SurMatiere?.V?.L]
        .find(value => typeof value === "string" && value.trim());
      if (!name) return [];
      const group = subject.SurMatiere?.V?.L;
      return [{
        name,
        group: typeof group === "string" ? group : undefined,
        average: optionalNumber(subject.MoyenneEleve),
        classAverage: optionalNumber(subject.MoyenneClasse),
        assessments: (Array.isArray(subject.ListeAppreciations?.V) ? subject.ListeAppreciations.V : [])
          .flatMap(line => typeof line?.L === "string" && line.L.trim() ? [line.L] : []),
      }];
    }),
  };
}
`;

// Separate read-only PageBulletins from generation of a PDF, leaving the
// published gradebook() API and PDF behavior unchanged for existing callers.
export function separateGradebookPDF(source, readName, pdfName) {
  const separator = readName + '=async(e,s)=>';
  const readStart = source.indexOf(separator);
  const pageStart = source.indexOf('"PageBulletins"', readStart);
  const decoder = "return await(async(e,s,t)=>{";
  const decoderStart = source.indexOf(decoder, pageStart);
  const pdf = "url:await " + pdfName + "(e,s)";
  const pdfStart = source.indexOf(pdf, decoderStart);
  if (readStart < 0 || pageStart < 0 || decoderStart < 0 || pdfStart < 0 || pdfStart - readStart > 1500) {
    throw new Error("Pawnote 1.6.4 bulletin code changed");
  }
  return source.slice(0, readStart) + readName + "=async(e,s,withPDF=true)=>" +
    source.slice(readStart + separator.length, decoderStart + decoder.length) +
    "if(!withPDF)return __cadenzaDecodeGradebook(t);" +
    source.slice(decoderStart + decoder.length);
}

for (const { file, aliases, exportCode, bulletin } of artifacts) {
  const path = join(sdkRoot, file);
  const source = readFileSync(path, "utf8");
  let installed = source;
  if (!installed.includes(exportCode)) {
    const bindAliases = code => Object.entries(aliases).reduce((value, [from, to]) =>
      value.replace(new RegExp('\\b' + from + '\\b', 'g'), to), code);
    const expected = bindAliases(before);
    if (installed.split(expected).length !== 2) {
      throw new Error("Pawnote 1.6.4 news code changed in " + file);
    }
    installed = installed.replace(expected, bindAliases(after)) + "\n" +
      bindAliases(newsCompatibilityHelpers) + "\n" + exportCode + "\n";
  }
  if (!installed.includes(bulletin.exportCode)) {
    installed = separateGradebookPDF(installed, bulletin.readName, bulletin.pdfName) + "\n" + gradebookOverviewDecoder +
      "\nconst cadenzaGradebookOverview=(session,period)=>" + bulletin.readName + "(session,period,false);\n" +
      bulletin.exportCode + "\n";
  }
  if (installed !== source) writeFileSync(path, installed);
}
