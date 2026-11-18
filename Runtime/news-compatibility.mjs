// Index Education's public PRONOTE 2026 client now receives listeNatures.
// The public demo's empty reception list has been checked over the real API.
// Its public eleve_defer.js documents request kinds 0 (list) and 1 (detail),
// merging detailsActualite into the selected raw item, and nature as category.
// Details stay lazy. Unknown shapes fail instead of fabricating empty content.
export const newsCompatibilityID='cadenza-pronote2026-lazy-news-v2';
// Public publisher asset, inspected without authentication. No school rows are
// copied into this adapter or its entirely synthetic test fixtures.
export const newsProtocolProvenance=Object.freeze({
  sourceURL:'https://demo.index-education.net/pronote/E_3_C_26A61756062CEBB94B47B3C6829978280DB11D70F4823EE0434C06DDCB7796AA_L_1036/eleve_defer.js',
  sourceSHA256:'bb67d249720fffe00b3219c85aff891ee99094e992fa37ac7913cbe9cb286fd1',
  inspectedAtUTC:'2026-11-18',providerVersion:'2026.2.8'
});
const before='const t=e.listeCategories.V.map(ft);return{categories:t,items:e.listeModesAff[0].listeActualites.V.map';
const after='const __cadenzaCategories=e.listeCategories??e.listeNatures,__cadenzaModes=e.listeModesAff;'+
  'if(!__cadenzaCategories||!Array.isArray(__cadenzaCategories.V)||!Array.isArray(__cadenzaModes)||'+
  '!__cadenzaModes.every(v=>v&&v.listeActualites&&Array.isArray(v.listeActualites.V)))throw Error("UnsupportedNewsFormat");'+
  'if(e.listeCategories===undefined&&e.listeNatures!==undefined)return __cadenzaModernNewsList(e,s);'+
  'if(!__cadenzaModes.length)return{categories:__cadenzaCategories.V.map(ft),items:[]};'+
  'const t=__cadenzaCategories.V.map(ft);return{categories:t,items:__cadenzaModes[0].listeActualites.V.map';

export function transformNewsFunction(source){
  const count=source.split(before).length-1;
  if(count!==1)throw Error('Pinned Pawnote news implementation changed');
  return source.replace(before,after);
}

// These helpers are appended inside the already hash-verified Pawnote module,
// reusing its queue, authenticated RequestFN and decoders, never new crypto.
export const newsCompatibilityHelpers=String.raw`
const __cadenzaNewsRefs=new WeakMap();
function __cadenzaNewsFailure(){throw Error("UnsupportedNewsFormat");}
function __cadenzaNewsObject(v){return v!==null&&typeof v==="object"&&!Array.isArray(v);}
function __cadenzaNewsList(v){if(!__cadenzaNewsObject(v)||!Array.isArray(v.V))return __cadenzaNewsFailure();return v.V;}
function __cadenzaNewsID(v){if(typeof v!=="string"&&!(typeof v==="number"&&Number.isFinite(v)))return __cadenzaNewsFailure();const s=String(v);if(!s.length)return __cadenzaNewsFailure();return s;}
function __cadenzaNewsDate(v){if(!__cadenzaNewsObject(v)||typeof v.V!=="string")return __cadenzaNewsFailure();const date=le(v.V);if(!(date instanceof Date)||!Number.isFinite(date.getTime()))return __cadenzaNewsFailure();return date;}
function __cadenzaModernNewsList(raw,session){
  const categories=__cadenzaNewsList(raw.listeNatures).map(value=>{
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
        if(item[source]!==undefined)result[target]=__cadenzaNewsDate(item[source]);
      }
      const nature=item.nature;
      if(nature!==undefined){
        if(!__cadenzaNewsObject(nature)||!__cadenzaNewsObject(nature.V)||typeof nature.V.N!=="string")return __cadenzaNewsFailure();
        const category=categories.find(c=>c.id===nature.V.N);if(category)result.category=category;
      }
      refs.set(id,{raw:item,mode:mode.G,categories,decoded:null});items.push(result);
    }
  }
  __cadenzaNewsRefs.set(session,refs);return{categories,items};
}
function __cadenzaValidateNewsQuestions(item){
  const questions=__cadenzaNewsList(item.listeQuestions);
  if(item.estInformation&&questions.length!==1)return __cadenzaNewsFailure();
  for(const question of questions){
    if(!__cadenzaNewsObject(question)||typeof question.N!=="string"||!Number.isInteger(question.genreReponse))return __cadenzaNewsFailure();
    if(!__cadenzaNewsObject(question.reponse)||!__cadenzaNewsObject(question.reponse.V)||typeof question.reponse.V.avecReponse!=="boolean")return __cadenzaNewsFailure();
    if(!__cadenzaNewsObject(question.texte)||typeof question.texte.V!=="string")return __cadenzaNewsFailure();
    __cadenzaNewsList(question.listePiecesJointes);
    if(question.genreReponse!==1)__cadenzaNewsList(question.listeChoix);
  }
}
async function __cadenzaNewsDetail(session,id){
  const record=__cadenzaNewsRefs.get(session)?.get(String(id));
  if(!record)throw Error("MissingResource");
  if(record.decoded)return record.decoded;
  let item={...record.raw};
  if(!__cadenzaNewsObject(item.listeQuestions)||!Array.isArray(item.listeQuestions.V)){
    const properties=ne(session),request=new ae(session,"PageActualites",{
      [properties.signature]:{onglet:Q.News},
      [properties.data]:{genreRequeteActualite:1,modeAffActu:record.mode,actualite:record.raw}
    });
    const response=(await request.send()).data[properties.data];
    if(!__cadenzaNewsObject(response)||response.genreRequeteActualite!==1||!__cadenzaNewsObject(response.detailsActualite))return __cadenzaNewsFailure();
    item={...item,...response.detailsActualite};
  }
  if(__cadenzaNewsID(item.N)!==String(id))return __cadenzaNewsFailure();
  if(!item.estInformation&&!item.estSondage)return __cadenzaNewsFailure();
  if(!item.categorie){if(!__cadenzaNewsObject(item.nature)||!__cadenzaNewsObject(item.nature.V))return __cadenzaNewsFailure();item.categorie=item.nature;}
  if(!__cadenzaNewsObject(item.categorie.V)||typeof item.categorie.V.N!=="string"||!record.categories.some(c=>c.id===item.categorie.V.N))return __cadenzaNewsFailure();
  if(!__cadenzaNewsObject(item.public)||!("V"in item.public))return __cadenzaNewsFailure();
  __cadenzaNewsDate(item.dateCreation);__cadenzaNewsDate(item.dateDebut);__cadenzaNewsDate(item.dateFin);
  __cadenzaValidateNewsQuestions(item);
  try{
    const decoded=item.estInformation?ht(item,session,record.categories):gt(item,session,record.categories);
    decoded.detailsRequired=false;record.decoded=decoded;return decoded;
  }catch(_error){return __cadenzaNewsFailure();}
}
`;

export function applyNewsCompatibility(source){
  return transformNewsFunction(source)+'\n'+newsCompatibilityHelpers+'\nexport {__cadenzaNewsDetail as cadenzaNewsDetail};\n';
}
