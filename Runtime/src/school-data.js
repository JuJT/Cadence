// Presentation projections only. Raw PRONOTE objects stay in the session for
// later requests; no HTML is executed and no unofficial value replaces a
// published average.
const entities = {nbsp:' ',amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",eacute:'é',egrave:'è',ecirc:'ê',agrave:'à',acirc:'â',ugrave:'ù',ucirc:'û',icirc:'î',ocirc:'ô',ccedil:'ç',Eacute:'É',rsquo:'’',lsquo:'‘',rdquo:'”',ldquo:'“',ndash:'–',mdash:'—',hellip:'…',bull:'•'};
export function plainSchoolText(value) {
  let text=String(value??'');
  // Decode escaped tags before stripping them. Two passes also support the
  // double escaping produced by some school editors without recursive expansion.
  for(let i=0;i<2;i++) text=text.replace(/&(#x[\da-f]+|#\d+|[a-z][a-z\d]+);/gi,(whole,name)=>{
    if(name[0]!=='#')return entities[name]??whole;
    const hex=name[1].toLowerCase()==='x',point=Number.parseInt(name.slice(hex?2:1),hex?16:10);
    return point>0&&point<=0x10ffff&&!(point>=0xd800&&point<=0xdfff)?String.fromCodePoint(point):whole;
  });
  text=text.replace(/<(script|style|iframe|object)\b[^>]*>[\s\S]*?<\/\1\s*>/gi,'')
    .replace(/<!--[^]*?-->/g,'').replace(/<li\b[^>]*>/gi,'\n• ')
    .replace(/<br\b[^>]*>|<\/(?:p|div|li|h[1-6]|tr|ul|ol)\s*>/gi,'\n')
    .replace(/<\/?[a-z][^>]*>/gi,'').replace(/\r\n?/g,'\n')
    .replace(/[\t ]+/g,' ').replace(/ *\n */g,'\n').replace(/\n{3,}/g,'\n\n').replace(/\n{2,}(?=• )/g,'\n');
  return text.trim();
}

const tabIDs={grades:198,evaluations:201,attendance:19,gradebook:13};
export function resolvePeriod(session,section,id,now=new Date()) {
  const tab=session.userResource?.tabs?.get?.(tabIDs[section]);
  const all=session.instance?.periods??[],available=tab?.periods?.length?tab.periods:all;
  if(id){const found=available.find(p=>String(p.id)===String(id));if(!found)throw Error('InvalidPeriod');return found;}
  // PRONOTE's per-tab default is authoritative. It can intentionally point at
  // the last released period rather than the annual overlapping period.
  if(tab?.defaultPeriod){const found=available.find(p=>String(p.id)===String(tab.defaultPeriod.id));if(found)return found;}
  const span=p=>p.endDate-p.startDate;
  const containing=available.filter(p=>p.startDate<=now&&p.endDate>=now).sort((a,b)=>span(a)-span(b));
  const past=available.filter(p=>p.endDate<now).sort((a,b)=>b.endDate-a.endDate||span(a)-span(b));
  const future=available.filter(p=>p.startDate>now).sort((a,b)=>a.startDate-b.startDate||span(a)-span(b));
  const found=containing[0]??past[0]??future[0];if(!found)throw Error('InvalidPeriod');return found;
}

function points(value){return value?.kind===0&&Number.isFinite(value.points)?value.points:null;}
function estimate(grades,field){
  let numerator=0,denominator=0,count=0;
  for(const g of grades){
    // Bonus and optional assessment rules depend on the teacher's formula.
    // Keep them out of this explicitly indicative calculation.
    if(g.isBonus||g.isOptional)continue;
    const n=points(g[field]),d=points(g.outOf),coef=Number(g.coefficient);
    const zeroKind=field==='value'&&[6,7].includes(g.value?.kind);
    if((n===null&&!zeroKind)||!(d>0)||!Number.isFinite(coef)||coef<=0)continue;
    // PRONOTE can combine raw points or reduce each assessment to /20.
    const scale=g.isOutOf20===false?1:20/d;
    numerator+=(zeroKind?0:n)*coef*scale;denominator+=d*coef*scale;count++;
  }
  return denominator?{kind:0,points:20*numerator/denominator,count}:undefined;
}
export function projectGrades(value) {
  const grades=value.grades??[],averages=(value.subjectsAverages??[]).map(a=>({...a}));
  const key=s=>String(s?.id??s?.name??'');
  for(const g of grades)if(!averages.some(a=>key(a.subject)===key(g.subject)))averages.push({subject:g.subject});
  for(const average of averages){
    const own=grades.filter(g=>key(g.subject)===key(average.subject));
    if(points(average.student)===null)average.calculatedStudent=estimate(own,'value');
    if(points(average.class_average)===null)average.calculatedClassAverage=estimate(own,'average');
  }
  const mean=field=>{const values=averages.map(a=>{
    const official=points(a[field]),outOf=points(a.outOf)??20;
    return official!==null&&outOf>0?20*official/outOf:points(a[field==='student'?'calculatedStudent':'calculatedClassAverage']);
  }).filter(v=>v!==null);return values.length?{kind:0,points:values.reduce((a,b)=>a+b,0)/values.length}:undefined;};
  return {...value,subjectsAverages:averages,
    calculatedOverallAverage:points(value.overallAverage)===null?mean('student'):undefined,
    calculatedClassAverage:points(value.classAverage)===null?mean('class_average'):undefined,
    calculationNotice:'Estimation sur les notes disponibles : coefficients des devoirs pris en compte, matières pondérées à égalité. Bonus et notes facultatives exclus. Les règles du professeur peuvent différer.'};
}
