'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { chromium } = require('playwright');
const site = 'https://energygame-minigames-demo.vercel.app';
const directory = 'https://energygame-room-directory.energygame-room-directory.workers.dev';
const roomTitle = 'QA' + crypto.randomBytes(4).toString('hex');
const password = crypto.randomBytes(8).toString('hex');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const points = {name:[997,232],online:[1105,518],title:[1004,267],lock:[1004,393],password:[1004,437],create:[1004,525],join:[745,249],codeField:[470,190],submitCode:[748,190],joinPassword:[618,317],confirm:[685,365],start:[743,617],ready:[640,406],dismissGuide:[188,240],dice:[1108,285]};
let secret, code, pendingCode, stage='baseline', blockedScores=0;
let privateScreens=true;const rows=new Map();const registered = new Map(), gameStarted = new Set(), clients = [], problems = new Set();
const redacted = s => String(s).replaceAll(password,'[redacted]').replaceAll(secret||'__impossible__','[redacted]').replace(/\b\d{6}\b/g,'[room]');
const log = (label, obj={}) => console.log('[QA]',label,JSON.stringify(obj));
const until=async(check,label,timeout=50000)=>{const deadline=Date.now()+timeout;do{if(problems.size)throw new Error([...problems].join('; '));if(await check())return;await delay(350)}while(Date.now()<deadline);throw new Error('Timed out: '+label)};
async function baseline(){
  const endpoints=[['index',site+'/','GET'],['pck',site+'/index.pck','HEAD'],['wasm',site+'/index.wasm','HEAD'],['room directory',directory+'/webrtc/rooms','GET'],['leaderboard',site+'/api/scores/solar_align','GET']];
  const fileLengths={};const declared={};const results=await Promise.all(endpoints.map(async ([label,url,method])=>{
    try {
      const r=await fetch(url,{method,headers:{'Accept-Encoding':'identity'},signal:AbortSignal.timeout(35000)});
      const d={status:r.status,length:r.headers.get('content-length')};
      if(label==='index'){const html=await r.text();for(const [_,ext,bytes] of html.matchAll(/"index\.(pck|wasm)"\s*:\s*(\d+)/g))declared[ext]=Number(bytes);d.declared=declared;d.onlineFrameSupport=html.includes('setEnergyGameOnlineFrames');}
      if((label==='pck'||label==='wasm')&&d.length)fileLengths[label]=Number(d.length);
      if(label==='leaderboard')d.expectedResponse=(await r.json()).game_id==='solar_align';
      if(label==='room directory')d.expectedResponse=Array.isArray((await r.json()).rooms);
      log('public '+label,d);return r.ok && !Object.values(d).includes(false);
    }catch(e){log('public '+label,{error:redacted(e.message)});return false;}
  }));const matched=['pck','wasm'].every(k=>declared[k]>0 && (!fileLengths[k]||declared[k]===fileLengths[k]));log('build size consistency',{match:matched});return matched && results.every(Boolean);
}
async function observeRTC(){
  const base=window.RTCPeerConnection; if(!base)return;
  window.qaTransport={peers:[],dice:[],boards:[]};
  const state=window.qaTransport;const decoder=new TextDecoder('latin1');
  async function inspect(data,direction){
    try{
      const b=data instanceof Blob?new Uint8Array(await data.arrayBuffer()):ArrayBuffer.isView(data)?new Uint8Array(data.buffer,data.byteOffset,data.byteLength):new Uint8Array(data);
      const txt=decoder.decode(b);
      const pos=txt.indexOf('dice_rolled');
      if(pos>=0){const hash=await crypto.subtle.digest('SHA-256',b.slice(pos));state.dice.push({direction,hash:[...new Uint8Array(hash)].map(v=>v.toString(16).padStart(2,'0')).join('')});}
      if(txt.includes('QAP1')&&txt.includes('QAP2')&&txt.includes('QAP3')&&txt.includes('QAP4')&&txt.includes('is_ai')&&txt.length>1500)state.boards.push(direction);
    }catch{}
  }
  const watched=new WeakSet();
  function watch(dc){if(watched.has(dc))return;watched.add(dc);dc.addEventListener('message',ev=>inspect(ev.data,'in'));}
  const orig=RTCDataChannel.prototype.send; RTCDataChannel.prototype.send=function(data){const result=orig.call(this,data);inspect(data,'out');return result;};
  window.RTCPeerConnection=class extends base{
    constructor(...args){super(...args);state.peers.push(this);this.addEventListener('datachannel',e=>watch(e.channel));}
    createDataChannel(...args){const c=super.createDataChannel(...args);watch(c);return c;}
  };
}
function simulateHostBackground(){
  const raf=window.requestAnimationFrame.bind(window),cancel=window.cancelAnimationFrame.bind(window);
  const originalHidden=Object.getOwnPropertyDescriptor(Document.prototype,'hidden').get;
  const originalVisibility=Object.getOwnPropertyDescriptor(Document.prototype,'visibilityState').get;
  const parked=new Map();let active=false,next=1000000000;
  Object.defineProperty(document,'hidden',{configurable:true,get(){return active||originalHidden.call(document);}});
  Object.defineProperty(document,'visibilityState',{configurable:true,get(){return active?'hidden':originalVisibility.call(document);}});
  function dispatch(fn){const id=++next;const native=raf(time=>{if(!parked.has(id))return;if(active){parked.get(id).native=null;return;}parked.delete(id);fn(time);});parked.set(id,{fn,native});return id;}
  window.requestAnimationFrame=fn=>{if(active){const id=++next;parked.set(id,{fn,native:null});return id;}return dispatch(fn);};
  window.cancelAnimationFrame=id=>{const rec=parked.get(id);if(!rec){cancel(id);return;}if(rec.native!==null)cancel(rec.native);parked.delete(id);};
  window.qaSetHostHidden=value=>{active=value;document.dispatchEvent(new Event('visibilitychange'));if(!value){
    for(const [id,rec] of [...parked])if(rec.native===null){parked.delete(id);dispatch(rec.fn);}
  }return {hidden:document.hidden,visibility:document.visibilityState};};
}
async function tap(page,point){await page.mouse.click(...points[point],{delay:160});await delay(350)}
async function fill(page,point,value){await tap(page,point);await page.keyboard.press('ControlOrMeta+a');await page.keyboard.type(value,{delay:55});}
async function submitPassword(page){
  await fill(page,'joinPassword',password);
  const screenshot=await page.screenshot({timeout:18000});
  const cp=require('node:child_process');
  const rows=cp.execFileSync('tesseract',['stdin','stdout','-l','kor+eng','tsv'],{input:screenshot,encoding:'utf8',timeout:14000,stdio:['pipe','pipe','ignore']}).split('\n').map(l=>l.split('\t'));
  const button=rows.find(r=>r.length>=12&&r[11].trim()==='참가'&&Number(r[6])>625&&Number(r[6])<830&&Number(r[7])>=325&&Number(r[7])<475);
  if(!button)throw Error('Password dialog confirm not found in game screenshot');
  const x=Math.round(Number(button[6])+Number(button[8])/2),y=Math.round(Number(button[7])+Number(button[9])/2);
  log('visually located password submit',{x,y});
  await page.mouse.click(x,y,{delay:220});await delay(650);
}
async function run(){
  const baselineOK=await baseline();
  const browser=await chromium.launch({headless:true,args:['--enable-unsafe-swiftshader','--disable-background-timer-throttling','--disable-renderer-backgrounding']});
  try{
    stage='loading four production clients';
    for(let i=0;i<4;i++){
      const ctx=await browser.newContext({viewport:{width:1280,height:720},deviceScaleFactor:1});
      await ctx.addInitScript(observeRTC);if(i===0)await ctx.addInitScript(simulateHostBackground);
      await ctx.route(site+'/api/scores/**',async route=>{if(!['GET','HEAD','OPTIONS'].includes(route.request().method())){blockedScores++;await route.fulfill({status:204,body:''})}else await route.continue()});
      await ctx.route(directory+'/webrtc/rooms',async route=>{
        const req=route.request();
        if(req.method()==='GET')return route.continue();
        if(req.method()==='POST'){
          const body=req.postDataJSON();
          if(i!==0||body.title!==roomTitle||body.password!==password||body.host_name!=='QAP1'){log('private form check',{host:i===0,titleOK:body.title===roomTitle,passwordOK:body.password===password,nameOK:body.host_name==='QAP1'});problems.add('Room form values did not match private test settings');return route.abort();}
          secret=body.host_token; pendingCode=body.code; return route.continue();
        }
        return route.continue();
      });
      await ctx.route(directory+'/webrtc/rooms/*/join',async route=>{
        const req=route.request();if(req.method()!=='POST')return route.continue();
        if(!code||!req.url().endsWith('/'+code+'/join')||req.postDataJSON().password!==password){problems.add('Unexpected join target or password');return route.abort();}
        return route.continue();
      });
      const page=await ctx.newPage();clients.push(page);
      const statuses=new Map();page.on('response',async r=>{
        if(r.request().method()==='GET' && r.url()===directory+'/webrtc/rooms'){try{const out=await r.json();if(out.rooms.some(row=>row.title!==roomTitle))privateScreens=false;const index=out.rooms.findIndex(row=>row.title===roomTitle&&String(row.code)===String(code));const own=out.rooms[index];log('visible private room',{player:i+1,index,locked:own?.password_required,count:own?.player_count,max:own?.max_players});if(index>=0)rows.set(i,index);}catch(e){log('listing parser',{error:redacted(e.message).slice(0,110)});}}
        if(r.request().method()==='POST' && r.url()===directory+'/webrtc/rooms'){
          if(r.status()===201){code=pendingCode;log('private room created',{player:i+1,origin:new URL(page.url()).origin,cors:r.headers()['access-control-allow-origin']});}
          else problems.add('Create room HTTP '+r.status());
        }
        if(r.request().method()==='POST' && code && r.url()===directory+'/webrtc/rooms/'+code+'/join'){
          if(r.ok()){try{const seat=(await r.json()).peer_id;registered.set(i,seat);log('assigned seat',{player:i+1,seat});}catch{problems.add('Guest could not read join response');}}
          else problems.add('Join HTTP '+r.status());
        }if(!r.url().startsWith(directory+'/webrtc/'))return;
        const route=new URL(r.url()).pathname.replace(/\/\d{6}\b/,'/ROOM');const key=r.request().method()+' '+route+' '+r.status();
        if(!statuses.has(key)){statuses.set(key,1);log('signaling response',{player:i+1,method:r.request().method(),path:route,status:r.status()});}});
      page.on('requestfailed',r=>{if(r.url().startsWith(directory+'/webrtc/'))log('signaling transport error',{player:i+1,path:new URL(r.url()).pathname.replace(/\/\d{6}\b/,'/ROOM'),error:r.failure()?.errorText});});
      page.on('console',m=>{const text=m.text();if(text.includes('공통 게임 시작 수신'))gameStarted.add(i);if(text.includes('SCRIPT ERROR')||text.includes('Parse Error'))problems.add('Godot runtime error on player '+(i+1));});
      page.on('pageerror',()=>problems.add('Browser runtime exception on player '+(i+1)));
      await page.goto(site+'/',{waitUntil:'domcontentloaded',timeout:65000});
      await page.waitForFunction(()=>document.querySelector('#canvas')&&!document.querySelector('#loading'),null,{timeout:105000});
      await delay(1100);await fill(page,'name','QAP'+(i+1));
      log('production client ready',{player:i+1});
    }
    const host=clients[0];
    stage='create private room';
    await tap(host,'online');await delay(800);await fill(host,'title',roomTitle);await tap(host,'lock');await fill(host,'password',password);await tap(host,'create');
    await until(()=>!!code,'private room registration');
    stage='join other three browsers';const hidden=await host.evaluate(()=>window.qaSetHostHidden(true));assert.equal(hidden.hidden,true);log('host backgrounded and native frames paused',hidden);
    await Promise.all(clients.slice(1).map(async (p,idx)=>{const listing=p.waitForResponse(r=>r.request().method()==='GET' && r.url()===directory+'/webrtc/rooms',{timeout:30000});await tap(p,'online');await listing;await delay(700);if(idx===2){await fill(p,'codeField',code);await tap(p,'submitCode');await delay(400);log('guest uses direct six-digit code',{player:idx+2});}else{await until(()=>rows.has(idx+1),'own room in guest listing',16000);assert(rows.get(idx+1)<5,'Private room beyond visible rows');await p.mouse.click(745,249+rows.get(idx+1)*68,{delay:180});await delay(550);log('guest uses room list',{player:idx+2});}await submitPassword(p);}));
    await until(()=>registered.size===3,'assign three different seats');
    assert.equal(new Set([1,...registered.values()]).size,4);
    const transports=()=>Promise.all(clients.map(p=>p.evaluate(()=>window.qaTransport?.peers.filter(x=>x.connectionState==='connected'||['connected','completed'].includes(x.iceConnectionState)).length||0)));
    await until(async()=>{const v=await transports();return v[0]>=3 && v.slice(1).every(n=>n>=1)},'all three live WebRTC links',65000);
    log('host admitted three while hidden',{hidden:await host.evaluate(()=>document.hidden)});await host.evaluate(()=>window.qaSetHostHidden(false));log('four connected real clients',{connections:await transports(),seats:[1,...[...registered.values()].sort()]});
    await delay(1200);stage='start synchronized game';await tap(host,'start');
    const read=()=>Promise.all(clients.map(p=>p.evaluate(()=>({boards:window.qaTransport.boards,dice:window.qaTransport.dice}))));
    await until(async()=>{const m=await read();return gameStarted.size===4 || (m[0].boards.includes('out')&&m.slice(1).every(q=>q.boards.includes('in')))},'same four participants receive game start');
    log('four clients receive board start',{engineAcknowledgements:gameStarted.size});await delay(2300);
    stage='ready and roll';await Promise.all(clients.map(p=>tap(p,'ready')));await delay(2000);await Promise.all(clients.map(p=>tap(p,'dismissGuide')));await delay(700);
    // Only the player with turn authority can roll. All other clicks are ignored by the client.
    for(const p of clients){await tap(p,'dice');if((await read())[0].dice.length)break;}
    await until(async()=>{const m=await read();const hashes=m[0].dice.filter(x=>x.direction==='out').map(x=>x.hash);return hashes.some(h=>m.slice(1).every(q=>q.dice.some(x=>x.direction==='in' && x.hash===h)))},'same authoritative dice event at all guests',37000);
    log('four clients agree on first die',{matchedOnAllGuests:true,blockedScorePosts:blockedScores,baselineOK});
    assert(baselineOK,'public endpoint baseline incomplete');
  }catch(e){console.error('[QA] failure at '+stage+': '+redacted(e.message));for(let i=0;i<clients.length;i++){try{if(privateScreens){const fs=require('node:fs');fs.mkdirSync('qa-pictures',{recursive:true});await clients[i].screenshot({path:'qa-pictures/failed-player'+(i+1)+'.png',timeout:8000}).catch(()=>{});}log('browser failure state',{player:i+1,origin:new URL(clients[i].url()).origin,...await clients[i].evaluate(()=>({peers:window.qaTransport?.peers.map(x=>({ice:x.iceConnectionState,connection:x.connectionState,signaling:x.signalingState})),body:document.body.innerText.slice(-140)}))});}catch{}}throw Error('Production smoke stopped at '+stage);}
  finally{
    try{if(secret&&(code||pendingCode)){const r=await fetch(directory+'/webrtc/rooms/'+(code||pendingCode),{method:'DELETE',headers:{Authorization:'Bearer '+secret},signal:AbortSignal.timeout(15000)});log('test room cleanup',{status:r.status});if(!r.ok)process.exitCode=1;}}
    finally{await browser.close();}
  }
}
run().catch(e=>{console.error(e.message);process.exitCode=1;});
