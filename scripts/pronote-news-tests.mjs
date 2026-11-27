import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import * as api from '@blockshub/pawnote-lts';
import {newsCompatibilityHelpers} from './pronote-news-compatibility.mjs';

function setup(payload,detailReply){
  const calls=[],session={user:{id:'demo-student',kind:4}};
  const scope={Date,
    ne:()=>({signature:'signature',data:'data'}),Q:{News:8},at:()=> '[0]',
    ae:class{constructor(_s,name,body){this.body=body;calls.push({name,body});}async send(){
      if(this.body.data.genreRequeteActualite===1){
        if(detailReply instanceof Error)throw detailReply;
        return {data:{data:detailReply}};
      }
      return {data:{data:payload}};
    }},
    le:value=>new Date(value),
    De:value=>({id:value.N,name:value.L,url:value.url}),
    ft:value=>({id:value.N,name:value.L,default:value.estDefaut??false}),
    ht:(value,_session,categories)=>({id:value.N,is:'information',title:value.L,
      category:categories.find(c=>c.id===value.categorie.V.N),content:value.listeQuestions.V[0].texte.V,
      attachments:value.listeQuestions.V[0].listePiecesJointes.V,question:value.listeQuestions.V[0],public:value.public.V}),
    gt:(value,_session,categories)=>({id:value.N,is:'survey',title:value.L,category:categories.find(c=>c.id===value.categorie.V.N),questions:value.listeQuestions.V}),
    E:Error};
  const context=vm.createContext(scope);
  vm.runInContext(newsCompatibilityHelpers+'\nglobalThis.testNews=('+api.news.toString()+');globalThis.testDetails=__cadenzaNewsDetail;',context);
  return {list:()=>scope.testNews(session),details:(id,selectedSession=session)=>scope.testDetails(selectedSession,id),calls,session};
}
const category={N:'fictional-category',L:'Catégorie fictive',estDefaut:true};
const modes=items=>[{G:0,listeActualites:{_T:24,V:items}}];
const question=()=>({N:'fictional-question',genreReponse:0,texte:{_T:21,V:'Contenu pédagogique fictif'},
  reponse:{V:{N:'fictional-answer',avecReponse:false,estReponseAttendue:true}},listePiecesJointes:{V:[]},listeChoix:{V:[]}});
const metadata=()=>({N:'fixture-news',L:'Information fictive',estInformation:true,nature:{V:{N:category.N}},
  auteur:'Auteur fictif',lue:false,dateCreation:{V:'2026-11-16T08:00:00'},dateDebut:{V:'2026-11-16T00:00:00'},dateFin:{V:'2026-12-16T00:00:00'}});
const complete=()=>({...metadata(),public:{V:{N:'fictional-public'}},listeQuestions:{V:[question()]}});
const modern=items=>({listeNatures:{_T:24,V:[category]},listeModesAff:modes(items),genreRequeteActualite:0});
const plain=value=>JSON.parse(JSON.stringify(value));

test('legacy empty news keeps categories and calls only the read endpoint',async()=>{
  const f=setup({listeCategories:{V:[category]},listeModesAff:modes([])});
  assert.deepEqual(plain(await f.list()),{categories:[{id:category.N,name:category.L,default:true}],items:[]});
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].name,'PageActualites');assert.equal(f.calls[0].body.signature.onglet,8);
});
test('observed PRONOTE2026 empty form uses listeNatures without inventing rows',async()=>{
  const categories=Array.from({length:9},(_,i)=>({...category,N:'fixture-'+i}));
  const f=setup({listeNatures:{_T:24,V:categories},listeModesAff:modes([]),genreRequeteActualite:0});
  const value=await f.list();assert.equal(value.categories.length,9);assert.equal(value.items.length,0);assert.equal(f.calls.length,1);
});
test('modern nonempty news lists metadata without requesting details or marking it read',async()=>{
  const f=setup(modern([metadata()]));const result=await f.list();
  assert.equal(f.calls.length,1);assert.equal(result.items[0].id,'fixture-news');assert.equal(result.items[0].detailsRequired,true);
  assert.equal(result.items[0].read,false);assert.equal('content'in result.items[0],false);assert.equal('question'in result.items[0],false);
});
test('modern information details use the official read-only request and are cached in the session',async()=>{
  const f=setup(modern([metadata()]),{genreRequeteActualite:1,detailsActualite:complete()});
  await f.list();const result=await f.details('fixture-news');
  assert.equal(result.detailsRequired,false);assert.equal(result.content,'Contenu pédagogique fictif');assert.equal(result.category.name,category.L);
  assert.equal(f.calls.length,2);const request=f.calls[1];assert.equal(request.name,'PageActualites');
  assert.equal(request.body.data.genreRequeteActualite,1);assert.equal(request.body.data.modeAffActu,0);
  assert.deepEqual(plain(request.body.data.actualite),{N:'fixture-news',genrePublic:4,public:{N:'demo-student',G:4}});
  assert.equal('marqueLueSeulement'in request.body.data,false);
  assert.equal(await f.details('fixture-news'),result);assert.equal(f.calls.length,2);
});
test('a recipient supplied by the list is unwrapped for the detail request',async()=>{
  const row={...metadata(),public:{_T:24,V:{N:'specific-recipient',G:2,L:'display name'}},genrePublic:9,listeQuestions:{V:[]}};
  const f=setup(modern([row]),{detailsActualite:{listeQuestions:{V:[{texte:{V:'Texte seul'}}]}}});
  await f.list();const value=await f.details(row.N);
  assert.deepEqual(plain(f.calls[1].body.data.actualite),{N:row.N,genrePublic:9,public:{N:'specific-recipient',G:2}});
  assert.equal(value.content,'Texte seul');assert.equal(value.needToAcknowledge,false);
});
test('multipart information retains ordered text and attachment-only components',async()=>{
  const f=setup(modern([metadata()]),{genreRequeteActualite:1,detailsActualite:{listeQuestions:{V:[
    {texte:{V:'Premier bloc'}},{texte:'Second bloc'},{listePiecesJointes:{V:[{N:'file',L:'Document',url:'https://example.com/document'}]}}
  ]}}});
  await f.list();const value=await f.details('fixture-news');
  assert.equal(value.content,'Premier bloc\n\nSecond bloc');
  assert.equal(value.attachments.length,1);assert.equal(value.needToAcknowledge,false);
});
test('modern survey detail keeps all published questions without sending an answer',async()=>{
  const item={...metadata(),estInformation:false,estSondage:true};
  const details={...complete(),...item,listeQuestions:{V:[question(),{...question(),N:'other-question'}]}};
  const f=setup(modern([item]),{genreRequeteActualite:1,detailsActualite:details});
  await f.list();const result=await f.details(item.N);assert.equal(result.is,'survey');assert.equal(result.questions.length,2);
  assert.ok(f.calls.every(x=>x.name==='PageActualites'));
});
test('already complete modern information needs no redundant details request',async()=>{
  const f=setup(modern([complete()]));await f.list();const item=await f.details('fixture-news');
  assert.equal(item.content,'Contenu pédagogique fictif');assert.equal(f.calls.length,1);
});

test('modern categories and personal labels coexist without falling into the legacy decoder',async()=>{
  const payload={...modern([metadata()]),listeCategories:{V:[{N:'personal-label',L:'Étiquette personnelle'}]}};
  const f=setup(payload,{genreRequeteActualite:1,detailsActualite:complete()});
  const list=await f.list();assert.equal(list.items[0].detailsRequired,true);
  const detail=await f.details('fixture-news');assert.equal(detail.content,'Contenu pédagogique fictif');
  assert.equal(detail.category.id,category.N);
});

test('published read-only text is readable without optional acknowledgment or recipient metadata',async()=>{
  const detail={...complete()};delete detail.public;delete detail.nature;
  const q={...question()};delete q.reponse;delete q.listeChoix;delete q.listePiecesJointes;detail.listeQuestions={V:[q]};
  const f=setup(modern([metadata()]),{genreRequeteActualite:1,detailsActualite:detail});await f.list();
  const value=await f.details('fixture-news');assert.equal(value.content,'Contenu pédagogique fictif');
  assert.equal(value.acknowledgementAvailable,false);assert.equal(value.needToAcknowledge,false);
  assert.equal(value.acknowledged,undefined);assert.equal(f.calls.length,2);
});

test('acknowledgment requires complete answer state and a usable original public reference',async()=>{
  const valid=()=>({...complete(),public:{V:{N:'fictional-public',G:6}},listeQuestions:{V:[{...question(),reponse:{V:{N:'123',avecReponse:false,estReponseAttendue:true}}}]}});
  const check=async item=>{
    const f=setup(modern([metadata()]),{genreRequeteActualite:1,detailsActualite:item});await f.list();
    const result=await f.details('fixture-news');assert.equal(result.content,'Contenu pédagogique fictif');return result;
  };
  const enabled=await check(valid());assert.equal(enabled.acknowledgementAvailable,true);assert.equal(enabled.needToAcknowledge,true);
  for(const mutate of [
    item=>{item.public={V:null};},item=>{item.public={V:'invalid-reference'};},item=>{item.public={V:{N:'missing-kind'}};},
    item=>{delete item.listeQuestions.V[0].reponse.V.avecReponse;},item=>{delete item.listeQuestions.V[0].reponse.V.estReponseAttendue;},
    item=>{item.listeQuestions.V[0].reponse.V.N='not-a-number';},item=>{item.listeQuestions.V[0].reponse.V.N='9007199254740993';},
    item=>{item.listeQuestions.V[0].genreReponse=2;}
  ]){
    const item=valid();mutate(item);const result=await check(item);
    assert.equal(result.acknowledgementAvailable,false);assert.equal(result.needToAcknowledge,false);
  }
});

test('nullable optional news metadata never blocks a valid published information text',async()=>{
  for(const empty of [null,{V:null}]){
  const item={...metadata(),nature:empty,dateCreation:empty,dateDebut:empty,dateFin:empty};
  const info={...item,public:null,listeQuestions:{V:[{...question(),L:null,titre:null,
    reponse:{V:{N:null,avecReponse:false,estReponseAttendue:true,reponduLe:empty}},
    listePiecesJointes:empty,listeChoix:empty}]}};
  const f=setup({...modern([item]),listeNatures:empty},{genreRequeteActualite:1,detailsActualite:info});
  const list=await f.list();assert.equal(list.items.length,1);assert.equal(list.items[0].creationDate,undefined);
  const result=await f.details(item.N);assert.equal(result.content,'Contenu pédagogique fictif');
  assert.equal(result.needToAcknowledge,false);assert.equal(result.question.answerDate,undefined);
  assert.equal(result.creationDate,undefined);assert.deepEqual(plain(result.attachments),[]);
  assert.equal(result.question.answerID,undefined);
  }
});

test('null category references, answer objects and blank optional attachment rows stay readable',async()=>{
  for(const nature of [null,{V:null},{V:{N:null}}]){
    const info={...complete(),nature,listeQuestions:{V:[{...question(),reponse:{V:null},
      listePiecesJointes:{V:[null]},listeChoix:{V:[null]}}]}};
    const f=setup({...modern([info]),listeNatures:{V:[null,category]}});await f.list();
    const result=await f.details(info.N);assert.equal(result.content,'Contenu pédagogique fictif');
    assert.equal(result.needToAcknowledge,false);assert.deepEqual(plain(result.attachments),[]);
  }
});
test('unknown or malformed news shapes are not silently accepted as empty',async()=>{
  for(const payload of [{listeModesAff:modes([])}, {listeNatures:{V:[]},listeModesAff:[{}]}, {listeNatures:{V:{}},listeModesAff:[]}]){
    await assert.rejects(setup(payload).list(),/UnsupportedNewsFormat/);
  }
});
test('malformed, mismatched or incomplete detail replies raise an explicit format error',async()=>{
  for(const detail of [{}, {genreRequeteActualite:0,detailsActualite:complete()},
    {genreRequeteActualite:1,detailsActualite:{...complete(),N:'another-news'}},
    {genreRequeteActualite:1,detailsActualite:{...complete(),listeQuestions:{V:[{N:'missing-typed-fields'}]}}}]){
    const f=setup(modern([metadata()]),detail);await f.list();await assert.rejects(f.details('fixture-news'),/UnsupportedNewsFormat/);
  }
});
test('network detail failures propagate and cannot turn into a fabricated empty article',async()=>{
  const f=setup(modern([metadata()]),new Error('NetworkUnavailable'));await f.list();
  await assert.rejects(f.details('fixture-news'),/NetworkUnavailable/);assert.equal(f.calls.length,2);
});
test('modern raw references are isolated by session',async()=>{
  const f=setup(modern([metadata()]),{genreRequeteActualite:1,detailsActualite:complete()});await f.list();
  await assert.rejects(f.details('fixture-news',{}),/MissingResource/);assert.equal(f.calls.length,1);
});
test('legacy nonempty news still reaches unchanged information and survey decoders',async()=>{
  const info={...complete(),categorie:{V:{N:category.N}}};const survey={...complete(),N:'survey',estInformation:false,estSondage:true,categorie:info.categorie};
  const f=setup({listeCategories:{V:[category]},listeModesAff:modes([info,survey])});
  const items=(await f.list()).items;assert.equal(items[0].is,'information');assert.equal(items[1].is,'survey');assert.equal(f.calls.length,1);
});

test('both installed SDK entrypoints expose the same detail capability', async () => {
  const require = createRequire(import.meta.url);
  const commonJS = require('@blockshub/pawnote-lts');
  for (const build of [api, commonJS]) {
    assert.equal(typeof build.cadenzaNewsDetail, 'function');
    await assert.rejects(build.cadenzaNewsDetail({}, 'uncached-row'), /MissingResource/);
  }
});
