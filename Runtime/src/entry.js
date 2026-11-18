import './platform.js';
import * as pawnote from '@blockshub/pawnote-lts';
import {createRuntime} from './runtime.js';
const native=globalThis.__cadenzaNative;
if(!native)throw Error('Native bridge is required');
const runtime=createRuntime(pawnote,native);
globalThis.__cadenzaFetchReply=runtime.replyFetch;
globalThis.__cadenzaCommand=(id,command,payload)=>{
  Promise.resolve().then(()=>runtime.command(command,JSON.parse(payload))).then(
    value=>native.complete(String(id),JSON.stringify({ok:true,result:value})),
    error=>native.complete(String(id),JSON.stringify({ok:false,error:runtime.classify(error)})));
};
