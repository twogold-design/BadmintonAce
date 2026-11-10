// Exercise the shipped file: Web client, including actual shader animation.
const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--enable-unsafe-swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const wait=predicate=>page.waitForFunction(predicate,null,{polling:100,timeout:60000});
  await page.goto(pathToFileURL(path.join(root,'index.html')).href);
  await wait(()=>window.badmintonState?.screen==='login');
  await page.mouse.click(720,629);
  await wait(()=>window.badmintonState?.screen==='menu');
  await page.mouse.click(380,660);
  await wait(()=>window.badmintonState?.screen==='game'&&window.badmintonState.mode==='practice');
  await page.waitForTimeout(500);
  // Far-baseline crowd lies above the court and outside the pause overlay.
  const clip={x:420,y:115,width:590,height:125};
  const movingA=await page.screenshot({clip});
  await page.waitForTimeout(450);
  const movingB=await page.screenshot({clip});
  assert.ok(!movingA.equals(movingB),'Spectators must visibly animate during a match');
  await page.screenshot({path:path.join(root,'artifacts/crowd-web-baseline.png')});
  await page.keyboard.press('Escape');
  await wait(()=>window.badmintonState.paused);
  await page.waitForTimeout(200);
  const pausedA=await page.screenshot({clip});
  await page.waitForTimeout(450);
  const pausedB=await page.screenshot({clip});
  assert.ok(pausedA.equals(pausedB),'Spectators must freeze when the match is paused');
  await page.keyboard.press('Escape');
  await wait(()=>!window.badmintonState.paused);
  await page.keyboard.press('c');
  await wait(()=>!window.badmintonState.baseline_camera);
  await page.waitForTimeout(300);
  await page.screenshot({path:path.join(root,'artifacts/crowd-web-overhead.png')});
  await page.keyboard.press('l');
  await wait(()=>window.badmintonState.hits>0);
  assert.deepEqual(errors,[],'Web client should have no script/shader errors');
  fs.writeFileSync(path.join(root,'artifacts/crowd-web-test.json'),JSON.stringify({ok:true,animated:true,pause_freezes:true,practice_serve:true,errors},null,2)+'\n');
  console.log('PASS crowd Web: local entry, visible animation, pause freeze, overhead view, practice serve, no shader errors.');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
