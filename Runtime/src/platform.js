// Small host primitives used by Pawnote. All network and entropy come from the
// native bridge; neither arbitrary web pages nor a web view execute this code.
const native=globalThis.__cadenzaNative;
if (native) {
  globalThis.window=globalThis;globalThis.self=globalThis;
  if (!globalThis.crypto) globalThis.crypto={getRandomValues(array){
    if(!ArrayBuffer.isView(array)||array.byteLength>65536)throw Error('Invalid random buffer');
    const data=native.secureRandom(array.byteLength);
    if(!data||data.length!==array.byteLength)throw Error('Secure entropy unavailable');
    new Uint8Array(array.buffer,array.byteOffset,array.byteLength).set(data);return array;
  }};
  let counter=0;const timers=new Map();
  globalThis.setTimeout=(callback,delay=0,...args)=>{const id=String(++counter);timers.set(id,()=>callback(...args));native.setTimer(id,Math.min(60000,Math.max(0,Number(delay)||0)));return id;};
  globalThis.clearTimeout=id=>{timers.delete(String(id));native.clearTimer(String(id));};
  globalThis.__cadenzaTimerFire=id=>{const callback=timers.get(String(id));timers.delete(String(id));if(callback)callback();};
  globalThis.setImmediate=callback=>globalThis.setTimeout(callback,0);
  globalThis.clearImmediate=globalThis.clearTimeout;
  if(!globalThis.URLSearchParams)globalThis.URLSearchParams=class {
    constructor(value=''){this.values=[];if(typeof value==='object'&&!Array.isArray(value))for(const [k,v]of Object.entries(value))this.append(k,v);
      else for(const pair of String(value).replace(/^\?/,'').split('&').filter(Boolean)){const i=pair.indexOf('=');const decode=x=>decodeURIComponent(x.replace(/\+/g,' '));this.values.push([decode(i<0?pair:pair.slice(0,i)),decode(i<0?'':pair.slice(i+1))]);}}
    append(k,v){this.values.push([String(k),String(v)]);}
    set(k,v){this.delete(k);this.append(k,v);}
    get(k){return this.values.find(x=>x[0]===String(k))?.[1]??null;}
    has(k){return this.values.some(x=>x[0]===String(k));}
    delete(k){this.values=this.values.filter(x=>x[0]!==String(k));}
    entries(){return this.values[Symbol.iterator]();}
    [Symbol.iterator](){return this.entries();}
    toString(){const encode=x=>encodeURIComponent(x).replace(/%20/g,'+');return this.values.map(([k,v])=>`${encode(k)}=${encode(v)}`).join('&');}
  };
  if(!globalThis.URL)globalThis.URL=class {
    constructor(value){const m=String(value).match(/^(https?):\/\/([^/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$/i);if(!m)throw TypeError('Absolute HTTPS URL required');
      this.protocol=m[1].toLowerCase()+':';this.host=m[2].toLowerCase();this.hostname=this.host.split(':')[0];this.pathname=m[3]||'/';this.hash=m[5]||'';this.searchParams=new URLSearchParams(m[4]||'');}
    get origin(){return this.protocol+'//'+this.host;}
    get search(){const value=this.searchParams.toString();return value?'?'+value:'';}
    set search(value){this.searchParams=new URLSearchParams(value);}
    get href(){return this.origin+this.pathname+this.search+this.hash;}
    toString(){return this.href;}
    toJSON(){return this.href;}
  };
  globalThis.console??={log(){},warn(){},error(){},debug(){}};
}
