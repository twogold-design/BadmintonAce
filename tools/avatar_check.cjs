const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const {enterAccount,challenge}=require('./account_helpers.cjs');
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime','avatar-check'),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const errors=[];
 try{
  const p=await context.newPage();
  if(process.env.ACE_TEST_URL)await p.addInitScript(url=>Object.defineProperty(window,'ACE_SERVER',{get:()=>url.replace(/^http/,'ws')+'/ws',set:()=>{}}),process.env.ACE_TEST_URL);
  p.on('pageerror',e=>errors.push(e.message));
  p.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await p.goto(pathToFileURL(path.join(root,'index.html')).href);
  await enterAccount(p,'avatar');
  await p.waitForFunction(()=>window.badmintonState?.screen==='menu');
  for(const avatar of ['male','female']){
   await p.mouse.click(515,585);await p.waitForFunction(()=>window.badmintonState.screen==='avatars');
   await p.screenshot({path:path.join(root,'artifacts','avatar-selection.png')});
   await p.mouse.click(avatar==='female'?970:470,450);
   await p.waitForFunction(a=>window.badmintonState.screen==='menu'&&window.badmintonState.selected_avatar===a,avatar);
   await challenge(p,avatar==='female'?4:0);
   await p.waitForFunction(a=>window.badmintonState.screen==='game'&&window.badmintonState.avatars.every(v=>v===a),avatar);
   await p.reload();await enterAccount(p);await p.waitForFunction(()=>window.badmintonState?.screen==='menu');
  }
  await p.reload();await enterAccount(p);await p.waitForFunction(()=>window.badmintonState?.screen==='menu'&&window.badmintonState.selected_avatar==='female');
  await challenge(p,4);await p.waitForFunction(()=>window.badmintonState.screen==='game'&&window.badmintonState.avatars.every(v=>v==='female'));
  await p.waitForTimeout(300);
  await p.keyboard.down('l');await p.waitForTimeout(150);await p.keyboard.up('l');
  await p.waitForFunction(()=>window.badmintonState.hits>=2);
  await p.screenshot({path:path.join(root,'artifacts','female-ai-play.png')});
  assert.equal(errors.length,0,errors.join('\n'));
  fs.writeFileSync(path.join(root,'artifacts','avatar-test.json'),JSON.stringify({ok:true,checks:['both menu selections','front/back preview','same-gender challenge for male and female','female selection persisted after reload','female player serves','AI returns'],errors},null,2));
  console.log('PASS: avatar selection, persistence, preview and AI play');
 }finally{await context.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
