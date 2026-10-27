const {chromium}=require('playwright');
const path=require('node:path');
const fs=require('node:fs');
const {pathToFileURL}=require('node:url');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
(async()=>{
 const context=await chromium.launchPersistentContext(path.join(root,'.runtime',process.env.ACE_BROWSER?'local-entry-edge':'local-entry-test'),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 const report=[];
 try{
  const entries=process.env.ACE_ENTRY_URL?[['extracted-zip',process.env.ACE_ENTRY_URL]]:[['root-file',pathToFileURL(path.join(root,'index.html')).href],['export-file',pathToFileURL(path.join(root,'build/web/index.html')).href],['http',(process.env.ACE_TEST_URL||'http://127.0.0.1:8765')+'/index.html']];
  for(const [label,url] of entries){
   const page=await context.newPage();const errors=[];const requests=[];
   page.on('console',m=>{if(m.type()==='error'){errors.push(m.text());console.log(label,m.text())}});
   page.on('pageerror',e=>errors.push(e.message));
   page.on('request',r=>requests.push(r.url()));
   await page.goto(url);
   await page.waitForFunction(()=>window.badmintonState?.screen==='menu',null,{timeout:30000});
   await page.mouse.click(200,585);
   await page.waitForTimeout(400);
   await page.keyboard.down('j');await page.waitForTimeout(170);await page.keyboard.up('j');
   await page.waitForFunction(()=>window.badmintonState?.hits>=2,null,{timeout:8000});
   await page.waitForTimeout(500);
   assert.equal(errors.length,0,errors.join('\n'));
   if(label==='http')assert.equal(requests.some(u=>u.endsWith('/local-data.js')),false,'HTTP should not load offline resource duplicate');
   if(label==='root-file')await page.screenshot({path:path.join(root,'artifacts','local-file-play.png')});
   report.push({label,url,menu:true,playerServeAndAiReturn:true,errors});
   console.log('PASS',label);
   await page.close();
  }
  fs.writeFileSync(path.join(root,'artifacts',process.env.ACE_ENTRY_URL?'extracted-entry-test.json':'local-entry-test.json'),JSON.stringify(report,null,2));
 }finally{await context.close()}
})().catch(e=>{console.error(e);process.exit(1)});
