// Real Godot Web build, browser touch emulation and isolated local server/data.
const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {enterAccount}=require('./account_helpers.cjs');
const root=path.resolve(__dirname,'..'),out=path.join(root,'.runtime/mobile-check');fs.mkdirSync(out,{recursive:true});
const port=18786,base=`http://127.0.0.1:${port}`;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const state=p=>p.evaluate(()=>window.badmintonState);
async function wait(p,predicate,timeout=25000){const end=Date.now()+timeout;while(Date.now()<end){const s=await state(p);if(s&&predicate(s))return s;await delay(100);}throw Error('Timeout '+JSON.stringify(await state(p)));}
async function point(p,x,y){const s=await state(p);const box=await p.locator('canvas').boundingBox();return {x:box.x+(s.ui_offset[0]+x*s.ui_scale[0])*box.width/s.render_size[0],y:box.y+(s.ui_offset[1]+y*s.ui_scale[1])*box.height/s.render_size[1]};}
async function tap(p,x,y){const q=await point(p,x,y);await p.touchscreen.tap(q.x,q.y);}
async function control(p,key){const s=await state(p),box=await p.locator('canvas').boundingBox();const q=key==='stick'?s.touch.stick:s.touch.buttons[key];return {x:box.x+q[0]*box.width/s.render_size[0],y:box.y+q[1]*box.height/s.render_size[1],radius:q[2]*box.width/s.render_size[0]};}
async function multitouch(cdp,type,points){await cdp.send('Input.dispatchTouchEvent',{type,touchPoints:points.map(p=>({id:p.id,x:p.x,y:p.y,radiusX:3,radiusY:3,force:1}))});}
(async()=>{
 const service=spawn(process.execPath,['server/server.js'],{cwd:root,env:{...process.env,PORT:String(port),DATA_DIR:fs.mkdtempSync(path.join(root,'.runtime/mobile-db-')),WEB_ROOT:path.join(root,'build/web'),SERVE_WEB:'1',LAN_ONLY:'1'},stdio:['ignore','pipe','pipe'],windowsHide:true});
 let browser;const errors=[];
 try{
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Startup')),10000);service.stdout.on('data',d=>{if(d.toString().includes(`localhost:${port}`)){clearTimeout(timer);resolve();}});service.once('error',reject);});
  browser=await chromium.launch({executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required']});
  const mobile=await browser.newContext({viewport:{width:844,height:390},deviceScaleFactor:2,isMobile:true,hasTouch:true});
  const desktop=await browser.newContext({viewport:{width:1440,height:900}});
  for(const context of [mobile,desktop])await context.addInitScript(url=>Object.defineProperty(window,'ACE_SERVER',{get:()=>url,set:()=>{}}),base.replace('http','ws')+'/ws');
  const p=await mobile.newPage(),host=await desktop.newPage();
  for(const page of [p,host]){page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});}
  const cdp=await mobile.newCDPSession(p);
  await p.goto(pathToFileURL(path.join(root,'index.html')).href);await wait(p,s=>s.screen==='login',60000);
  assert.equal((await state(p)).touch.enabled,true);
  await tap(p,720,629);await wait(p,s=>s.screen==='menu');
  await tap(p,200,585);await wait(p,s=>s.screen==='challenges');
  await tap(p,230,340);await wait(p,s=>s.screen==='game'&&s.touch.active);
  const clear=await control(p,'clear'),stick=await control(p,'stick');
  assert.ok(clear.radius>=25,'Phone controls have finger-sized targets');
  await delay(350);
  await multitouch(cdp,'touchStart',[{id:1,...clear}]);await wait(p,s=>s.charges[0]===0);
  await multitouch(cdp,'touchEnd',[]);await wait(p,s=>s.phase==='rally');
  const before=await state(p);
  const net=await control(p,'net');
  await multitouch(cdp,'touchStart',[{id:2,x:stick.x+stick.radius*.85,y:stick.y},{id:3,...net}]);
  const held=await wait(p,s=>s.touch.movement[0]>.7&&s.charges[0]===1);
  await wait(p,s=>s.players[0][0]>before.players[0][0]+.1);
  await p.screenshot({path:path.join(out,'mobile-game.png')});
  await multitouch(cdp,'touchCancel',[]);await wait(p,s=>s.touch.movement[0]===0&&s.charges[0]===-1);
  const pause=await control(p,'pause');await p.touchscreen.tap(pause.x,pause.y);await wait(p,s=>s.paused);
  await tap(p,720,380);await wait(p,s=>!s.paused);
  await p.setViewportSize({width:390,height:844});await wait(p,s=>s.touch.portrait&&s.paused);
  assert.equal(await p.locator('#ace-rotate').isVisible(),true);await p.screenshot({path:path.join(out,'mobile-portrait.png')});
  await p.setViewportSize({width:844,height:390});await wait(p,s=>!s.touch.portrait);
  assert.equal(await p.locator('#ace-rotate').isVisible(),false);
  await tap(p,720,645);await wait(p,s=>s.screen==='menu');await tap(p,160,790);await wait(p,s=>s.screen==='login');
  // Exercise the engine's DOM-backed virtual keyboard used by phone browsers.
  await tap(p,700,355);await delay(150);
  const keyboard=await p.evaluate(()=>({tag:document.activeElement?.tagName,type:document.activeElement?.type}));
  assert.ok(['INPUT','TEXTAREA'].includes(keyboard.tag),'Login opens browser virtual-keyboard input');
  await p.keyboard.press('Control+A');await p.keyboard.insertText('手机球友');
  await tap(p,700,455);await p.keyboard.insertText('mobile-test-pass');await tap(p,720,555);await wait(p,s=>s.screen==='menu');
  await host.goto(base);await enterAccount(host);await wait(host,s=>s.screen==='menu');
  await host.mouse.click(180,660);await wait(host,s=>s.screen==='lobby');await host.mouse.click(1125,535);const room=await wait(host,s=>s.room.length===6);
  await tap(p,180,660);await wait(p,s=>s.rooms.some(r=>r.code===room.room));
  await tap(p,430,310);await tap(p,390,700);await wait(p,s=>s.screen==='game');
  await wait(p,s=>!s.preparing&&s.touch.active,20000);await wait(host,s=>!s.preparing);
  assert.equal((await state(p)).view_player,1);
  assert.equal((await state(p)).scoreboard_names[1],'手机球友');
  await host.keyboard.press('l');await wait(p,s=>s.phase==='rally');
  const guestBefore=await state(host),guestStick=await control(p,'stick'),guestNet=await control(p,'net');
  await multitouch(cdp,'touchStart',[{id:5,x:guestStick.x+guestStick.radius*.9,y:guestStick.y},{id:6,...guestNet}]);
  await wait(host,s=>s.players[1][0]<guestBefore.players[1][0]-.1&&s.charges[1]===1);
  await multitouch(cdp,'touchCancel',[]);await wait(host,s=>s.charges[1]===-1);
  await wait(p,s=>s.touch.movement[0]===0);
  await p.screenshot({path:path.join(out,'mobile-p2.png')});
  const small={width:667,height:375};await p.setViewportSize(small);await delay(500);
  const smallState=await state(p),box=await p.locator('canvas').boundingBox();
  for(const b of Object.values(smallState.touch.buttons)){const x=b[0]*box.width/smallState.render_size[0],y=b[1]*box.height/smallState.render_size[1],r=b[2]*box.width/smallState.render_size[0];assert.ok(x-r>=0&&x+r<=small.width&&y-r>=0&&y+r<=small.height);}
  assert.deepEqual(errors,[]);
  const report={ok:true,viewport:[844,390],device_scale:2,offline_file_entry:true,virtual_keyboard:keyboard,checks:['multi-touch move plus charge','release serves','cancel clears without firing','pause/resume','portrait rotation pauses','P2 screen-relative movement','P2 cancellation reaches host','667px layout bounds'],errors};
  fs.writeFileSync(path.join(out,'mobile-test.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
 }finally{await browser?.close();service.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
