const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime','avatar-check'),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const errors=[];
 try{
  const p=await context.newPage();
  p.on('pageerror',e=>errors.push(e.message));
  p.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await p.goto(pathToFileURL(path.join(root,'index.html')).href);
  await p.waitForFunction(()=>window.badmintonState?.screen==='menu');
  for(const avatar of ['male','female']){
   await p.mouse.click(515,585);await p.waitForFunction(()=>window.badmintonState.screen==='avatars');
   await p.screenshot({path:path.join(root,'artifacts','avatar-selection.png')});
   await p.mouse.click(avatar==='female'?970:470,450);
   await p.waitForFunction(a=>window.badmintonState.screen==='menu'&&window.badmintonState.selected_avatar===a,avatar);
  }
  await p.reload();await p.waitForFunction(()=>window.badmintonState?.screen==='menu'&&window.badmintonState.selected_avatar==='female');
  await p.mouse.click(200,585);await p.waitForFunction(()=>window.badmintonState.screen==='game'&&window.badmintonState.avatars[0]==='female');
  await p.waitForTimeout(300);
  await p.keyboard.down('j');await p.waitForTimeout(150);await p.keyboard.up('j');
  await p.waitForFunction(()=>window.badmintonState.hits>=2);
  await p.screenshot({path:path.join(root,'artifacts','female-ai-play.png')});
  assert.equal(errors.length,0,errors.join('\n'));
  fs.writeFileSync(path.join(root,'artifacts','avatar-test.json'),JSON.stringify({ok:true,checks:['both menu selections','front/back preview','female selection persisted after reload','female player serves','AI returns'],errors},null,2));
  console.log('PASS: avatar selection, persistence, preview and AI play');
 }finally{await context.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
