const { chromium }=require('playwright');
const path=require('node:path');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const root=path.resolve(__dirname,'..');
const base=process.env.ACE_TEST_URL||'http://127.0.0.1:8765';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function state(p){return p.evaluate(()=>window.badmintonState)}
async function wait(p,fn,timeout=15000){const end=Date.now()+timeout;while(Date.now()<end){const s=await state(p);if(s&&fn(s))return s;await sleep(100);}throw Error('State timeout: '+JSON.stringify(await state(p)));}
async function tap(p,key,ms=150){await p.keyboard.down(key);await sleep(ms);await p.keyboard.up(key);}
(async()=>{
 const errors=[];
 const contexts=[];
 try{
 for(let i=0;i<2;i++)contexts.push(await chromium.launchPersistentContext(path.join(root,'.runtime','online-'+i),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--no-sandbox','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required','--disable-crash-reporter','--disable-breakpad']}));
 const pages=await Promise.all(contexts.map(c=>c.newPage()));
 for(const [i,p] of pages.entries()){p.on('console',m=>{if(m.type()==='error'){errors.push(i+': '+m.text());console.log('ERROR',i,m.text())}});p.on('pageerror',e=>errors.push(i+': '+e.message));}
 await Promise.all(pages.map(p=>p.goto(base)));
 await Promise.all(pages.map(p=>wait(p,s=>s.screen==='menu',30000)));
 const [a,b]=pages;
 for(const [i,p] of pages.entries()){
  await p.mouse.click(515,585);await wait(p,s=>s.screen==='avatars');
  if(i===0)await p.screenshot({path:path.join(root,'artifacts','avatar-selection.png')});
  await p.mouse.click(i===0?970:470,682);
  await wait(p,s=>s.screen==='menu'&&s.selected_avatar===(i===0?'female':'male'));
 }
 await a.reload();await wait(a,s=>s.screen==='menu'&&s.selected_avatar==='female',30000);
 await a.screenshot({path:path.join(root,'artifacts','menu.png')});
 await Promise.all(pages.map(p=>p.mouse.click(180,660)));
 await Promise.all(pages.map(p=>wait(p,s=>s.screen==='lobby')));
 await a.mouse.click(700,412);
 const host=await wait(a,s=>s.room.length===6);
 console.log('ROOM',host.room);
 await a.screenshot({path:path.join(root,'artifacts','room.png')});
 assert.equal(host.invitation,'','Local service must not advertise an unusable invitation');
 assert.ok(['local','lan'].includes(host.scope));
 // Join through the public idle-room list on the isolated test service.
 await b.mouse.click(700,490);
 await wait(b,s=>s.screen==='rooms');
 await b.mouse.click(430,280);await sleep(200);await b.mouse.click(390,800);
 await Promise.all(pages.map(p=>wait(p,s=>s.screen==='game')));
 console.log('CONNECTED',await state(a),await state(b));
 assert.equal((await state(b)).view_player,1,'Guest owns the near camera');
 await Promise.all(pages.map(p=>wait(p,s=>s.avatars?.[0]==='female'&&s.avatars?.[1]==='male')));
 await a.screenshot({path:path.join(root,'artifacts','female-near-court.png')});
 await tap(a,'j');
 await wait(a,s=>s.phase==='rally');
 await wait(b,s=>s.phase==='rally');
 await b.keyboard.down('d');await sleep(400);await b.keyboard.up('d');
 await sleep(160);
 const sa=await state(a),sb=await state(b);
 assert.ok(sa.players[1][0]<-1.5,'Guest screen-right moves toward negative world X');
 assert.ok(Math.abs(sa.players[1][0]-sb.players[1][0])<0.8,'Remote positions synchronized');
 await a.screenshot({path:path.join(root,'artifacts','game.png')});
 await b.screenshot({path:path.join(root,'artifacts','guest.png')});
 const point=await wait(a,s=>s.score[0]+s.score[1]>0);
 await wait(b,s=>s.score[0]===point.score[0]&&s.score[1]===point.score[1]);
 console.log('SCORE SYNC',point.score);
 await wait(a,s=>s.phase==='serve');
 await sleep(300);
 await tap(a,'j');
 await wait(b,s=>s.phase==='rally');
 await tap(b,'s',330);
 await b.keyboard.down('j');
 await sleep(160);
 await b.screenshot({path:path.join(root,'artifacts','motion-side-prepare.png')});
 await wait(b,s=>s.ball[2]<3.8&&s.ball[1]<-3.8);
 console.log('BEFORE GUEST SHOT',await state(a),await state(b));
 await b.keyboard.up('j');
 await wait(a,s=>s.hits>=3);
 console.log('GUEST RETURN SYNC',await state(a));
 await sleep(160);
 await b.screenshot({path:path.join(root,'artifacts','motion-follow-through.png')});
 await a.keyboard.press('Escape');await wait(b,s=>s.paused);
 await b.keyboard.press('Escape');await wait(a,s=>!s.paused);
 console.log('PAUSE SYNC OK');
 await contexts[1].close();contexts.pop();
 await wait(a,s=>s.screen==='lobby'&&s.status.includes('对手离开'));
 console.log('DISCONNECT OK');
 assert.equal(errors.length,0,errors.join('\n'));
 fs.writeFileSync(path.join(root,'artifacts','online-test.json'),JSON.stringify({ok:true,room:host.room,score:point.score,checks:['male/female menu selection','selection persists after reload','female host / male guest synchronized','create','browse idle rooms and join','nonpublic share blocked','serve','remote movement','guest return','P2 own baseline camera','P2 local-direction movement','buffered ball and velocity rendering','state sync','score sync','pause/resume','disconnect'],errors},null,2));
 console.log('PASS: two real Godot Web clients');
 }finally{await Promise.all(contexts.map(c=>c.close()));}
})().catch(e=>{console.error(e);process.exit(1)});
