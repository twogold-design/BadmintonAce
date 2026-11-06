// Exercise real offline play for multiple rounds; never contact a server.
const {chromium} = require('playwright');
const {pathToFileURL} = require('node:url');
const fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '..');
(async () => {
  const browser = await chromium.launch({executablePath:process.env.ACE_BROWSER || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless:true});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors=[], connections=[];
    page.on('pageerror', e=>errors.push(e.message));
    page.on('websocket', s=>connections.push(s.url()));
    await page.route(/^https?:\/\//, route=>route.abort());
    await page.goto(pathToFileURL(path.resolve(process.env.ACE_PROFILE_ENTRY || path.join(root,'index.html'))).href);
    const wait = f=>page.waitForFunction(f,null,{timeout:60000});
    await wait(()=>window.badmintonState?.screen==='login');
    await page.mouse.click(720,629);
    await wait(()=>window.badmintonState?.screen==='menu');
    await page.mouse.click(200,585);
    await wait(()=>window.badmintonState?.screen==='challenges');
    await page.mouse.click(230,575);
    await wait(()=>window.badmintonState?.screen==='game');
    await page.evaluate(()=>{
      window.rallyProfile=[];window.rallyProfiling=true;
      let previous=performance.now(); const start=previous;
      function frame(now){
        const s=window.badmintonState;
        window.rallyProfile.push({at:now-start,ms:now-previous,hits:s.hits,score:s.score,phase:s.phase});
        previous=now;if(window.rallyProfiling)requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    });
    const held=new Set(), started=Date.now();let matches=0;
    while(Date.now()-started<90000){
      const s=await page.evaluate(()=>window.badmintonState);
      const keys=new Set();
      if(s.phase==='end'){
        for(const key of held)await page.keyboard.up(key);held.clear();
        await page.mouse.click(590,665);matches++;await page.waitForTimeout(300);continue;
      }
      if(s.phase==='rally'&&s.last_hit!==0){
        const t=Math.max(0,(s.velocity[2]+Math.sqrt(Math.max(0,s.velocity[2]**2+21.6*(s.ball[2]-1.6))))/10.8);
        const travel=(1-Math.exp(-.2*t))/.2;
        const target=[Math.max(-2.65,Math.min(2.65,s.ball[0]+s.velocity[0]*travel-.4)),Math.max(.7,Math.min(6.6,s.ball[1]+s.velocity[1]*travel+.35))];
        const [x,y]=s.players[0];
        if(Math.abs(target[0]-x)>.18)keys.add(target[0]>x?'d':'a');
        if(Math.abs(target[1]-y)>.18)keys.add(target[1]>y?'s':'w');
      }
      for(const key of held)if(!keys.has(key))await page.keyboard.up(key);
      for(const key of keys)if(!held.has(key))await page.keyboard.down(key);
      held.clear();for(const key of keys)held.add(key);
      if(s.phase==='serve'&&s.server===0 || s.phase==='rally'&&s.last_hit!==0)await page.keyboard.press('l');
      await page.waitForTimeout(80);
    }
    const result=await page.evaluate(()=>{
      window.rallyProfiling=false;
      const frames=window.rallyProfile.slice(1),batches=[];
      for(let i=0;i<3;i++){
        const part=frames.filter(f=>f.at>=i*30000&&f.at<(i+1)*30000),sorted=part.map(f=>f.ms).sort((a,b)=>a-b);
        batches.push({seconds:(i+1)*30,frames:part.length,mean_ms:sorted.reduce((a,b)=>a+b,0)/sorted.length,p95_ms:sorted[Math.floor(sorted.length*.95)],max_ms:sorted.at(-1),over_50ms:sorted.filter(v=>v>50).length,last:part.at(-1)});
      }
      return {batches,slow:frames.filter(f=>f.ms>50),state:window.badmintonState};
    });
    Object.assign(result,{matches,errors,connections});
    const output=process.env.ACE_PROFILE_REPORT||path.join(root,'.runtime/rallies-web.json');
    fs.writeFileSync(output,JSON.stringify(result,null,2));
    console.log(JSON.stringify({batches:result.batches,matches,errors,connections}));
    if(errors.length||connections.length)throw Error('Offline profile failed');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
