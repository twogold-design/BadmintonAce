const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--enable-unsafe-swiftshader']});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[],connections=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('websocket',socket=>connections.push(socket.url()));
  // A saved account must not force a server connection before mode selection.
  await page.addInitScript(()=>{
   const address='ws://127.0.0.1:18779/ws';
   Object.defineProperty(window,'ACE_SERVER',{get:()=>address,set:()=>{}});
   localStorage.setItem('badminton.account.'+address,'offline-test-saved-session');
  });
  const wait=predicate=>page.waitForFunction(predicate,null,{polling:100,timeout:30000});
  const menu=()=>wait(()=>window.badmintonState?.screen==='menu'&&window.badmintonState.offline);
  const home=async()=>{await page.keyboard.press('Escape');await wait(()=>window.badmintonState.paused);await page.mouse.click(720,645);await menu();};
  const loadingStarted=Date.now();
  await page.goto(pathToFileURL(path.join(root,'index.html')).href);
  await wait(()=>window.badmintonState?.screen==='login');
  const loadingMs=Date.now()-loadingStarted;
  await page.screenshot({path:path.join(root,'artifacts/offline-login.png')});
  const entryStarted=Date.now();
  await page.mouse.click(720,629);await menu();
  const entryMs=Date.now()-entryStarted;
  assert.ok(entryMs<2000,`First offline click must not compile the 3D scene (${entryMs} ms)`);
  await page.screenshot({path:path.join(root,'artifacts/offline-home.png')});
  await page.mouse.click(200,585);await wait(()=>window.badmintonState.screen==='challenges');
  await page.screenshot({path:path.join(root,'artifacts/offline-challenges.png')});
  await page.mouse.click(230,575);await wait(()=>window.badmintonState.screen==='game');
  assert.equal(await page.evaluate(()=>window.badmintonState.avatars[1]),'female');
  await page.waitForTimeout(400);await page.keyboard.press('l');await wait(()=>window.badmintonState.hits>=2);
  await home();await page.mouse.click(380,660);await wait(()=>window.badmintonState.screen==='game'&&window.badmintonState.mode==='practice');
  await home();await page.mouse.click(1100,59);await wait(()=>window.badmintonState.screen==='login');
  await page.mouse.click(720,629);await menu();await page.mouse.click(180,660);await wait(()=>window.badmintonState.screen==='login');
  await page.setViewportSize({width:960,height:600});await page.waitForTimeout(350);
  await page.screenshot({path:path.join(root,'artifacts/offline-login-small.png')});
  assert.deepEqual(connections,[],'Offline selection, play and login prompts never open a server connection');
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'artifacts/offline-entry-test.json'),JSON.stringify({ok:true,loading_ms:loadingMs,first_offline_entry_ms:entryMs,server_connections:connections.length,errors},null,2));
  console.log('PASS offline: local file, saved-session choice, AI rally, practice, login gates, zero WebSocket connections, small-window login.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
