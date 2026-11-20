import {mapLesson,mapAssignment,mapResource,localDayArgument,profileFor,safeJSON} from './mapping.js';
import {resolvePeriod,projectGrades} from './school-data.js';

export function createRuntime(api,native) {
  let session=null,credential=null,challenge=null,authenticated=false,discussionsCache=null;
  const threads=new Map(),newsItems=new Map();
  const fetches=new Map();let fetchCounter=0;
  const fetcher=options=>new Promise((resolve,reject)=>{const id=String(++fetchCounter);fetches.set(id,{resolve,reject});native.fetch(id,JSON.stringify(options));});
  const replyFetch=(id,json)=>{const pending=fetches.get(String(id));if(!pending)return;fetches.delete(String(id));
    const value=JSON.parse(json);if(value.error){pending.reject(new Error('NetworkUnavailable'));return;}
    const headers=value.headers??{};pending.resolve({status:value.status,content:value.content??'',headers:{get:key=>headers[String(key).toLowerCase()]??null}});};
  function save(next) {
    if (!next?.token || !next?.url || !next?.username || !credential?.deviceUUID) throw Error('InvalidCredential');
    const value={url:next.url,username:next.username,token:next.token,kind:next.kind??credential.kind??6,
      navigatorIdentifier:next.navigatorIdentifier??credential.navigatorIdentifier??null,deviceUUID:credential.deviceUUID,
      resourceID:session?.userResource?.id||credential.resourceID||null,tokenState:'ready'};
    if (!native.credential(JSON.stringify(value))) throw Error('SecureStorageUnavailable');
    credential=value;
  }
  function challengeSummary(e) {
    const h=e.handle;
    return {message:'PRONOTE demande une vérification de sécurité.',shouldEnterPIN:!!h.shouldEnterPIN,shouldCustomPassword:!!h.shouldCustomPassword,
      shouldCustomDoubleAuth:!!h.shouldCustomDoubleAuth,shouldEnterSource:!!h.shouldEnterSource,availableModes:h.availableSecurityModes??[],
      defaultMode:h.defaultSecurityMode??0,passwordMinLength:h.passwordRules?.minLength??0,passwordMaxLength:h.passwordRules?.maxLength??128};
  }
  function classify(e) {
    if (api.SecurityError && e instanceof api.SecurityError) {challenge=e.handle;return {name:'SecurityChallenge',message:'Vérification PRONOTE nécessaire.',challenge:challengeSummary(e)};}
    for (const name of ['BadCredentialsError','AccountDisabledError','AuthenticateError','AccessDeniedError','SuspendedIPError','SessionExpiredError','RateLimitedError','BusyPageError','PageUnavailableError','UnreachableError']) {
      if(api[name]&&e instanceof api[name])return {name,message:name};
    }
    const recognized=['SecureStorageUnavailable','InvalidCredential','NotConnected','UnsupportedSection','InvalidPeriod','NetworkUnavailable','MissingDiscussion','MissingResource','ResponseTooLarge','UnsupportedNewsFormat'];
    return {name:recognized.includes(e?.message)?e.message:'PronoteError',message:'La requête PRONOTE n’a pas abouti.'};
  }
  function clearData(){threads.clear();newsItems.clear();discussionsCache=null;}
  function requireSession(){if(!authenticated||!session?.userResource)throw Error('NotConnected');}
  function requireCapability(name){if(!profileFor(session).capabilities.includes(name))throw Error('UnsupportedSection');}
  function requireCompose(kind){requireCapability('discussions');requireCapability('compose');if(kind!==3)throw Error('UnsupportedSection');}
  function messageContent(text){return session.user.authorizations?.hasAdvancedDiscussionEditor?
    text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\r?\n/g,'<br>'):text;}
  function weekRange(args){
    const selected=typeof args.periodID==='string'&&args.periodID.startsWith('week:')?args.periodID.slice(5):null;
    const start=localDayArgument(selected??args.dateDay??args.date??new Date().toISOString());
    start.setDate(start.getDate()-((start.getDay()+6)%7));
    const end=new Date(start);end.setDate(end.getDate()+7);
    return {start,end};
  }
  // Pawnote accepts a bounded PRONOTE week domain per request. Splitting the
  // year keeps rich text and attachment metadata below the native response cap.
  async function contentsForSchoolYear(args){
    const today=localDayArgument(args.dateDay??args.date??new Date().toISOString());
    const first=session.instance.firstDate??session.instance.firstMonday;
    if(!(first instanceof Date)||!Number.isFinite(first.getTime()))throw Error('InvalidPeriod');
    const start=new Date(first);start.setHours(0,0,0,0);
    const last=session.instance.lastDate;
    const through=new Date(last instanceof Date&&last<today?last:today);through.setHours(23,59,59,999);
    const lessons=new Map();
    let from=new Date(start);
    while(from<=through){
      const next=new Date(from);next.setDate(next.getDate()+28);
      const end=new Date(Math.min(next.getTime()-1,through.getTime()));
      for(const item of await api.resourcesFromIntervals(session,from,end)){
        if(item.id==null)continue;
        const title=item.contents?.find(content=>content.title)?.title;
        lessons.set(String(item.id),{id:String(item.id),subject:item.subject,teachers:item.teachers,startDate:item.startDate,
          haveAssignment:item.haveAssignment,contents:title?[{title}]:[]});
      }
      from=next;
    }
    return safeJSON({yearStart:start,through,resources:[...lessons.values()]});
  }
  function discussionID(item){const id=item.participantsMessageID??item.id;return id==null?null:String(id);}
  async function fetchDiscussions(){
    requireCapability('discussions');
    if(session.user.authorizations?.canReadDiscussions===false)throw Error('UnsupportedSection');
    discussionsCache??={_:[]};
    const value=await api.discussions(session,discussionsCache);
    threads.clear();
    for(const item of value.items??value.discussions??[]){const id=discussionID(item);if(id)threads.set(id,item);}
    return {...safeJSON(value),items:[...threads].map(([id,item])=>({...safeJSON(item),id,participantsMessageID:id}))};
  }
  async function findDiscussion(id){
    requireCapability('discussions');
    if(session.user.authorizations?.canReadDiscussions===false)throw Error('UnsupportedSection');
    if(!threads.has(String(id)))await fetchDiscussions();
    const item=threads.get(String(id));if(!item)throw Error('MissingDiscussion');return item;
  }
  async function findNews(id){
    requireCapability('news');
    if(!newsItems.has(String(id))){const list=await api.news(session);for(const item of list.items??[])newsItems.set(String(item.id),item);}
    const item=newsItems.get(String(id));if(!item)throw Error('MissingResource');
    if(item.detailsRequired===true){
      if(typeof api.cadenzaNewsDetail!=='function')throw Error('UnsupportedNewsFormat');
      const detailed=await api.cadenzaNewsDetail(session,String(id));newsItems.set(String(id),detailed);return detailed;
    }
    return item;
  }
  async function command(name,args={}) {
    if(name==='discover')return safeJSON(await api.geolocation({latitude:args.latitude,longitude:args.longitude},fetcher));
    if(name==='inspect')return safeJSON(await api.instance(args.url,fetcher));
    if(name==='login'||name==='resume') {
      clearData();challenge=null;authenticated=false;credential={...args};session=api.createSessionHandle(fetcher);
      const params={url:args.url,username:args.username,kind:args.kind??6,deviceUUID:args.deviceUUID,navigatorIdentifier:args.navigatorIdentifier};
      let fresh;
      try {
        fresh=name==='login'?await api.loginCredentials(session,{...params,password:args.password}):
          await api.loginToken(session,{...params,token:args.token},{
            onAuthenticationSent:()=>{const {password,...stored}=credential;if(!native.credential(JSON.stringify({...stored,tokenState:'consuming'})))throw Error('SecureStorageUnavailable');},
            onTokenIssued:save});
      } finally {delete credential.password;}
      save(fresh);
      if(args.resourceID&&session.user.resources.some(r=>r.id===args.resourceID))api.use(session,session.user.resources.find(r=>r.id===args.resourceID));
      save(credential);authenticated=true;
      return profileFor(session);
    }
    if(name==='security') {
      if(!session||!challenge)throw Error('NotConnected');
      const h=challenge;
      if(h.shouldEnterPIN&&(!args.pin||!await api.securityCheckPIN(session,args.pin)))throw new api.BadCredentialsError();
      if(h.shouldCustomPassword&&(!args.password||!await api.securityCheckCustomPassword(session,args.password)))throw new api.BadCredentialsError();
      const options={};
      if(h.shouldEnterPIN&&args.pin)options.pin=args.pin;
      if(h.shouldCustomPassword&&args.password)options.password=args.password;
      if(h.shouldCustomDoubleAuth){if(!h.availableSecurityModes.includes(args.mode))throw new api.BadCredentialsError();options.mode=args.mode;}
      if(h.shouldEnterSource||h.shouldEnterPIN)options.deviceName=String(args.source||'Cadenza iPhone').slice(0,30);
      await api.securitySave(session,h,options);
      const fresh=await api.finishLoginManually(session,h.context.authentication,h.context.identity,h.context.initialUsername);
      save(fresh);challenge=null;authenticated=true;return profileFor(session);
    }
    if(name==='logout'){session=null;credential=null;challenge=null;authenticated=false;clearData();return {};}
    requireSession();
    if(name==='profile')return profileFor(session);
    if(name==='selectResource') {
      const selected=session.user.resources.find(r=>r.id===args.id);if(!selected)throw Error('NotConnected');
      api.use(session,selected);clearData();save(credential);return profileFor(session);
    }
    if(name==='snapshot') {
      const start=localDayArgument(args.startDay??args.start),end=localDayArgument(args.endDay??args.end),caps=profileFor(session).capabilities;
      if(!caps.includes('timetable'))throw Error('UnsupportedSection');
      const timetable=await api.timetableFromIntervals(session,start,end);
      api.parseTimetable(session,timetable,{withSuperposedCanceledClasses:false,withCanceledClasses:true,withPlannedClasses:true});
      const assignments=caps.includes('homework')?await api.assignmentsFromIntervals(session,start,end):[];
      const unique=new Map(timetable.classes.map(c=>{const mapped=mapLesson(c);return[mapped.event_id,mapped];}));
      return {generated_at:new Date().toISOString(),window_start:args.start,window_end:args.end,timetable:[...unique.values()],
        homework:assignments.map(mapAssignment),course_content:[],sync_state:{has_error:false}};
    }
    if(name==='section') {
      const section=args.section;
      requireCapability(section);
      const p=()=>resolvePeriod(session,section,args.periodID);
      if(section==='grades')return safeJSON(projectGrades(await api.gradesOverview(session,p())));
      if(section==='evaluations')return safeJSON(await api.evaluations(session,p()));
      if(section==='gradebook')return safeJSON(await api.gradebook(session,p()));
      if(section==='attendance')return safeJSON(await api.notebook(session,p()));
      if(section==='menus')return safeJSON(await api.menus(session,weekRange(args).start));
      if(section==='account')return safeJSON(await api.account(session));
      if(section==='homepage')return safeJSON(await api.homepage(session));
      if(section==='news') {const value=await api.news(session);for(const item of value.items??[])newsItems.set(String(item.id),item);return safeJSON(value);}
      if(section==='discussions') return fetchDiscussions();
      if(section==='contents')return contentsForSchoolYear(args);
      throw Error('UnsupportedSection');
    }
    if(name==='resource') {requireCapability('contents');const r=await api.resource(session,args.id);return {resource:safeJSON(r),course_content:mapResource(r)};}
    if(name==='newsDetail')return safeJSON({...await findNews(args.id),detailsRequired:false});
    if(name==='discussion') {
      const item=await findDiscussion(args.id);
      return safeJSON(await api.discussionMessages(session,item,false));
    }
    if(name==='reply') {const item=await findDiscussion(args.id);
      if(session.user.authorizations?.canDiscuss===false||item.closed)throw Error('UnsupportedSection');
      if(!item.messages)await api.discussionMessages(session,item,false);
      if(item.messages?.sendAction==null)throw Error('UnsupportedSection');
      if(!String(args.text??'').trim()||String(args.text).length>20000)throw Error('InvalidCredential');
      await api.discussionSendMessage(session,item,messageContent(String(args.text)));return {sent:true};}
    if(name==='acknowledge') {const item=await findNews(args.id);
      if(item.is!=='information')throw Error('UnsupportedSection');
      if(item.acknowledged===true)return {acknowledged:true};
      if(item.needToAcknowledge!==true)throw Error('UnsupportedSection');
      await api.newsInformationAcknowledge(session,item);return {acknowledged:true};}
    if(name==='recipients'){const kind=args.kind??3;requireCompose(kind);return safeJSON(await api.newDiscussionRecipients(session,kind));}
    if(name==='compose') {
      const kind=args.kind??3;requireCompose(kind);
      const ids=args.recipientIDs,subject=typeof args.subject==='string'?args.subject.trim():'',text=typeof args.text==='string'?args.text:'';
      if(!Array.isArray(ids)||!ids.length||ids.length>20||!ids.every(x=>typeof x==='string'&&x.length>0&&x.length<=256)||new Set(ids).size!==ids.length||
        !subject||subject.length>200||!text.trim()||text.length>20000)throw Error('InvalidCredential');
      const recipients=await api.newDiscussionRecipients(session,kind);
      const permitted=new Map(recipients.filter(r=>r.kind===3).map(r=>[String(r.id),r]));
      // Never send a silently reduced recipient list after permission changes.
      if(!ids.every(id=>permitted.has(id)))throw Error('UnsupportedSection');
      const selected=ids.map(id=>permitted.get(id));
      await api.newDiscussion(session,subject,messageContent(text),selected);return {sent:true};}
    throw Error('UnsupportedSection');
  }
  return {command,replyFetch,classify};
}
