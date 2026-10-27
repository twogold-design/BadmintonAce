const {chromium}=require('playwright');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const address=process.env.ACE_LAN_ADDRESS;
if(!address)throw Error('Set ACE_LAN_ADDRESS to the real LAN WebSocket address');
async function wait(p,fn){await p.waitForFunction(fn,null,{timeout:20000});}
async function fill(p,x,y,value){await p.mouse.click(x,y);await p.waitForTimeout(150);await p.keyboard.press('Control+A');await p.waitForTimeout(100);await p.keyboard.type(value,{delay:30});await p.waitForTimeout(150);}
(async()=>{
 const contexts=[],errors=[];
 const port=new URL(address).port;
 const service=spawn(path.join(root,'BadmintonAce-Server.exe'),[],{cwd:root,windowsHide:true,env:{...process.env,PORT:port,DATA_DIR:path.join(root,'.runtime','lan-exe-test-data')},stdio:['ignore','pipe','inherit']});
 try{
  await new Promise((resolve,reject)=>{service.once('error',reject);service.once('exit',code=>reject(Error('EXE exited: '+code)));service.stdout.once('data',resolve)});
  for(let i=0;i<2;i++)contexts.push(await chromium.launchPersistentContext(path.join(root,'.runtime','lan-file-'+i),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']}));
  const pages=await Promise.all(contexts.map(c=>c.newPage()));
  for(const p of pages)await p.addInitScript(value=>Object.defineProperty(window,'ACE_SERVER',{get:()=>value,set:()=>{}}),address);
  for(const p of pages){p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(m.type()==='error')errors.push(m.text())});}
  for(const [i,p] of pages.entries()){
   await p.goto(pathToFileURL(path.join(root,'index.html')).href);
   await wait(p,()=>window.badmintonState?.screen==='menu');
   await p.mouse.click(180,660);
   await wait(p,()=>window.badmintonState?.screen==='lobby');
  }
  const [host,guest]=pages;
  for(const [i,p] of pages.entries()){
   await p.mouse.click(700,674);await wait(p,()=>window.badmintonState?.screen==='avatars');
   await p.mouse.click(i===0?470:970,682);
   await wait(p,()=>window.badmintonState?.screen==='lobby');
  }

  await fill(host,850,270,'friend123');await host.mouse.click(700,412);
  await wait(host,()=>window.badmintonState?.room.length===6);
  const code=await host.evaluate(()=>window.badmintonState.room);
  await guest.mouse.click(700,490);await wait(guest,()=>window.badmintonState?.screen==='rooms');
  await guest.screenshot({path:path.join(root,'artifacts','lan-rooms.png')});
  await guest.mouse.click(420,280);await guest.waitForTimeout(150);await guest.mouse.click(390,800);
  await wait(guest,()=>window.badmintonState?.screen==='room_password');
  await fill(guest,700,390,'wrong');await guest.mouse.click(700,475);
  await wait(guest,()=>window.badmintonState?.status.includes('密码不正确'));
  await fill(guest,700,390,'friend123');await guest.mouse.click(700,475);
  await wait(guest,()=>window.badmintonState?.screen==='game');await wait(host,()=>window.badmintonState?.screen==='game');
  for(const p of pages)await wait(p,()=>window.badmintonState?.avatars?.[0]==='male'&&window.badmintonState?.avatars?.[1]==='female');
  await host.screenshot({path:path.join(root,'artifacts','female-far-court.png')});
  await contexts[0].close();contexts.shift();
  await wait(guest,()=>window.badmintonState?.screen==='lobby');
  await guest.mouse.click(530,735);await wait(guest,()=>window.badmintonState?.screen==='ranking');
  await guest.screenshot({path:path.join(root,'artifacts','lan-ranking.png')});
  assert.equal(errors.length,0,errors.join('\n'));
  fs.writeFileSync(path.join(root,'artifacts','lan-test.json'),JSON.stringify({ok:true,address,entry:'local file',server:'standalone EXE',checks:['lobby male/female selection','male host / female guest synchronized','room list','password rejected','password accepted','two clients join','ranking UI'],errors,limitation:'Both browsers are on this host; second physical PC and firewall still require validation.'},null,2));
  console.log('PASS: local file clients -> LAN IP -> standalone EXE, optional-password UI and rankings');
 }catch(e){for(const [i,c] of contexts.entries()){const p=c.pages().at(-1);if(p){console.log('LAN FAIL STATE',await p.evaluate(()=>window.badmintonState));await p.screenshot({path:path.join(root,'artifacts','lan-fail-'+i+'.png')});}}throw e;
 }finally{await Promise.all(contexts.map(c=>c.close()));service.kill();}
})().catch(e=>{console.error(e);process.exitCode=1});
