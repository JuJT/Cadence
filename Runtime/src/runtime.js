import {mapLesson,mapAssignment,mapResource,localDayArgument,profileFor,safeJSON} from './mapping.js';

export function createRuntime(api,native) {
  let session=null,credential=null,challenge=null,authenticated=false,discussionsCache=null;
  const threads=new Map(),newsItems=new Map(),resources=new Map();
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
    const recognized=['SecureStorageUnavailable','InvalidCredential','NotConnected','UnsupportedSection','InvalidPeriod','NetworkUnavailable','MissingDiscussion','MissingResource','ResponseTooLarge'];
    return {name:recognized.includes(e?.message)?e.message:'PronoteError',message:'La requête PRONOTE n’a pas abouti.'};
  }
  function clearData(){threads.clear();newsItems.clear();resources.clear();discussionsCache=null;}
  function requireSession(){if(!authenticated||!session?.userResource)throw Error('NotConnected');}
  function requireCapability(name){if(!profileFor(session).capabilities.includes(name))throw Error('UnsupportedSection');}
  function period(id){const list=session.instance.periods??[];const found=id?list.find(x=>x.id===id):list.find(x=>x.startDate<=new Date()&&x.endDate>=new Date())||list[0];if(!found)throw Error('InvalidPeriod');return found;}
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
      const p=()=>period(args.periodID);
      if(section==='grades')return safeJSON(await api.gradesOverview(session,p()));
      if(section==='evaluations')return safeJSON(await api.evaluations(session,p()));
      if(section==='gradebook')return safeJSON(await api.gradebook(session,p()));
      if(section==='attendance')return safeJSON(await api.notebook(session,p()));
      if(section==='menus')return safeJSON(await api.menus(session,localDayArgument(args.dateDay??args.date??new Date().toISOString())));
      if(section==='account')return safeJSON(await api.account(session));
      if(section==='homepage')return safeJSON(await api.homepage(session));
      if(section==='news') {const value=await api.news(session);for(const item of value.items??[])newsItems.set(item.id,item);return safeJSON(value);}
      if(section==='discussions') return fetchDiscussions();
      if(section==='contents') {const value=await api.resourcesFromIntervals(session,localDayArgument(args.startDay??args.start),localDayArgument(args.endDay??args.end));
        for(const item of value)resources.set(item.id,item);return safeJSON(value);}
      throw Error('UnsupportedSection');
    }
    if(name==='resource') {requireCapability('contents');const r=await api.resource(session,args.id);resources.set(r.id,r);return {resource:safeJSON(r),course_content:mapResource(r)};}
    if(name==='discussion') {
      const item=await findDiscussion(args.id);
      return safeJSON(await api.discussionMessages(session,item,false));
    }
    if(name==='reply') {const item=await findDiscussion(args.id);
      if(session.user.authorizations?.canDiscuss===false||item.closed)throw Error('UnsupportedSection');
      if(!item.messages)await api.discussionMessages(session,item,false);
      if(item.messages?.sendAction==null)throw Error('UnsupportedSection');
      if(!String(args.text??'').trim()||String(args.text).length>20000)throw Error('InvalidCredential');
      const text=String(args.text);const content=session.user.authorizations?.hasAdvancedDiscussionEditor?
        text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\r?\n/g,'<br>'):text;
      await api.discussionSendMessage(session,item,content);return {sent:true};}
    if(name==='acknowledge') {requireCapability('news');const item=newsItems.get(args.id);if(!item)throw Error('MissingResource');
      if(item.is!=='information'||item.needToAcknowledge!==true||item.acknowledged===true)throw Error('UnsupportedSection');
      await api.newsInformationAcknowledge(session,item);return {acknowledged:true};}
    if(name==='recipients'){requireCapability('discussions');if(session.user.authorizations?.canDiscuss===false)throw Error('UnsupportedSection');return safeJSON(await api.newDiscussionRecipients(session,args.kind??3));}
    if(name==='compose') {requireCapability('discussions');if(session.user.authorizations?.canDiscuss===false)throw Error('UnsupportedSection');const recipients=await api.newDiscussionRecipients(session,args.kind??3);
      const selected=recipients.filter(r=>(args.recipientIDs??[]).includes(r.id));
      if(!selected.length||!String(args.subject??'').trim()||!String(args.text??'').trim())throw Error('InvalidCredential');
      await api.newDiscussion(session,args.subject,args.text,selected);return {sent:true};}
    throw Error('UnsupportedSection');
  }
  return {command,replyFetch,classify};
}
