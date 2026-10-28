'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {Records}=require('./records');
const directory=fs.mkdtempSync(path.join(__dirname,'../.runtime/auto-login-'));
(async()=>{
 const records=new Records(path.join(directory,'rankings.sqlite'));
 try{
  const first=await records.login('首次登录','first-login-pass');assert.equal(first.points,0);
  assert.equal((await records.login('首次登录','first-login-pass')).id,first.id);
  await assert.rejects(records.login('首次登录','wrong-pass'),/密码/);
  assert.equal(records.db.prepare('SELECT COUNT(*) AS n FROM accounts').get().n,1);
  const same=await Promise.all([records.login('并发同密码','same-password'),records.login('并发同密码','same-password')]);assert.equal(same[0].id,same[1].id);
  const different=await Promise.allSettled([records.login('并发异密码','password-one'),records.login('并发异密码','password-two')]);assert.equal(different.filter(r=>r.status==='fulfilled').length,1);assert.equal(different.filter(r=>r.status==='rejected').length,1);
  await assert.rejects(records.login('bad name','long-enough'),/账号/);await assert.rejects(records.login('无效密码','12'),/密码/);
  assert.equal(records.db.prepare('SELECT COUNT(*) AS n FROM accounts').get().n,3);
  const short=await records.login('三位密码','123');
  assert.equal((await records.login('三位密码','123')).id,short.id);
  await assert.rejects(records.login('三位密码','124'),/密码/);
  console.log('PASS auto-login: first account creation, existing password verification, concurrent first logins, invalid credentials leave no account.');
 }finally{records.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
