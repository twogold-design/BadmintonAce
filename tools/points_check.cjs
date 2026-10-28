const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
const crypto=require('node:crypto'),path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
const {fill}=require('./account_helpers.cjs');
const root=path.resolve(__dirname,'..');
const name='points'+crypto.randomBytes(5).toString('hex');
(async()=>{
 await new Promise((resolve,reject)=>{
  const child=spawn(process.env.GODOT_BIN||'D:/tools/Godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe',['--headless','--path',root,'--script','tools/test_points.gd'],{cwd:root,env:{...process.env,ACE_POINTS_ACCOUNT:name},stdio:'inherit',windowsHide:true});
  child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(Error('Godot points test: '+code)));
 });
 const browser=await chromium.launch({executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--enable-unsafe-swiftshader']});
 let activePage;
 const errors=[];
 try{
  const page=await browser.newPage({viewport:{width:1440,height:900}});activePage=page;
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.goto(process.env.ACE_TEST_URL||'http://127.0.0.1:18765');
  await page.waitForFunction(()=>window.badmintonState?.screen==='login');
  await page.screenshot({path:path.join(root,'artifacts','account-login.png')});
  await fill(page,700,355,name);await fill(page,700,455,'wrong-password');await page.mouse.click(600,555);
  await page.waitForFunction(()=>window.badmintonState?.status.includes('账号或密码不正确'));
  await fill(page,700,455,'points-ui-pass');await page.mouse.click(600,555);
  await page.waitForFunction(()=>window.badmintonState?.screen==='menu'&&window.badmintonState?.points===10&&window.badmintonState?.leaders_loaded);
  await page.screenshot({path:path.join(root,'artifacts','points-home.png')});
  await page.mouse.click(200,585);await page.waitForFunction(()=>window.badmintonState?.screen==='challenges');
  await page.screenshot({path:path.join(root,'artifacts','challenge-selection.png')});
  await page.mouse.click(230,575);await page.waitForFunction(()=>window.badmintonState?.screen==='game');
  assert.equal((await page.evaluate(()=>window.badmintonState)).avatars[1],'female');
  await page.keyboard.press('Escape');await page.waitForFunction(()=>window.badmintonState?.paused);await page.mouse.click(720,645);
  await page.waitForFunction(()=>window.badmintonState?.screen==='menu');
  await page.reload();await page.waitForFunction(()=>window.badmintonState?.screen==='login');
  await fill(page,700,355,name);await fill(page,700,455,'points-ui-pass');await page.mouse.click(720,555);
  await page.waitForFunction(()=>window.badmintonState?.screen==='menu'&&window.badmintonState?.points===10);
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'artifacts','points-test.json'),JSON.stringify({ok:true,checks:['register/login','wrong password','Godot first victory +5','repeat victory +0','second athlete +5','cross-client account restore','homepage points leaderboard','eight opponent cards','female challenger','session reload'],errors},null,2));
  console.log('PASS: account UI, challenge reward flow, cross-client points, home leaderboard.');
 }catch(e){console.log('POINTS FAILURE',await activePage?.evaluate(()=>window.badmintonState),errors);await activePage?.screenshot({path:path.join(root,'.runtime','points-failure.png')});throw e;}finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
