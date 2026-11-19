import test from 'node:test';
import assert from 'node:assert/strict';
import {plainSchoolText,resolvePeriod,projectGrades} from '../src/school-data.js';
import {mapAssignment,mapResource,profileFor,safeJSON} from '../src/mapping.js';

const score=points=>({kind:0,points});
const subject={id:'maths',name:'Mathématiques'};
const grade=(value,outOf,coefficient=1,extra={})=>({subject,value:score(value),outOf:score(outOf),coefficient,isOutOf20:true,...extra});
const period=(id,start,end)=>({id,name:id,kind:1,startDate:new Date(start),endDate:new Date(end)});

test('school HTML becomes readable paragraphs without active markup, including escaped markup',()=>{
  assert.equal(plainSchoolText('<div style="font-family: Arial">QCM 10 à 22 page 293<br>Exercices 26, 27 et 30&nbsp;: &#233;tudier</div>'),'QCM 10 à 22 page 293\nExercices 26, 27 et 30 : étudier');
  assert.equal(plainSchoolText('&lt;div&gt;Revoir &amp; apprendre&lt;br&gt;Suite&lt;/div&gt;'),'Revoir & apprendre\nSuite');
  assert.equal(plainSchoolText('<script>alert(1)</script><ul><li>Lire</li><li>Écrire</li></ul>'),'• Lire\n\n• Écrire');
  assert.equal(plainSchoolText('2 < 3 et 4 > 1'),'2 < 3 et 4 > 1');
});

test('homework retains its exact raw source while homework and lessons display plain text',()=>{
  const raw='<div>Parcours dans mon schéma de l’œuvre.&nbsp;</div>';
  const hw=mapAssignment({id:'hw',subject,deadline:new Date(2026,10,24),description:raw});
  assert.equal(hw.description,'Parcours dans mon schéma de l’œuvre.');assert.equal(hw.raw_description,raw);
  assert.equal(mapResource({id:'r',contents:[{id:'c',description:raw}]})[0].description,hw.description);
});

test('current period honors PRONOTE per-tab default even when an annual period overlaps',()=>{
  const annual=period('year','2026-09-01','2027-08-31'),term=period('term1','2026-09-01','2026-12-15');
  const session={instance:{periods:[annual,term]},userResource:{tabs:new Map([[198,{periods:[annual,term],defaultPeriod:term}]])}};
  assert.equal(resolvePeriod(session,'grades',undefined,new Date('2026-11-19')).id,'term1');
  session.userResource.tabs.get(198).defaultPeriod=annual;
  assert.equal(resolvePeriod(session,'grades',undefined,new Date('2026-11-19')).id,'year');
  assert.equal(resolvePeriod(session,'grades','term1').id,'term1');
  assert.throws(()=>resolvePeriod(session,'grades','unknown'),/InvalidPeriod/);
});

test('without a tab default current period uses the shortest active interval and available tab periods only',()=>{
  const annual=period('year','2026-09-01','2027-08-31'),term=period('term1','2026-09-01','2026-12-15'),other=period('not-for-grades','2026-11-01','2026-11-30');
  const session={instance:{periods:[annual,term,other]},userResource:{tabs:new Map([[198,{periods:[annual,term]}]])}};
  assert.equal(resolvePeriod(session,'grades',undefined,new Date('2026-11-19')).id,'term1');
  assert.throws(()=>resolvePeriod(session,'grades',other.id),/InvalidPeriod/);
});

test('profile exposes per-tab defaults and available periods without protocol references',()=>{
  const p=period('term1','2026-09-01','2026-12-15');
  const value=profileFor({instance:{periods:[p]},userResource:{id:'student',tabs:new Map([[198,{defaultPeriod:p,periods:[p]}]])}});
  assert.deepEqual(value.defaultPeriodIDs,{grades:p.id});assert.deepEqual(value.sectionPeriodIDs,{grades:[p.id]});
});

test('published PRONOTE averages always take precedence and are never overwritten',()=>{
  const value={grades:[grade(5,10)],subjectsAverages:[{subject,student:score(16),class_average:score(14)}],overallAverage:score(15),classAverage:score(13)};
  const result=projectGrades(value);
  assert.equal(result.subjectsAverages[0].student.points,16);assert.equal(result.calculatedOverallAverage,undefined);
  assert.equal(result.subjectsAverages[0].calculatedStudent,undefined);assert.equal(result.calculatedClassAverage,undefined);
});

test('missing averages have separately named estimates with coefficients and assessment scale',()=>{
  const result=projectGrades({grades:[grade(5,5,0.07),grade(5.5,6,1)],subjectsAverages:[{subject,student:score(NaN)}]});
  const expected=(20*0.07+(5.5/6*20))/1.07;
  assert.ok(Math.abs(result.subjectsAverages[0].calculatedStudent.points-expected)<1e-10);
  assert.equal(result.calculatedOverallAverage.points,result.subjectsAverages[0].calculatedStudent.points);
  assert.equal(safeJSON(result).subjectsAverages[0].student.points,null);
  assert.match(result.calculationNotice,/Estimation/);
});

test('raw-point weighting, zero marks and teacher-specific optional rules are not conflated',()=>{
  const result=projectGrades({grades:[grade(5,10,1,{isOutOf20:false}),grade(15,20,1,{isOutOf20:false}),
    grade(20,20,100,{isBonus:true}),grade(20,20,100,{isOptional:true}),grade(0,20,0)]});
  assert.ok(Math.abs(result.subjectsAverages[0].calculatedStudent.points-40/3)<1e-10);
  const zero=projectGrades({grades:[grade(NaN,20,1,{value:{kind:6,points:0}})]});
  assert.equal(zero.calculatedOverallAverage.points,0);
  assert.equal(projectGrades({grades:[grade(NaN,20,1,{value:{kind:1,points:NaN}})]}).calculatedOverallAverage,undefined);
});

test('overall estimates normalize official subject scales and do not invent a class average',()=>{
  const result=projectGrades({grades:[],subjectsAverages:[{subject,student:score(8),outOf:score(10)},{subject:{id:'other'},student:score(12),outOf:score(20)}]});
  assert.equal(result.calculatedOverallAverage.points,14);assert.equal(result.calculatedClassAverage,undefined);
});
