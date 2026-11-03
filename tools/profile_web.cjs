// Offline local-file frame timing; never creates accounts or contacts production.
const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path'),fs=require('node:fs');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--enable-unsafe-swiftshader']});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:900}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>Object.defineProperty(window,'ACE_SERVER',{get:()=> 'ws://127.0.0.1:18779/ws',set:()=>{}}));
  await page.goto(pathToFileURL(path.join(root,'index.html')).href);
  const wait=f=>page.waitForFunction(f,null,{timeout:60000});
  await wait(()=>window.badmintonState?.screen==='login');
  await page.mouse.click(720,629);await wait(()=>window.badmintonState?.screen==='menu');
  await page.mouse.click(200,585);await wait(()=>window.badmintonState?.screen==='challenges');
  await page.mouse.click(230,340);await wait(()=>window.badmintonState?.screen==='game');
  await page.evaluate(()=>{window.profileFrames=[];window.profileActive=true;let last=performance.now();function frame(now){window.profileFrames.push(now-last);last=now;if(window.profileActive)requestAnimationFrame(frame);}requestAnimationFrame(frame);});
  await page.waitForTimeout(500);await page.keyboard.press('l');
  for(const key of ['a','d','w','s']){await page.keyboard.down(key);await page.waitForTimeout(650);await page.keyboard.up(key);await page.keyboard.press('l');}
  await page.waitForTimeout(3000);
  const report=await page.evaluate(()=>{window.profileActive=false;const a=window.profileFrames.slice(1).sort((a,b)=>a-b);const gl=document.querySelector('canvas')?.getContext('webgl2');const ext=gl?.getExtension('WEBGL_debug_renderer_info');return {frames:a.length,mean_ms:a.reduce((s,n)=>s+n,0)/a.length,p95_ms:a[Math.floor(a.length*.95)],max_ms:a.at(-1),over_50ms:a.filter(n=>n>50).length,gpu:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'unknown',state:window.badmintonState};});
  report.errors=errors;
  const output=process.env.ACE_PROFILE_REPORT||path.join(root,'.runtime','web-profile.json');
  fs.writeFileSync(output,JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
  if(errors.length)throw Error(errors.join('\n'));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
