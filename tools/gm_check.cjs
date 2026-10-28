'use strict';
const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {enterAccount,challenge}=require('./account_helpers.cjs');
const root=path.resolve(__dirname,'..'),base=process.env.ACE_TEST_URL,key=fs.readFileSync(process.env.ACE_GM_KEY_FILE,'utf8').trim();
(async()=>{
 const browser=await chromium.launchPersistentContext(path.join(root,'.runtime','gm-check-'+Date.now()),{executablePath:process.env.ACE_BROWSER||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,viewport:{width:1440,height:900},args:['--enable-unsafe-swiftshader','--disable-crash-reporter','--disable-breakpad']});
 try{
  const errors=[],gm=await browser.newPage();gm.on('pageerror',e=>errors.push(e.message));
  await gm.goto(base+'/gm#'+key);await gm.locator('#manager').waitFor({state:'visible'});assert.equal(new URL(gm.url()).hash,'');
  const game=await browser.newPage();game.on('pageerror',e=>errors.push(e.message));await game.goto(base);await game.waitForFunction(()=>window.badmintonState?.screen==='login');await game.screenshot({path:path.join(root,'artifacts','single-login.png')});await enterAccount(game);const name=await game.evaluate(()=>window.badmintonState.account);await challenge(game);
  await gm.locator('#refresh').click();await gm.getByRole('cell',{name:'账号：'+name,exact:false}).waitFor();await gm.screenshot({path:path.join(root,'artifacts','gm-management.png')});
  await gm.getByRole('button',{name:'清除积分',exact:true}).click();assert.equal(await gm.locator('#execute').isDisabled(),true);await gm.locator('#confirm-text').fill('wrong');assert.equal(await gm.locator('#execute').isDisabled(),true);await gm.locator('#confirm-text').fill(name);await gm.locator('#execute').click();await gm.locator('#confirmation').waitFor({state:'hidden'});
  try{await game.waitForFunction(()=>window.badmintonState?.screen==='login'&&window.badmintonState?.status.includes('管理员'));}catch(e){console.log('GM GAME STATE',await game.evaluate(()=>window.badmintonState));console.log('GM STATUS',await gm.locator('#status').textContent());await game.screenshot({path:path.join(root,'.runtime','gm-game-failure.png')});throw e;}assert.equal(await game.evaluate(()=>window.badmintonState.account_id),'');
  await gm.getByRole('button',{name:'删除账号',exact:true}).click();await gm.locator('#cancel').click();assert.equal(await gm.locator('#players tr').count(),1);
  await gm.getByRole('button',{name:'删除账号',exact:true}).click();await gm.locator('#confirm-text').fill(name);await gm.screenshot({path:path.join(root,'artifacts','gm-delete-confirm.png')});await gm.locator('#execute').click();await gm.waitForFunction(()=>document.getElementById('totals').textContent.startsWith('0 个'));
  await gm.setViewportSize({width:700,height:800});await gm.screenshot({path:path.join(root,'artifacts','gm-small-window.png')});assert.equal(await gm.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await gm.locator('#logout').click();await gm.locator('#login').waitFor({state:'visible'});assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'artifacts','gm-test.json'),JSON.stringify({ok:true,checks:['GM key fragment removed','account list','confirmation gates','clear points logs active game out','cancel deletion','delete account','700px layout','exit management'],errors},null,2));console.log('PASS GM browser: management UI, confirmations, live Godot logout, deletion, narrow window.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
