import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createRuntime} from '../src/runtime.js';
import {mapLesson,mapAssignment,safeJSON,schoolISO,localDayArgument} from '../src/mapping.js';

const DATE=()=>new Date(2026,10,16,8,10);
const windowArgs={start:'2026-11-15T23:00:00Z',end:'2026-11-18T23:00:00Z',startDay:'2026-11-16',endDay:'2026-11-19'};
const credential={url:'https://school.example/pronote',username:'fixture-user',token:'fixture-token',deviceUUID:'00000000-0000-4000-8000-000000000001',kind:6};
function fixture(tabs=[16,88,131,89,8,198,10]) {
  const trace=[],writes=[];
  const resource={id:'student-fixture',name:'Élève fictif',establishmentName:'Établissement fictif',className:'Classe test',tabs:new Map(tabs.map(x=>[x,{}]))};
  const session={userResource:resource,user:{name:'Élève fictif',resources:[resource],authorizations:{tabs,canReadDiscussions:true,canDiscuss:true}},
    instance:{firstDate:new Date(2026,8,1),lastDate:new Date(2027,6,4),periods:[{id:'p1',name:'Période fictive',kind:1,startDate:new Date(2026,8,1),endDate:new Date(2027,0,1)}]}};
  class SecurityError extends Error {constructor(handle){super('private diagnostic never exposed');this.handle=handle;}}
  class BadCredentialsError extends Error {}
  const api={SecurityError,BadCredentialsError,createSessionHandle:()=>session,
    loginCredentials:async()=>({...credential,token:'new-fixture-token'}),
    loginToken:async(_s,_args,hooks)=>{hooks.onAuthenticationSent();trace.push('authentication');hooks.onTokenIssued({...credential,token:'rotated-fixture-token'});trace.push('parameters');return {...credential,token:'rotated-fixture-token'};},
    use:(_s,r)=>{session.userResource=r;},
    timetableFromIntervals:async(_s,start,end)=>{trace.push(['timetable',start,end]);return {classes:[lesson()]};},
    parseTimetable:(_s,_data,options)=>{trace.push(['parse',options]);},
    assignmentsFromIntervals:async(_s,start,end)=>{trace.push(['homework',start,end]);return [{id:'hw',subject:{name:'Français'},deadline:new Date(2026,10,18),description:'Texte fictif',done:false,attachments:[]}];},
    resourcesFromIntervals:async(_s,start,end)=>{trace.push(['contents',start,end]);return [];},
    menus:async(_s,day)=>{trace.push(['menus',day]);return {days:[]};},
    discussions:async()=>({items:[],folders:[]}),
    discussionMessages:async(_s,item,read)=>{trace.push(['read',item.participantsMessageID,read]);const result={sents:[],sendAction:1};item.messages=result;return result;},
    discussionSendMessage:async(_s,item,text)=>{trace.push(['send',item.participantsMessageID,text]);},
    securityCheckPIN:async()=>true,securityCheckCustomPassword:async()=>true,
    securitySave:async(_s,_h,options)=>trace.push(['securitySave',options]),
    finishLoginManually:async()=>({...credential,token:'security-fixture-token'})};
  const native={fetch(){throw Error('Unexpected real request');},credential(json){const value=JSON.parse(json);writes.push(value);trace.push(['credential',value.tokenState]);return true;}};
  return {runtime:createRuntime(api,native),api,native,session,trace,writes,resource};
}
function lesson(){return {id:'lesson',is:'lesson',subject:{id:'subject',name:'Français'},startDate:DATE(),endDate:new Date(2026,10,16,9,5),teacherNames:[],classrooms:['Salle fictive'],groupNames:[]};}
async function login(f){return f.runtime.command('login',{...credential,password:'fixture-only'});}

test('school clock maps to Paris in winter and summer regardless of phone timezone',()=>{
  const module=new URL('../src/mapping.js',import.meta.url).href;
  for(const TZ of ['UTC','America/New_York','Asia/Tokyo','Europe/Paris']) {
    const script=`import {schoolISO} from ${JSON.stringify(module)};console.log(JSON.stringify([schoolISO(new Date(2026,0,12,8,10)),schoolISO(new Date(2026,5,15,8,10))]));`;
    const result=spawnSync(process.execPath,['--input-type=module','-e',script],{env:{...process.env,TZ},encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    assert.deepEqual(JSON.parse(result.stdout),['2026-01-12T07:10:00.000Z','2026-06-15T06:10:00.000Z']);
  }
});
test('civil-day arguments reject invalid dates',()=>{
  assert.equal(localDayArgument('2026-11-16').getDate(),16);
  assert.throws(()=>localDayArgument('2026-02-30'));
  assert.throws(()=>localDayArgument('invalid'));
});
test('lesson identity survives a changed hour and classroom',()=>{
  const a=lesson(),b={...a,startDate:new Date(2026,10,16,8,15),endDate:new Date(2026,10,16,9,10),classrooms:['Autre salle fictive']};
  assert.equal(mapLesson(a).event_id,mapLesson(b).event_id);
  assert.equal(mapLesson(b).start_local,'2026-11-16T08:15:00');
  assert.deepEqual(mapLesson(b).classrooms,['Autre salle fictive']);
});
test('homework source identity includes deadline and preserves source state',()=>{
  const a=mapAssignment({id:'hw',subject:{name:'Mathématiques'},deadline:new Date(2026,10,18),description:'Exercice fictif',done:true,attachments:[{name:'Fiche',url:'https://example.com/document'}],length:20});
  assert.equal(a.uid,'hw|2026-11-18');assert.equal(a.pronote_id,'hw');assert.equal(a.deadline,'2026-11-18');assert.equal(a.done,true);assert.equal(a.length_minutes,20);assert.equal(a.external_links.length,1);
});
test('snapshot uses explicit Paris days and official PRONOTE timetable filtering',async()=>{
  const f=fixture();await login(f);
  const result=await f.runtime.command('snapshot',windowArgs);
  assert.equal(result.window_start,windowArgs.start);assert.equal(result.window_end,windowArgs.end);
  assert.equal(f.trace.find(x=>Array.isArray(x)&&x[0]==='timetable')[1].getDate(),16);
  assert.equal(f.trace.find(x=>Array.isArray(x)&&x[0]==='homework')[2].getDate(),19);
  assert.deepEqual(f.trace.find(x=>Array.isArray(x)&&x[0]==='parse')[1],{withSuperposedCanceledClasses:false,withCanceledClasses:true,withPlannedClasses:true});
  assert.equal(result.timetable.length,1);assert.equal(result.homework.length,1);
});
test('unsupported homework and section capabilities make no request',async()=>{
  const f=fixture([16]);await login(f);await f.runtime.command('snapshot',windowArgs);
  assert.equal(f.trace.some(x=>Array.isArray(x)&&x[0]==='homework'),false);
  await assert.rejects(f.runtime.command('section',{section:'grades'}),/UnsupportedSection/);
  await assert.rejects(f.runtime.command('resource',{id:'forbidden'}),/UnsupportedSection/);
});
test('the notebook reads contiguous bounded intervals from the provider school year to the chosen civil day',async()=>{
  const f=fixture();await login(f);
  const value=await f.runtime.command('section',{...windowArgs,section:'contents',dateDay:'2026-11-18',periodID:'week:2026-10-26'});
  const calls=f.trace.filter(x=>Array.isArray(x)&&x[0]==='contents');
  assert.equal(calls.length,3);assert.equal(calls[0][1].getTime(),new Date(2026,8,1).getTime());
  for(let i=1;i<calls.length;i++)assert.equal(calls[i][1].getTime(),calls[i-1][2].getTime()+1);
  assert.equal(calls.at(-1)[2].getTime(),new Date(2026,10,18,23,59,59,999).getTime());
  assert.ok(value.yearStart);assert.deepEqual(value.resources,[]);
});
test('annual course index deduplicates lessons, retains titles and stops on the last school day',async()=>{
  const f=fixture();await login(f);
  f.session.instance.firstDate=new Date(2025,8,8);f.session.instance.lastDate=new Date(2026,5,10);
  let end=null;
  f.api.resourcesFromIntervals=async(_s,_from,until)=>{end=until;return [{id:'r1',startDate:new Date(2026,4,11,12),subject:{name:'Mathématiques'},
    teachers:['Professeur fictif'],contents:[{title:'Géométrie',description:'Texte intégral réservé au détail'}]}];};
  const value=await f.runtime.command('section',{section:'contents',dateDay:'2026-07-25'});
  assert.equal(end.getTime(),new Date(2026,5,10,23,59,59,999).getTime());
  assert.equal(value.resources.length,1);assert.deepEqual(value.resources[0].contents,[{title:'Géométrie'}]);
});
test('menus still support the Paris school week and explicit week navigation',async()=>{
  const f=fixture();await login(f);
  await f.runtime.command('section',{section:'menus',dateDay:'2026-11-18'});
  await f.runtime.command('section',{section:'menus',periodID:'week:2026-12-28',dateDay:'2026-11-18'});
  const menus=f.trace.filter(x=>Array.isArray(x)&&x[0]==='menus');
  assert.equal(menus[0][1].getTime(),new Date(2026,10,16).getTime());assert.equal(menus[1][1].getTime(),new Date(2026,11,28).getTime());
});
test('consuming credential is durable before authentication and replacement before parameters',async()=>{
  const f=fixture();await f.runtime.command('resume',credential);
  assert.deepEqual(f.trace.slice(0,4),[['credential','consuming'],'authentication',['credential','ready'],'parameters']);
  assert.equal(f.writes[0].tokenState,'consuming');assert.equal(f.writes.at(-1).tokenState,'ready');
  assert.equal(f.writes.some(x=>'password'in x),false);
});
test('interrupted consuming request never restores the previous ready credential',async()=>{
  const f=fixture();f.api.loginToken=async(_s,_c,h)=>{h.onAuthenticationSent();throw Error('NetworkUnavailable');};
  await assert.rejects(f.runtime.command('resume',credential),/NetworkUnavailable/);
  assert.equal(f.writes.length,1);assert.equal(f.writes[0].tokenState,'consuming');
  await assert.rejects(f.runtime.command('snapshot',windowArgs),/NotConnected/);
});
test('unavailable secure storage prevents consuming authentication',async()=>{
  const f=fixture();let authenticated=false;
  f.native.credential=()=>false;f.api.loginToken=async(_s,_c,h)=>{h.onAuthenticationSent();authenticated=true;};
  await assert.rejects(f.runtime.command('resume',credential),/SecureStorageUnavailable/);assert.equal(authenticated,false);
});
test('security challenge exposes flags but no protocol context',async()=>{
  const f=fixture();const handle={shouldEnterPIN:true,shouldCustomPassword:false,shouldCustomDoubleAuth:false,shouldEnterSource:false,
    availableSecurityModes:[2,3],defaultSecurityMode:3,passwordRules:{minLength:8,maxLength:64},context:{authentication:{token:'private-fixture'},identity:{}}};
  f.api.loginCredentials=async()=>{throw new f.api.SecurityError(handle);};
  let error;try{await login(f);}catch(e){error=e;}
  const value=f.runtime.classify(error);assert.equal(value.name,'SecurityChallenge');assert.equal(value.challenge.shouldEnterPIN,true);
  assert.deepEqual(value.challenge.availableModes,[2,3]);assert.equal('context'in value.challenge,false);
  await f.runtime.command('security',{pin:'0000',source:'Cadenza fictif'});
  assert.deepEqual(f.trace.find(x=>Array.isArray(x)&&x[0]==='securitySave')[1],{pin:'0000',deviceName:'Cadenza fictif'});
});
test('QR pairing calls the pupil login once and stores no pairing material',async()=>{
  const f=fixture();
  const qr={url:'https://school.example/pronote/mobile.eleve.html',jeton:'temporary-pairing-token',login:'encrypted-user'};
  const {url,deviceUUID,kind}=credential;
  let count=0;
  f.api.loginQrCode=async(_session,args)=>{
    count++;
    assert.deepEqual(args,{qr,pin:'0042',deviceUUID});
    return {...credential,token:'new-device-token'};
  };
  await assert.rejects(f.runtime.command('pair',{url,deviceUUID,kind,qr,pin:'0042\n'}),/InvalidPairingCode/);
  assert.equal(count,0);
  const profile=await f.runtime.command('pair',{url,deviceUUID,kind,qr,pin:'0042'});
  assert.equal(count,1);
  assert.equal(profile.displayName,'Élève fictif');
  assert.ok(f.writes.every(write=>write.token==='new-device-token'&& !('qr' in write)&& !('pin' in write)));
});

test('ENT exchanges a transient token for a durable device token without writing the input',async()=>{
  const f=fixture();
  f.api.loginToken=async(_session,args,hooks)=>{
    assert.equal(args.token,'one-time-ent-token');
    assert.equal(args.deviceUUID,credential.deviceUUID);
    assert.equal(hooks.onAuthenticationSent,undefined);
    const rotated={...credential,token:'rotated-device-token'};
    hooks.onTokenIssued(rotated);
    return rotated;
  };
  await assert.rejects(f.runtime.command('loginENT',{...credential,token:''}),/InvalidENTResult/);
  assert.equal(f.writes.length,0);
  await f.runtime.command('loginENT',{...credential,token:'one-time-ent-token'});
  assert.ok(f.writes.every(write=>write.token==='rotated-device-token'&&write.tokenState==='ready'));
});

test('pairing continues through the same PRONOTE challenge without exposing the QR',async()=>{
  const f=fixture();
  f.api.loginQrCode=async()=>{throw new f.api.SecurityError({shouldEnterPIN:true,context:{authentication:{},identity:{}}});};
  const {url,deviceUUID}=credential;
  const qr={url:url+'/mobile.eleve.html',jeton:'pair-token',login:'encrypted-user'};
  let error;
  try{await f.runtime.command('pair',{url,deviceUUID,qr,pin:'1234'});}catch(caught){error=caught;}
  const envelope=f.runtime.classify(error);
  assert.equal(envelope.name,'SecurityChallenge');
  assert.equal(envelope.challenge.shouldEnterPIN,true);
  assert.equal(f.writes.length,0);
  await f.runtime.command('security',{pin:'5678',source:'Cadenza'});
  assert.ok(f.writes.every(write=>write.token==='security-fixture-token'&& !('qr' in write)&& !('pin' in write)));
});
test('security mode must be one offered by the server',async()=>{
  const f=fixture();const handle={shouldCustomDoubleAuth:true,availableSecurityModes:[2,3],context:{authentication:{},identity:{}}};
  f.api.loginCredentials=async()=>{throw new f.api.SecurityError(handle);};
  try{await login(f);}catch(e){f.runtime.classify(e);}
  await assert.rejects(f.runtime.command('security',{mode:0}),f.api.BadCredentialsError);
  assert.equal(f.trace.some(x=>Array.isArray(x)&&x[0]==='securitySave'),false);
});
test('discussions preserve real participant IDs, avoid circular cache and never mark read',async()=>{
  const f=fixture();await login(f);
  const item={participantsMessageID:'real-thread-fixture',subject:'Sujet fictif',date:DATE(),closed:false,possessions:{secret:'protocol-only'}};
  const cache={_:[item]};cache[item.participantsMessageID]=item;item.cache=cache;
  f.api.discussions=async(_s,provided)=>{assert.ok(provided);return {items:[item],folders:[]};};
  const result=await f.runtime.command('section',{section:'discussions'});
  assert.equal(result.items[0].id,'real-thread-fixture');assert.equal(result.items[0].participantsMessageID,'real-thread-fixture');
  assert.equal('cache'in result.items[0],false);assert.equal('possessions'in result.items[0],false);assert.doesNotThrow(()=>JSON.stringify(result));
  await f.runtime.command('discussion',{id:'real-thread-fixture'});
  assert.deepEqual(f.trace.find(x=>Array.isArray(x)&&x[0]==='read'),['read','real-thread-fixture',false]);
});
test('reply re-fetches its reference after a refreshed session and escapes a plain-text editor',async()=>{
  const f=fixture();await login(f);f.session.user.authorizations.hasAdvancedDiscussionEditor=true;
  const item={participantsMessageID:'thread',subject:'Fictif',closed:false};f.api.discussions=async()=>({items:[item],folders:[]});
  await f.runtime.command('reply',{id:'thread',text:'2 < 3\nSuite & fin'});
  assert.deepEqual(f.trace.find(x=>Array.isArray(x)&&x[0]==='send'),['send','thread','2 &lt; 3<br>Suite &amp; fin']);
  assert.equal(f.trace.filter(x=>Array.isArray(x)&&x[0]==='send').length,1);
});
test('closed discussions and forbidden accounts cannot send messages',async()=>{
  const f=fixture();await login(f);const item={participantsMessageID:'thread',closed:true};f.api.discussions=async()=>({items:[item]});
  await assert.rejects(f.runtime.command('reply',{id:'thread',text:'Fictif'}),/UnsupportedSection/);
  assert.equal(f.trace.some(x=>Array.isArray(x)&&x[0]==='send'),false);
});
test('JSON projection drops protocol secrets and cycles but preserves repeated subjects',()=>{
  const subject={id:'maths',name:'Mathématiques'},loop={};loop.self=loop;
  const result=safeJSON({grades:[{subject},{subject}],loop,token:'sensitive-fixture',cache:{},public:{},aesKey:'hidden',value:DATE()});
  assert.equal(result.grades[0].subject.name,'Mathématiques');assert.equal(result.grades[1].subject.name,'Mathématiques');
  assert.equal(result.loop.self,null);assert.equal('token'in result,false);assert.equal('aesKey'in result,false);assert.equal('public'in result,false);
  assert.equal(result.value,schoolISO(DATE()));
});
test('unknown requested period cannot silently return a different period',async()=>{
  const f=fixture();await login(f);let requested=false;f.api.gradesOverview=async()=>{requested=true;return {};};
  await assert.rejects(f.runtime.command('section',{section:'grades',periodID:'missing'}),/InvalidPeriod/);assert.equal(requested,false);
});
test('selected resource survives token rotation',async()=>{
  const f=fixture();const second={...f.resource,id:'second-fixture',name:'Deuxième profil fictif'};f.session.user.resources.push(second);
  await f.runtime.command('resume',{...credential,resourceID:second.id});
  assert.equal(f.session.userResource.id,second.id);assert.equal(f.writes.at(-1).resourceID,second.id);
});

test('news detail lazily restores a refreshed session reference without acknowledging it',async()=>{
  const f=fixture();await login(f);let lists=0,details=0;
  const metadata={id:'news-fixture',title:'Information fictive',is:'information',detailsRequired:true};
  f.api.news=async()=>{lists++;return {categories:[],items:[metadata]};};
  f.api.cadenzaNewsDetail=async(s,id)=>{assert.equal(s,f.session);assert.equal(id,metadata.id);details++;return {...metadata,detailsRequired:false,content:'Texte fictif',cache:{token:'hidden-fixture'}};};
  f.api.newsInformationAcknowledge=async()=>{throw Error('No automatic acknowledgment');};
  const detail=await f.runtime.command('newsDetail',{id:metadata.id});
  assert.equal(detail.detailsRequired,false);assert.equal(detail.content,'Texte fictif');assert.equal('cache'in detail,false);
  await f.runtime.command('newsDetail',{id:metadata.id});
  assert.equal(lists,1);assert.equal(details,1);
});

test('legacy news detail stays available and unknown formats never become a fake empty article',async()=>{
  const f=fixture();await login(f);let details=0;
  const legacy={id:'legacy-fixture',is:'information',content:'Texte fictif existant'};
  const modern={id:'modern-fixture',is:'information',detailsRequired:true};
  f.api.news=async()=>({items:[legacy,modern],categories:[]});
  f.api.cadenzaNewsDetail=async()=>{details++;throw Error('UnsupportedNewsFormat');};
  assert.equal((await f.runtime.command('newsDetail',{id:legacy.id})).content,legacy.content);
  await assert.rejects(f.runtime.command('newsDetail',{id:modern.id}),/UnsupportedNewsFormat/);
  await assert.rejects(f.runtime.command('newsDetail',{id:'missing-fixture'}),/MissingResource/);
  assert.equal(details,1);
});
