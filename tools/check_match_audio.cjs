// Verify real scoring and a lost AI match through the exported Web Audio client.
const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--enable-unsafe-swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.addInitScript(()=>{
   window.playedSamples=[];
   const records=new WeakMap();
   const start=AudioBufferSourceNode.prototype.start;
   const stop=AudioBufferSourceNode.prototype.stop;
   AudioBufferSourceNode.prototype.start=function(...args){
    if(this.buffer){
     const samples=this.buffer.getChannelData(0);
     let peak=0;
     for(let i=0;i<samples.length;i+=16)peak=Math.max(peak,Math.abs(samples[i]));
     const record={duration:this.buffer.duration,peak,loop:this.loop,stopped:false};
     records.set(this,record);
     window.playedSamples.push(record);
    }
    return start.apply(this,args);
   };
   AudioBufferSourceNode.prototype.stop=function(...args){
    const record=records.get(this);
    if(record)record.stopped=true;
    return stop.apply(this,args);
   };
  });
  const wait=predicate=>page.waitForFunction(predicate,null,{polling:100,timeout:60000});
  await page.goto(pathToFileURL(path.join(root,'index.html')).href);
  await wait(()=>window.badmintonState?.screen==='login');
  await page.mouse.click(720,629);
  await wait(()=>window.badmintonState?.screen==='menu');
  await page.mouse.click(380,660);
  await wait(()=>window.badmintonState?.screen==='game'&&window.badmintonState.mode==='practice');
  await page.keyboard.press('l');
  await wait(()=>window.playedSamples.some(s=>s.duration>2.5&&s.duration<3.2));
  await page.waitForTimeout(500);
  const cheers=await page.evaluate(()=>window.playedSamples.filter(s=>s.duration>2.5&&s.duration<3.2));
  assert.equal(cheers.length,1,'One point starts exactly one cheer, without restarting it each frame');
  assert.ok(cheers.every(s=>s.peak>0.01&&!s.loop),'Cheer samples contain decoded audio and do not loop');
  assert.deepEqual(errors,[],'Exported game has no script or audio errors');
  console.log('PASS Web match audio: real practice point starts non-silent cheer',JSON.stringify(cheers));
  await page.keyboard.press('Escape');
  await wait(()=>window.badmintonState.paused);
  await page.mouse.click(720,645);
  await wait(()=>window.badmintonState.screen==='menu');
  await page.mouse.click(200,585);
  await wait(()=>window.badmintonState.screen==='challenges');
  await page.mouse.click(230,340);
  await wait(()=>window.badmintonState.screen==='game');
  const deadline=Date.now()+150000;
  // Serve when required, then let the AI score naturally without returning.
  while(Date.now()<deadline){
   const state=await page.evaluate(()=>window.badmintonState);
   if(state.phase==='end')break;
   if(state.phase==='serve'&&state.server===0)await page.keyboard.press('l');
   await page.waitForTimeout(200);
  }
  assert.equal(await page.evaluate(()=>window.badmintonState.phase),'end','AI match reaches its real result');
  assert.equal(await page.evaluate(()=>window.badmintonState.winner),1,'Local player loses this match');
  const losses=()=>page.evaluate(()=>window.playedSamples.filter(s=>s.duration>2.50&&s.duration<2.55));
  let playedLosses=await losses();
  assert.equal(playedLosses.length,1,'Defeat starts the supplied lose sample exactly once');
  assert.ok(playedLosses[0].peak>0.01&&!playedLosses[0].loop&&!playedLosses[0].stopped,'Lose sample is playing decoded audio');
  await page.mouse.click(842,670);
  await wait(()=>window.badmintonState.screen==='menu');
  playedLosses=await losses();
  assert.ok(playedLosses[0].stopped,'Returning home stops the lose sample immediately');
  assert.deepEqual(errors,[],'Result playback has no script or audio errors');
  console.log('PASS Web loss audio: real AI defeat plays once and returning home stops it',JSON.stringify(playedLosses));
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
