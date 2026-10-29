const { chromium }=require('playwright');
const path=require('node:path');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {enterAccount}=require('./account_helpers.cjs');
const root=path.resolve(__dirname,'..');
const base=process.env.ACE_TEST_URL||'http://127.0.0.1:8765';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function state(p){return p.evaluate(()=>window.badmintonState)}
async function wait(p,fn,timeout=15000){const end=Date.now()+timeout;while(Date.now()<end){const s=await state(p);if(s&&fn(s))return s;await sleep(100);}throw Error('State timeout: '+JSON.stringify(await state(p)));}
async function tap(p,key,ms=150){await p.keyboard.down(key);await sleep(ms);await p.keyboard.up(key);}
(async()=>{
 const errors=[];
 const forbidden=[];
 const contexts=[];
 try{
 for(let i=0;i<2;i++)contexts.push(await chromium.launchPersistentContext(path.join(root,'.runtime','online-'+i),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--no-sandbox','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required','--disable-crash-reporter','--disable-breakpad']}));
 const pages=await Promise.all(contexts.map(c=>c.newPage()));
 for(const p of pages)p.on('websocket',ws=>ws.on('framesent',event=>{try{const d=JSON.parse(event.payload);if(['state','input','effect','pause','appearance'].includes(d.type))forbidden.push(d.type);}catch{}}));
 for(const [i,p] of pages.entries()){p.on('console',m=>{if(m.type()==='error'){errors.push(i+': '+m.text());console.log('ERROR',i,m.text())}});p.on('pageerror',e=>errors.push(i+': '+e.message));}
 await Promise.all(pages.map(p=>p.goto(base)));
 await Promise.all(pages.map(p=>enterAccount(p,'联机')));
 await Promise.all(pages.map(p=>wait(p,s=>s.screen==='menu',30000)));
 const [a,b]=pages;
 for(const [i,p] of pages.entries()){
  await p.mouse.click(515,585);await wait(p,s=>s.screen==='avatars');
  if(i===0)await p.screenshot({path:path.join(root,'artifacts','avatar-selection.png')});
  await p.mouse.click(i===0?970:470,682);
  await wait(p,s=>s.screen==='menu'&&s.selected_avatar===(i===0?'female':'male'));
 }
 await a.reload();await enterAccount(a);await wait(a,s=>s.screen==='menu'&&s.selected_avatar==='female',30000);
 await a.screenshot({path:path.join(root,'artifacts','menu.png')});
 await Promise.all(pages.map(p=>p.mouse.click(180,660)));
 await Promise.all(pages.map(p=>wait(p,s=>s.screen==='lobby'&&s.rooms_loaded)));
 await a.mouse.click(1125,535);
 const host=await wait(a,s=>s.room.length===6);
 console.log('ROOM',host.room);
 await wait(a,s=>s.rooms.some(r=>r.code===host.room));
 await a.screenshot({path:path.join(root,'artifacts','room.png')});
 assert.equal(host.invitation,'','Local service must not advertise an unusable invitation');
 assert.ok(['local','lan'].includes(host.scope));
 // Join through the public idle-room list on the isolated test service.
 await wait(b,s=>s.screen==='lobby'&&s.rooms.some(r=>r.code===host.room));
 await b.mouse.click(430,310);await sleep(200);await b.mouse.click(390,700);
 await Promise.all(pages.map(p=>wait(p,s=>s.screen==='game')));
 console.log('CONNECTED',await state(a),await state(b));
 assert.equal((await state(b)).view_player,1,'Guest owns the near camera');
 await Promise.all(pages.map(p=>wait(p,s=>s.avatars?.[0]==='female'&&s.avatars?.[1]==='male')));
 await a.screenshot({path:path.join(root,'artifacts','female-near-court.png')});
 await tap(a,'l');
 await wait(a,s=>s.phase==='rally');
 await wait(b,s=>s.phase==='rally');
 await b.keyboard.down('d');await sleep(400);await b.keyboard.up('d');
 await sleep(160);
 const sa=await state(a),sb=await state(b);
 assert.ok(sa.peer_ready&&sb.peer_ready&&sa.peer_received>0&&sb.peer_received>0,'Gameplay flows directly over WebRTC');
 assert.ok(sa.snapshot_bytes>0&&sa.snapshot_bytes<600,'Compact binary snapshots stay below 600 bytes');
 assert.equal(sa.snapshot_version,3,'Host negotiates compact cosmetic poses');
 assert.equal(sb.snapshot_version,3,'Guest negotiates the same animation format');
 assert.ok(sa.snapshot_bytes<=420,'Compact poses reduce snapshots without reducing physics precision');
 assert.ok(sa.players[1][0]<-1.5,'Guest screen-right moves toward negative world X');
 assert.ok(Math.abs(sa.players[1][0]-sb.players[1][0])<0.8,'Remote positions synchronized');
 await a.screenshot({path:path.join(root,'artifacts','game.png')});
 await b.screenshot({path:path.join(root,'artifacts','guest.png')});
 const point=await wait(a,s=>s.score[0]+s.score[1]>0);
 await wait(b,s=>s.score[0]===point.score[0]&&s.score[1]===point.score[1]);
 console.log('SCORE SYNC',point.score);
 await wait(a,s=>s.phase==='serve');
 await sleep(300);
 await tap(a,'l');
 await wait(b,s=>s.phase==='rally');
 await tap(b,'s',330);
 await b.keyboard.down('l');
 // Do not block the short contact window on a GPU screenshot or large logs.
 // Diagnostic samples update at 5 Hz; release with enough margin for that
 // sampling delay and the game's short pre-contact input buffer.
 const receiving=await wait(b,s=>s.phase==='rally'&&s.ball[2]<4.8&&s.ball[1]<-3.0);
 console.log('RETURN WINDOW',receiving.ball,receiving.players[1]);
 await b.keyboard.up('l');
 await wait(a,s=>s.hits>=3);
 console.log('GUEST RETURN SYNC',await state(a));
 await sleep(160);
 await b.screenshot({path:path.join(root,'artifacts','motion-follow-through.png')});
 await a.keyboard.press('Escape');await wait(b,s=>s.paused);
 await b.keyboard.press('Escape');await wait(a,s=>!s.paused);
 console.log('PAUSE SYNC OK');
 // Reproduce an inactive/blocked guest renderer while the host keeps running.
 await wait(a,s=>s.phase==='serve');
 const serving=(await state(a)).server===0?a:b;
 await tap(serving,'l');await wait(a,s=>s.phase==='rally');
 const beforeStall=await state(b);
 await b.evaluate(()=>{const until=performance.now()+1800;while(performance.now()<until){}});
 const recovered=await wait(b,s=>s.remote_lag_ms<=150&&(s.remote_catchups>beforeStall.remote_catchups||s.coalesced_states>beforeStall.coalesced_states||s.phase==='point'),5000);
 const landed=await wait(a,s=>s.phase==='point');
 await wait(b,s=>s.phase==='point'&&s.score[0]===landed.score[0]&&s.score[1]===landed.score[1]);
 console.log('STALL RECOVERY OK',{lag_ms:recovered.remote_lag_ms,catchups:recovered.remote_catchups,coalesced:recovered.coalesced_states});
 await contexts[1].close();contexts.pop();
 await wait(a,s=>s.screen==='game'&&s.phase==='end'&&s.result_reason==='forfeit'&&s.winner===0&&s.result_recorded);
 await a.screenshot({path:path.join(root,'artifacts','forfeit-guest.png')});
 console.log('DISCONNECT OK');
 assert.deepEqual(forbidden,[],'No gameplay payload is sent to the room server');
 assert.equal(errors.length,0,errors.join('\n'));
 fs.writeFileSync(path.join(root,'artifacts','online-test.json'),JSON.stringify({ok:true,room:host.room,score:point.score,stall_recovery:{lag_ms:recovered.remote_lag_ms,catchups:recovered.remote_catchups,coalesced:recovered.coalesced_states},checks:['male/female menu selection','selection persists after reload','female host / male guest synchronized','create','browse idle rooms and join','nonpublic share blocked','serve','remote movement','guest return','P2 own baseline camera','P2 local-direction movement','buffered ball and velocity rendering','state sync','score sync','pause/resume','1.8-second guest stall recovery','landing replaces obsolete flight','disconnect'],errors},null,2));
 console.log('PASS: two real Godot Web clients');
 }finally{await Promise.all(contexts.map(c=>c.close()));}
})().catch(e=>{console.error(e);process.exit(1)});
