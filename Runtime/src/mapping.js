import {plainSchoolText} from './school-data.js';
const formatter = new Intl.DateTimeFormat('fr-CA', {timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});
const pad = n => String(n).padStart(2,'0');
export function wallText(value) {
  const d=value instanceof Date?value:new Date(value);
  if (!Number.isFinite(d.getTime())) throw Error('Invalid school date');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
export function schoolISO(value) {
  const wall=wallText(value), [y,m,d,h,min,s]=wall.match(/\d+/g).map(Number);
  const nominal=Date.UTC(y,m-1,d,h,min,s);
  const offset=ms=>{const p=Object.fromEntries(formatter.formatToParts(new Date(ms)).filter(x=>x.type!=='literal').map(x=>[x.type,Number(x.value)]));
    return Date.UTC(p.year,p.month-1,p.day,p.hour,p.minute,p.second)-ms;};
  let result=nominal-offset(nominal);result=nominal-offset(result);
  return new Date(result).toISOString();
}
export function localDayArgument(value) {
  const day=String(value).slice(0,10), match=day.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) throw Error('Invalid date interval');
  const date = new Date(Number(match[1]),Number(match[2])-1,Number(match[3]),0,0,0);
  if (date.getFullYear()!==Number(match[1]) || date.getMonth()!==Number(match[2])-1 || date.getDate()!==Number(match[3])) throw Error('Invalid date interval');
  return date;
}
export function mapLesson(c) {
  const title=c.subject?.name || c.title || (c.is==='detention'?'Retenue':'Activité scolaire');
  const local=wallText(c.startDate);
  return {event_id:`${c.id}|${local.slice(0,10)}`,start_at:schoolISO(c.startDate),end_at:schoolISO(c.endDate),
    start_local:local,end_local:wallText(c.endDate),subject_id:c.subject?.id==null?null:String(c.subject.id),subject_name:title,
    teacher_names:c.teacherNames??c.attendants??[],classrooms:c.classrooms??[],group_names:c.groupNames??[],
    personal_names:c.personalNames??[],virtual_classrooms:c.virtualClassrooms??[],background_color:c.backgroundColor??null,
    kind:c.is,canceled:!!c.canceled,exempted:!!c.exempted,is_test:!!c.test,lesson_resource_id:c.lessonResourceID??null};
}
export function mapAssignment(a) {
  const day=wallText(a.deadline).slice(0,10);
  return {uid:`${a.id}|${day}`,pronote_id:String(a.id),subject:a.subject?.name??'Devoir',deadline:day,
    description:plainSchoolText(a.description),raw_description:a.description??'',done:!!a.done,difficulty:a.difficulty??null,
    length_minutes:a.length??null,attachment_names:a.attachments??[],external_links:a.attachments??[]};
}
export function mapResource(r) {
  return (r.contents??[]).map(c=>({resource_id:String(r.id),content_id:String(c.id),title:c.title??r.subject?.name??'Contenu de cours',
    description:plainSchoolText(c.description),category:String(c.category??''),category_text:c.categoryText??null,
    files:c.files??[],themes:c.themes??[],educative_value:c.educativeValue??null,external_links:c.files??[]}));
}
export function safeJSON(value) {
  const hidden = new Set(['cache','possessions','context','authentication','identity','token','password','aeskey','aesiv','navigatoridentifier','public']);
  const ancestors = new WeakSet(); let nodes=0;
  function copy(v,depth=0) {
    if (++nodes>100000 || depth>40) throw Error('ResponseTooLarge');
    if (v==null) return null;
    if (typeof v==='string' || typeof v==='boolean') return v;
    if (typeof v==='number') return Number.isFinite(v)?v:null;
    if (v instanceof Date) return schoolISO(v);
    if (typeof v!=='object') return undefined;
    if (ancestors.has(v)) return null;
    ancestors.add(v);
    try {
      if (Array.isArray(v) || v instanceof Set) return Array.from(v,x=>copy(x,depth+1)??null);
      const result={};
      const entries=v instanceof Map?[...v.entries()]:Object.entries(v);
      for(const [key,item] of entries) {
        if(hidden.has(String(key).toLowerCase()) || ['__proto__','constructor','prototype'].includes(String(key))) continue;
        const next=copy(item,depth+1);if(next!==undefined)result[String(key)]=next;
      }
      return result;
    } finally { ancestors.delete(v); }
  }
  return copy(value);
}
export const tabNames = {198:'grades',89:'contents',88:'homework',16:'timetable',201:'evaluations',49:'account',8:'news',19:'attendance',131:'discussions',13:'gradebook',10:'menus'};
export function profileFor(session) {
  const resource=session.userResource;
  const tabs=new Set([...(session.user?.authorizations?.tabs??[]),...Array.from(resource?.tabs?.keys?.()??[])]);
  const capabilities=[...new Set([...tabs].map(x=>tabNames[x]).filter(Boolean).concat('homepage'))];
  if(capabilities.includes('discussions')&&session.user?.authorizations?.canDiscuss===true&&session.user?.authorizations?.canDiscussWithTeachers===true)capabilities.push('compose');
  return {displayName:resource?.name??session.user?.name??'',establishment:resource?.establishmentName??'',className:resource?.className??null,
    resourceID:String(resource?.id??''),resources:(session.user?.resources??[]).map(r=>({id:String(r.id),name:r.name,className:r.className??null})),
    capabilities,
    defaultPeriodIDs:Object.fromEntries(Array.from(resource?.tabs?.entries?.()??[]).filter(([id,tab])=>tabNames[id]&&tab.defaultPeriod).map(([id,tab])=>[tabNames[id],String(tab.defaultPeriod.id)])),
    sectionPeriodIDs:Object.fromEntries(Array.from(resource?.tabs?.entries?.()??[]).filter(([id,tab])=>tabNames[id]&&tab.periods?.length).map(([id,tab])=>[tabNames[id],tab.periods.map(p=>String(p.id))])),
    periods:(session.instance?.periods??[]).map(p=>({...p,startDate:schoolISO(p.startDate),endDate:schoolISO(p.endDate)}))};
}
