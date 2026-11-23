// Native: no localhost listener and no general-purpose file API. Native bridge
// accepts an unguessable, per-process token only the mapped app receives.
const token=location.hash.slice(1);
const allowedNative=location.origin==='https://inkrail.invalid';
const testing=location.protocol==='http:'&&location.hostname==='127.0.0.1';
const pending=new Map();let seq=0;
export function call(op,args={}){
 const id=++seq,packet={id,token,op,args};
 if(!token||(!allowedNative&&!testing))return Promise.reject(new Error('Open Inkrail.exe, not this HTML file.'));
 if(allowedNative&&window.chrome?.webview){
  return new Promise((resolve,reject)=>{pending.set(id,{resolve,reject});try{window.chrome.webview.postMessage(JSON.stringify(packet));}catch(e){pending.delete(id);reject(e);}});
 }
 if(testing)return fetch('/_test/rpc',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(packet)}).then(async r=>{if(!r.ok)throw Error('Test host refused request: '+r.status);return unpack(await r.json());});
 return Promise.reject(Error('WebView2 bridge unavailable.'));
}
function unpack(r){if(r.error)throw new Error(r.error);return r.value??null;}
Object.defineProperty(window,'__inkrailReply',{value:(r)=>{const h=pending.get(r.id);if(!h)return;pending.delete(r.id);try{h.resolve(unpack(r));}catch(e){h.reject(e);}}});
// Never follow pasted/dropped links or open a second window from the editor.
document.addEventListener('click',e=>{if(e.target.closest?.('a[href]'))e.preventDefault();},true);
window.addEventListener('dragover',e=>e.preventDefault());
window.addEventListener('drop',e=>e.preventDefault());
