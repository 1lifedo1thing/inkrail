import {call} from './bridge.js';
import {mountDesk} from './desk.js';
import {mountEditor} from './editor.js';
import {importMarkdown,exportMarkdown} from './markdown.js';
import {mountPanels,normalizeSettings} from './panels.js';
import {Keys} from './audio.js';

const $=id=>document.getElementById(id);
const buttons={};
const welcomed='A small room for your thoughts.\n\nNo feeds. No noise.\nJust the next sentence.\n\nMake yourself at home.';
const library=new Map(),dirty=new Map(),audio=new Keys(),seg=new Intl.Segmenter();
const state={id:null,settings:normalizeSettings(),focus:false,available:false,path:'',storageMessage:'',trashWarning:'',deleted:[],status:'Opening…',prefRevision:0,savedPrefRevision:0};
let pendingAction=Promise.resolve(),ready=false,closing=false,flushWork=null,timer=0,lastError='',signalDirty=null,formatMask=0;
const page=()=>library.get(state.id);
function createPage(data={}){const now=new Date().toISOString();return {id:crypto.randomUUID().toUpperCase(),createdAt:now,modifiedAt:now,text:'',...data};}
function message(msg){if(!msg)return;const d=$('notice');$('notice-text').textContent=msg;if(!d.open)d.showModal();}
$('notice-ok').onclick=()=>$('notice').close();
$('notice').addEventListener('close',()=>{if(!panel.isOpen())editor.focus()});
const desk=mountDesk($('desk'),{toggleNight:()=>{setPrefs({nightMode:!state.settings.nightMode});editor.focus()}});
const editor=mountEditor(desk.surface,{onChange(p){
 if(!ready||!p?.id||p.id!==state.id)return;
 const previous=page();const next={...previous,text:p.text,formatting:p.formatting??[],modifiedAt:new Date().toISOString()};
 library.set(p.id,next);mark(next);
},onMove:g=>desk.move(g),onSound:k=>{if(k!=='navigation'&&k!=='bell')desk.strike();if(state.settings.soundEnabled)audio.play(k,state.settings)},onFormat:n=>{formatMask=n;formatButtons();}});
const panel=mountPanels($('panels'),{onSettings:setPrefs,onPreviewSound:()=>audio.preview(state.settings),onStopSoundPreview:()=>audio.stopPreview(),onAction:action,onClose:()=>{audio.stopPreview();editor.focus();}});
function noticeError(e){message(e?.message||String(e))}
const icons={
 library:'<path d="M2 8.5 5 3h10l3 5.5V15H2Z"/><path d="M2 9h5l1 2h4l1-2h5"/>',
 new:'<path d="M10 3v14M3 10h14"/>',menu:'<circle cx="4" cy="10" r="1"/><circle cx="10" cy="10" r="1"/><circle cx="16" cy="10" r="1"/>',
 sound:'<path d="M2 8h4l4-4v12l-4-4H2Z"/><path d="M13 6q4 4 0 8"/>',mute:'<path d="M2 8h4l4-4v12l-4-4H2Z"/><path d="m13 8 4 4m0-4-4 4"/>',
 export:'<path d="M6 7H4v10h12V7h-2M10 12V2m-3 3 3-3 3 3"/>',
 focus:'<path d="M3 7V3h4m6 0h4v4m0 6v4h-4m-6 0H3v-4"/>',
 moon:'<path d="M16.5 12.2A7.4 7.4 0 0 1 7.8 3.4a7.1 7.1 0 1 0 8.7 8.8Z"/>',
 sun:'<circle cx="10" cy="10" r="3.5"/><path d="M10 1v2m0 14v2M1 10h2m14 0h2M3.6 3.6l1.6 1.6m9.6 9.6 1.6 1.6M3.6 16.4l1.6-1.6m9.6-9.6 1.6-1.6"/>',
 settings:'<path d="M2 4h16M2 10h16M2 16h16"/><path d="M6 2v4m7 2v4m-5 2v4"/>',
};
const el=(name,cls,text)=>{const o=document.createElement(name);if(cls)o.className=cls;if(text)o.textContent=text;return o};
function setIcon(b,k){b.innerHTML='<svg viewBox="0 0 20 20" aria-hidden="true">'+icons[k]+'</svg>';}
function button(action,label,icon,extra=''){const b=el('button','s-btn '+extra);b.type='button';b.dataset.action=action;b.title=label;b.setAttribute('aria-label',label);if(icon)setIcon(b,icon);b.onclick=e=>{if(action==='menu')showMenu(e.currentTarget);else invoke(action)};if(['bold','italic','underline'].includes(action))b.onpointerdown=e=>e.preventDefault();buttons[action]=b;return b;}
let header=el('div','s-head'),count=el('span','s-count'),dot=el('span','s-dot'),date=el('span','s-date'),tools=el('div','s-tools'),foot=el('div','s-foot'),wc=el('span'),saveState=el('span');
header.append(button('library','Letter box · Ctrl+Shift+O','library'),button('new','New letter · Ctrl+N','new'),button('menu','File and writing menu · Alt+F','menu'),el('span','s-flex'),el('span','s-brand','INKRAIL'),count,dot);
tools.append(date,el('span','s-flex'));
for(const [name,title,k,tag] of [['bold','Bold','B','b'],['italic','Italic','I','i'],['underline','Underline','U','u']]){const b=button(name,title,null,'s-format');b.append(el(tag,'',k));b.title=title+' · Ctrl+'+k;tools.append(b);}
tools.append(el('span','s-divider'),button('sound','Mute sounds · Ctrl+Shift+M','sound'),button('export','Export text · Ctrl+Shift+E','export'),button('focus','Enter Focus Mode · Ctrl+Shift+F','focus'),button('night','Night writing · Ctrl+Alt+L','moon'),button('settings','Make it yours · Ctrl+,','settings'));
foot.append(wc,el('span','','·'),saveState);desk.header.append(header);desk.controls.append(tools);desk.footer.append(foot);
function formatButtons(){for(const [k,b] of [['bold',1],['italic',2],['underline',4]])buttons[k]?.setAttribute('aria-pressed',String(!!(formatMask&b)));}
function dirtySignal(){const next=dirty.size>0;if(signalDirty!==next){signalDirty=next;void call('windowDirty',next).catch(()=>{})}}
function updateLibrary(){panel.setLibrary({pages:[...library.values()],selectedID:state.id,deleted:state.deleted,trashWarning:state.trashWarning});panel.setStorage({path:state.path,available:state.available,message:state.storageMessage});}
function status(){const p=page(),s=p?.text||'';if(status.last!==s){status.last=s;wc.textContent=(s.trim()?s.trim().split(/\s+/u).length:0)+' words';let n=0;if(/^[\x00-\x7f]*$/u.test(s))n=s.length-(s.match(/\r\n/g)||[]).length;else for(const _ of seg.segment(s))n++;count.textContent=n;count.setAttribute('aria-label',n+' characters');}
 dot.classList.toggle('dirty',dirty.size>0);dot.title=state.status;saveState.textContent=state.status.toLowerCase();foot.classList.toggle('error',/failed|unavailable|not saved/i.test(state.status));
 if(p)date.textContent=new Date(p.createdAt).toLocaleDateString(undefined,{day:'numeric',month:'long',year:'numeric'}).toLocaleUpperCase();dirtySignal();}
function applyAppearance(){const s=state.settings;desk.update({...s,focusMode:state.focus});editor.applySettings(s);panel.update(s);tools.classList.toggle('night',s.nightMode);for(const [k,ic,pressed,label] of [['sound',s.soundEnabled?'sound':'mute',s.soundEnabled,s.soundEnabled?'Mute sounds':'Turn sounds on'],['night',s.nightMode?'sun':'moon',s.nightMode,s.nightMode?'Day writing':'Night writing'],['focus','focus',state.focus,state.focus?'Exit Focus Mode':'Enter Focus Mode']]){const b=buttons[k];setIcon(b,ic);b.setAttribute('aria-pressed',String(pressed));b.setAttribute('aria-label',label);b.title=label;}formatButtons();}
function setPrefs(patch){const old=state.settings;state.settings=normalizeSettings({...old,...patch});if(!state.settings.soundEnabled||old.typewriterSound!==state.settings.typewriterSound||!state.settings.soundVolume)audio.stop();state.prefRevision++;applyAppearance();schedule();}
function select(id){const p=library.get(id);if(!p)return false;state.id=id;editor.load(p);state.prefRevision++;status();updateLibrary();schedule();return true;}
function mark(p){dirty.set(p.id,(dirty.get(p.id)||0)+1);state.status=state.available?'Saving…':'Not saved · export your writing';status();schedule();}
function schedule(){clearTimeout(timer);timer=setTimeout(()=>{void flush();},450);}
async function flush(){
 clearTimeout(timer);
 // The writer is shared by autosave, switching, relocation and close. A
 // successful write only clears the exact object that went to disk.
 if(!state.available){
  if(state.savedPrefRevision!==state.prefRevision){const revision=state.prefRevision;state.savedPrefRevision=revision;try{await call('settings',{preferences:state.settings,selectedID:state.id})}catch{state.storageMessage='Library or preferences unavailable. Export any unsaved writing before closing.';updateLibrary()}}
  status();return dirty.size===0;
 }
 while(dirty.size||state.savedPrefRevision!==state.prefRevision||flushWork){
  if(!flushWork){
   const work=(async()=>{
    try{
     for(const id of [...dirty.keys()]){const p=library.get(id);if(!p){dirty.delete(id);continue}
      await call('save',p);if(library.get(id)===p)dirty.delete(id);}
     if(state.prefRevision!==state.savedPrefRevision){const revision=state.prefRevision;await call('settings',{preferences:state.settings,selectedID:state.id});state.savedPrefRevision=revision;}
     state.status=dirty.size?'Saving…':'Saved on this PC';lastError='';return true;
    }catch(e){state.status='Save failed · export your writing';const msg=e.message||String(e);if(lastError!==msg){lastError=msg;message('Inkrail could not save changes. Your writing is still on the desk. Export a copy before closing.\n\n'+msg);}return false;}
   })();
   flushWork=work;work.finally(()=>{if(flushWork===work)flushWork=null;status()});
  }
  if(!await flushWork)return false;
 }
 return true;
}
function newLetter(data={}){const p=createPage(data);library.set(p.id,p);select(p.id);mark(p);return p;}
async function checkTrash(){try{const r=await call('cleanup');state.trashWarning=(r.warnings||[]).join('\n');const gone=new Set(r.removedIDs||[]);if(gone.size)state.deleted=state.deleted.filter(p=>!gone.has(p.id));}catch(e){state.trashWarning=e.message;}updateLibrary();}
async function trashList(){await checkTrash();const r=await call('list',{trash:true});state.deleted=r.pages||[];state.trashWarning=[state.trashWarning,...(r.warnings||[])].filter(Boolean).join('\n');updateLibrary();}
async function action(name,id,value){
 switch(name){
 case 'library':updateLibrary();panel.showLibrary();return true;
 case 'settings':panel.showSettings();return true;
 case 'new':newLetter();await flush();return true;
 case 'select':await flush();return select(id);
 case 'save':return flush();
 case 'import':{const result=await call('import');if(!result)return false;newLetter(result.markdown?importMarkdown(result.text):{text:result.text});await flush();return true;}
 case 'export':case 'exportMarkdown':{const p=page();if(!p)return false;const md=name==='exportMarkdown';return call('export',{text:md?exportMarkdown(p):p.text,body:p.text,markdown:md});}
 case 'rename':{const p=library.get(id);if(!p)throw Error('The letter is no longer in the library.');const next={...p},title=(value||'').split(/[\r\n\u0085\u2028\u2029\v\f]+/u).join(' ').trim();if(title)next.privateTitle=title;else delete next.privateTitle;library.set(id,next);mark(next);if(!await flush())throw Error('The title was not saved.');updateLibrary();return true;}
 case 'trash':{if(!await flush())throw Error('Save the current writing before moving a letter.');await call('trash',{id});library.delete(id);dirty.delete(id);if(id===state.id){if(library.size)select([...library.values()].sort((a,b)=>Date.parse(b.modifiedAt)-Date.parse(a.modifiedAt))[0].id);else newLetter();}await flush();updateLibrary();return true;}
 case 'restore':{await checkTrash();await call('restore',{id});const r=await call('list',{trash:false});for(const p of r.pages||[]){if(!library.has(p.id))library.set(p.id,p);}await trashList();return true;}
 case 'listTrash':await trashList();return true;
 case 'revealStorage':await call('revealStorage');return true;
 case 'changeStorage':{if(!await flush())throw Error('Could not save pending writing. Export a copy before changing folders.');await checkTrash();const path=await call('changeStorage');if(!path)return false;const old=state.path;state.path=path;state.storageMessage='Letters now save here. Your previous copy remains at '+old+'.';updateLibrary();return true;}
 case 'bold':case 'italic':case 'underline':case 'clearFormatting':editor.command(name);return true;
 case 'focus':state.focus=!state.focus;applyAppearance();return true;
 case 'night':setPrefs({nightMode:!state.settings.nightMode});return true;
 case 'sound':setPrefs({soundEnabled:!state.settings.soundEnabled});return true;
 case 'about':message('Inkrail for Windows\nPaper, ink, and a little room to write.\n\nMade with ❤ by Aaryan Verma.\nOpen source · MIT license.');return true;
 }
 return false;
}
function invoke(name){
 if(!ready||closing)return;
 // Saving must not swallow the next writing command or steal a newer caret.
 // Modal file actions are serialized, while editing controls stay responsive.
 if(name==='save'){void flush();return;}
 const run=async()=>{if(closing)return;try{await action(name)}catch(e){noticeError(e)}finally{if(!panel.isOpen()&&!$('notice').open)editor.focus();}};
 if(['bold','italic','underline','clearFormatting','focus','night','sound'].includes(name)){void run();return;}
 pendingAction=pendingAction.then(run,run);
}
const menu=$('commands'),commands=[['new','New letter','Ctrl+N'],['import','Import text or Markdown…','Ctrl+O'],['save','Save now','Ctrl+S'],['export','Export text…','Ctrl+Shift+E'],['exportMarkdown','Export Markdown…',''],null,['library','Letter box','Ctrl+Shift+O'],['settings','Make it yours…','Ctrl+,'],['clearFormatting','Clear inline formatting','Ctrl+\\'],['revealStorage','Show local files',''],null,['about','About Inkrail','']];
for(const entry of commands){if(!entry){menu.append(el('hr'));continue}const [id,label,key]=entry,b=el('button');b.type='button';b.role='menuitem';b.dataset.command=id;b.append(el('span','',label),el('small','',key));b.onclick=()=>{menu.hidden=true;invoke(id)};menu.append(b);}
function showMenu(anchor){if(!menu.hidden){menu.hidden=true;editor.focus();return}const r=anchor.getBoundingClientRect();menu.style.left=Math.max(4,Math.min(innerWidth-235,r.left))+'px';menu.style.top=(r.bottom+2)+'px';menu.hidden=false;menu.querySelector('button').focus();}
window.addEventListener('pointerdown',e=>{if(!menu.hidden&&!menu.contains(e.target)&&!buttons.menu.contains(e.target))menu.hidden=true;});
window.addEventListener('keydown',e=>{if(!ready||e.isComposing||e.key==='Process')return;
 if(e.key==='F5'||e.ctrlKey&&!e.altKey&&['r','p','l'].includes(e.key.toLowerCase())){e.preventDefault();return;}
 if(!menu.hidden){if(e.key==='Escape'){e.preventDefault();menu.hidden=true;buttons.menu.focus()}else if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();const list=[...menu.querySelectorAll('button')];list[(list.indexOf(document.activeElement)+list.length+(e.key==='ArrowDown'?1:-1))%list.length].focus()}return;}
 if(panel.isOpen()||$('notice').open)return;
 const k=e.key.toLowerCase();let cmd;if(e.altKey&&!e.ctrlKey&&k==='f'){e.preventDefault();showMenu(buttons.menu);return}
 if(e.ctrlKey&&!e.metaKey){if(e.altKey){if(k==='l'&&!e.getModifierState('AltGraph'))cmd='night'}else if(e.shiftKey)cmd=({o:'library',e:'export',m:'sound',f:'focus'})[k];else cmd=({o:'import',n:'new',s:'save',',':'settings','\\':'clearFormatting'})[k];}
 if(cmd){e.preventDefault();e.stopPropagation();if(!e.repeat)invoke(cmd)}
},true);
window.addEventListener('blur',()=>{if(ready)void flush();});
window.addEventListener('inkrail-flush',()=>{if(ready)void flush();});
window.addEventListener('inkrail-close-request',async()=>{if(closing)return;closing=true;const ok=await flush();await call(ok?'windowClosed':'windowCloseFailed').catch(()=>{});closing=false;});
async function boot(){const data=await call('boot');state.settings=normalizeSettings(data.settings?.preferences);state.available=data.available;state.path=data.path||'';state.trashWarning=data.trashWarning||'';state.status=data.available?'Saved on this PC':'Storage unavailable · export your writing';
 for(const p of data.pages||[])library.set(p.id,p);ready=true;applyAppearance();
 if(library.size){select(library.has(data.settings?.selectedID)?data.settings.selectedID:library.keys().next().value)}else if(state.available){newLetter({text:welcomed});await flush();}else{const p=createPage();library.set(p.id,p);select(p.id);}
 updateLibrary();$('boot-message').hidden=true;editor.focus();await call('windowReady');document.documentElement.dataset.ready='true';
 if(data.error||data.warnings?.length){state.storageMessage=data.error||'';updateLibrary();message([data.error?'Your library could not be opened. You can still write and export. Reconnect the drive before reopening.\n'+data.error:'',...(data.warnings||[])].filter(Boolean).join('\n\n'));}
 setInterval(()=>{if(dirty.size||state.available&&state.prefRevision!==state.savedPrefRevision)void flush();},2000);
 setInterval(()=>{if(state.available)void checkTrash()},3600000);
}
boot().catch(e=>{ready=false;$('boot-message').textContent='The desk could not open. '+(e.message||e);});
