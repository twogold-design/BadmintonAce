'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {spawn}=require('node:child_process'),{once}=require('node:events');
const {WebSocket}=require('ws'),{DatabaseSync}=require('node:sqlite');
const {localRequest}=require('./gm');
const root=path.resolve(__dirname,'..'),port=18769,base=`http://127.0.0.1:${port}`;
const directory=fs.mkdtempSync(path.join(root,'.runtime','gm-test-')),sockets=[];
let service,key;
const send=(s,d)=>s.send(JSON.stringify({protocol:5,...d}));
async function take(s,type){for(let t=0;t<500;t++){const i=s.queue.findIndex(x=>x.type===type);if(i>=0)return s.queue.splice(i,1)[0];await new Promise(r=>setTimeout(r,10));}throw Error('Missing '+type+JSON.stringify(s.queue));}
async function connect(){const s=new WebSocket(base.replace('http','ws')+'/ws');s.queue=[];sockets.push(s);s.on('message',d=>s.queue.push(JSON.parse(d)));await once(s,'open');return s;}
async function register(name){const s=await connect();send(s,{type:'register',name,password:'gm-test-pass'});s.profile=await take(s,'profile');return s;}
async function api(route,data,headers={}){const r=await fetch(base+route,{method:data?'POST':'GET',headers:{Authorization:'Bearer '+key,...(data?{'Content-Type':'application/json'}:{}),...headers},body:data?JSON.stringify(data):undefined});return {status:r.status,body:await r.json()};}
async function action(action,target,confirm){const r=await api('/gm/api/action',{action,target,confirm});assert.equal(r.status,200,JSON.stringify(r));return r.body;}
(async()=>{
 for(const [address,host,extra,allowed] of [['127.0.0.1','127.0.0.1:8766',{},true],['::1','localhost:8766',{},true],['192.168.1.8','127.0.0.1:8766',{},false],['127.0.0.1','evil.example',{},false],['127.0.0.1','localhost:8766',{origin:'https://evil.example'},false],['127.0.0.1','localhost:8766',{'x-forwarded-for':'127.0.0.1'},false]])assert.equal(localRequest({socket:{remoteAddress:address},headers:{host,...extra}}),allowed);
 const env={...process.env,PORT:String(port),DATA_DIR:directory,WEB_ROOT:path.join(root,'build/web')};
 service=spawn(process.env.ACE_GM_EXE||process.execPath,process.env.ACE_GM_EXE?[]:['server/server.js'],{cwd:root,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Service startup timeout')),10000);service.stdout.on('data',d=>{if(d.toString().includes(`localhost:${port}`)){clearTimeout(timer);resolve();}});service.stderr.on('data',d=>process.stderr.write(d));service.once('error',reject);service.once('exit',c=>reject(Error('Server exit '+c)));});
 key=fs.readFileSync(path.join(directory,'gm-key.txt'),'utf8').trim();
 assert.equal((await api('/gm/api/players',null,{Authorization:''})).status,401);
 assert.equal((await api('/gm/api/players',null,{Origin:'https://evil.example'})).status,403);
 assert.equal((await api('/gm/api/players',null,{'X-Forwarded-For':'127.0.0.1'})).status,403);
 assert.equal(await new Promise((resolve,reject)=>{require('node:http').get(base+'/gm/api/players',{headers:{Host:'evil.example',Authorization:'Bearer '+key}},r=>{r.resume();resolve(r.statusCode);}).on('error',reject);}),403);
 const a=await register('管理甲'),b=await register('管理乙');
 send(a,{type:'challenge_start',opponent:'shi-yuqi'});const run=await take(a,'challenge_started');
 send(a,{type:'challenge_finish',challenge:run.challenge,score:[11,0]});assert.equal((await take(a,'challenge_recorded')).points,5);
 send(b,{type:'leaders'});await take(b,'leaders');
 assert.equal((await api('/gm/api/action',{action:'delete_account',target:a.profile.id,confirm:'wrong'})).status,400);
 assert.equal(fs.existsSync(path.join(directory,'gm-backups')),false);
 const reset=await action('reset_points',a.profile.id,'管理甲');await take(a,'logged_out');
 const scores=await take(b,'leaders');assert.equal(scores.players.find(p=>p.id===a.profile.id).points,0);
 const old=await connect();send(old,{type:'hello',token:a.profile.token});await take(old,'error');
 const fresh=await connect();send(fresh,{type:'login',name:'管理甲',password:'gm-test-pass'});fresh.profile=await take(fresh,'profile');assert.deepEqual(fresh.profile.completed,[]);
 send(fresh,{type:'challenge_finish',challenge:run.challenge,score:[11,0]});await take(fresh,'error');
 send(fresh,{type:'challenge_start',opponent:'shi-yuqi'});const retry=await take(fresh,'challenge_started');send(fresh,{type:'challenge_finish',challenge:retry.challenge,score:[11,0]});assert.equal((await take(fresh,'challenge_recorded')).points,5);
 const snapshot=new DatabaseSync(path.join(directory,'gm-backups',reset.backup),{readOnly:true});assert.equal(snapshot.prepare('SELECT points FROM players WHERE id=?').get(a.profile.id).points,5);snapshot.close();
 send(fresh,{type:'create'});const room=await take(fresh,'created');send(b,{type:'join',code:room.code});const pair=await take(fresh,'paired');await take(b,'paired');send(fresh,{type:'relay_ready',match:pair.match});send(b,{type:'relay_ready',match:pair.match});await take(fresh,'start');await take(b,'start');
 await action('delete_account',a.profile.id,'管理甲');await take(fresh,'logged_out');assert.match((await take(b,'peer_unavailable')).message,/管理员/);
 const list=(await api('/gm/api/players')).body;assert.equal(list.total,1);assert.equal(list.players[0].games,0);assert.equal(list.players[0].points,0);assert.equal(JSON.stringify(list).includes('password'),false);assert.equal(JSON.stringify(list).includes('token'),false);
 const again=await register('管理甲');assert.notEqual(again.profile.id,a.profile.id);
 assert.equal((await api('/gm/api/players?search=%25')).body.total,0);
 await action('reset_points','all','清除全部积分');assert.equal((await api('/gm/api/players')).body.totals.points,0);
 await action('delete_account','all','删除全部账号');assert.equal((await api('/gm/api/players')).body.total,0);
 const db=new DatabaseSync(path.join(directory,'rankings.sqlite'),{readOnly:true});for(const table of ['players','accounts','sessions','challenge_runs','challenge_rewards','matches'])assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n,0);assert.equal(db.prepare('SELECT COUNT(*) AS n FROM gm_audit').get().n,4);db.close();
 console.log('PASS GM: local-only access, authentication, confirmation, single/all reset/delete, session revocation, replay rejection, reward reset, live match cancellation without forfeit, backups, account reuse.');
 if(process.env.ACE_GM_BROWSER==='1')await new Promise((resolve,reject)=>{const child=spawn(process.execPath,['tools/gm_check.cjs'],{cwd:root,env:{...env,ACE_TEST_URL:base,ACE_GM_KEY_FILE:path.join(directory,'gm-key.txt')},windowsHide:true,stdio:'inherit'});child.once('error',reject);child.once('exit',c=>c===0?resolve():reject(Error('GM browser exit '+c)));});
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{for(const s of sockets)s.terminate();if(service)service.kill();});
