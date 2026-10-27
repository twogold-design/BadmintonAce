const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime','layout-check'),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const errors=[],report=[];
 try{
  const p=await context.newPage();p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await p.goto(pathToFileURL(path.join(root,'index.html')).href);
  await p.waitForFunction(()=>window.badmintonState?.screen==='menu');
  const first=await p.evaluate(()=>window.badmintonState.demo_leg);
  let minHip=99;
  for(let i=0;i<12;i++){
   await p.waitForTimeout(500);
   const s=await p.evaluate(()=>window.badmintonState);
   minHip=Math.min(minHip,...s.pelvis_heights);
   assert.ok(Math.min(...s.pelvis_heights)>.7,'Home athletes must remain standing throughout playback');
   if(i%4===0)await p.screenshot({path:path.join(root,'artifacts',`home-motion-${i/4}.png`)});
  }
  assert.ok((await p.evaluate(()=>window.badmintonState.demo_leg))>=first+3,'Home demo must complete multiple alternating shots');
  await p.screenshot({path:path.join(root,'artifacts','menu.png')});
  await p.mouse.click(200,585);await p.waitForFunction(()=>window.badmintonState.screen==='game');
  if(!(await p.evaluate(()=>window.badmintonState.baseline_camera)))await p.keyboard.press('c');
  for(const [w,h] of [[1440,900],[1280,720],[960,600],[1024,768],[1920,1080]]){
   await p.setViewportSize({width:w,height:h});await p.waitForTimeout(450);
   const canvas=await p.locator('canvas').boundingBox(),s=await p.evaluate(()=>window.badmintonState);
   assert.ok(Math.abs(canvas.width-w)<2&&Math.abs(canvas.height-h)<2,'Canvas must fill the window without letterboxing');
   assert.ok(Math.abs(s.render_size[0]/s.render_size[1]-w/h)<.01,'3D render keeps the actual window aspect');
   for(const [x,y] of s.court_corners)assert.ok(x>0&&x<1440&&y>0&&y<857,'Playable boundary remains visible');
   await p.screenshot({path:path.join(root,'artifacts',`window-${w}x${h}.png`)});
   report.push({width:w,height:h,renderSize:s.render_size,canvas,corners:s.court_corners});
  }
  await p.setViewportSize({width:1440,height:900});await p.waitForTimeout(300);
  await p.keyboard.press('j');await p.waitForFunction(()=>window.badmintonState.hits>=2,null,{timeout:10000});
  assert.equal(errors.length,0,errors.join('\n'));
  fs.writeFileSync(path.join(root,'artifacts','layout-test.json'),JSON.stringify({ok:true,minDemoPelvisHeight:minHip,sizes:report,errors},null,2));
  console.log('PASS: continuous home motion, 5 window sizes, visible court bounds, AI return; minimum pelvis height',minHip);
 }finally{await context.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
