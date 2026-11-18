import test from 'node:test';
import assert from 'node:assert/strict';
import {createRuntime} from '../src/runtime.js';
import {profileFor} from '../src/mapping.js';

function fixture(){
  const calls=[];
  const student={id:'student-fixture',name:'Élève fictif',establishmentName:'Établissement fictif',tabs:new Map([[131,{}]])};
  const session={userResource:student,user:{resources:[student],authorizations:{tabs:[131],canReadDiscussions:true,canDiscuss:true,canDiscussWithTeachers:true,hasAdvancedDiscussionEditor:true}},instance:{periods:[]}};
  const teacher={id:'teacher-fixture',name:'Enseignant fictif',kind:3,isPrincipal:false,subjects:[]};
  const api={createSessionHandle:()=>session,loginCredentials:async()=>({url:'https://school.example/pronote',username:'fixture-user',token:'fixture-token',kind:6}),
    newDiscussionRecipients:async(_s,kind)=>{calls.push(['recipients',kind]);return [teacher];},
    newDiscussion:async(_s,subject,text,recipients)=>{calls.push(['send',subject,text,recipients]);}};
  const runtime=createRuntime(api,{credential:()=>true});
  const login=()=>runtime.command('login',{url:'https://school.example/pronote',username:'fixture-user',password:'fixture-only',deviceUUID:'00000000-0000-4000-8000-000000000001',kind:6});
  return {runtime,api,session,calls,teacher,login};
}
const input={kind:3,subject:'Sujet fictif',text:'Texte fictif',recipientIDs:['teacher-fixture']};

test('compose capability requires both current discussion and teacher permissions',()=>{
  const f=fixture();assert.ok(profileFor(f.session).capabilities.includes('compose'));
  f.session.user.authorizations.canDiscussWithTeachers=false;assert.equal(profileFor(f.session).capabilities.includes('compose'),false);
  f.session.user.authorizations.canDiscussWithTeachers=true;f.session.user.authorizations.canDiscuss=false;
  assert.equal(profileFor(f.session).capabilities.includes('compose'),false);
});
test('recipient lookup only uses permitted teacher kind',async()=>{
  const f=fixture();await f.login();
  assert.equal((await f.runtime.command('recipients',{kind:3})).length,1);
  await assert.rejects(f.runtime.command('recipients',{kind:34}),/UnsupportedSection/);
  f.session.user.authorizations.canDiscussWithTeachers=false;
  await assert.rejects(f.runtime.command('recipients',{kind:3}),/UnsupportedSection/);
  assert.deepEqual(f.calls,[['recipients',3]]);
});
test('a stale recipient choice is rejected without sending to a reduced subset',async()=>{
  const f=fixture();await f.login();
  await assert.rejects(f.runtime.command('compose',{...input,recipientIDs:['teacher-fixture','no-longer-allowed']}),/UnsupportedSection/);
  assert.deepEqual(f.calls,[['recipients',3]]);
});
test('duplicate and oversized composer inputs fail before fetching recipients',async()=>{
  const f=fixture();await f.login();
  for(const args of [{...input,recipientIDs:['teacher-fixture','teacher-fixture']},
    {...input,recipientIDs:Array.from({length:21},(_,i)=>'teacher-'+i)},
    {...input,subject:'😀'.repeat(101)}, {...input,text:'😀'.repeat(10001)}, {...input,text:'   '}]){
    await assert.rejects(f.runtime.command('compose',args),/InvalidCredential/);
  }
  assert.equal(f.calls.length,0);
});
test('confirmed compose revalidates recipients and sends one escaped plain-text message',async()=>{
  const f=fixture();await f.login();
  assert.deepEqual(await f.runtime.command('compose',{...input,subject:'  Test fictif  ',text:'2 < 3\nA & B'}),{sent:true});
  assert.equal(f.calls.length,2);assert.equal(f.calls[0][0],'recipients');
  assert.deepEqual(f.calls[1],['send','Test fictif','2 &lt; 3<br>A &amp; B',[f.teacher]]);
});
test('composer never resends automatically after an ambiguous send failure',async()=>{
  const f=fixture();await f.login();let sends=0;f.api.newDiscussion=async()=>{sends++;throw Error('NetworkUnavailable');};
  await assert.rejects(f.runtime.command('compose',input),/NetworkUnavailable/);
  assert.equal(sends,1);
});
