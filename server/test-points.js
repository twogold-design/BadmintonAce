const assert=require('node:assert/strict');
const {WebSocket}=require('ws');
const url=process.env.TEST_URL||'ws://127.0.0.1:18765/ws',sockets=[];
function send(s,d){s.send(JSON.stringify(d));}
async function take(s,type){const end=Date.now()+5000;while(Date.now()<end){const i=s.queue.findIndex(m=>m.type===type);if(i>=0)return s.queue.splice(i,1)[0];await new Promise(r=>setTimeout(r,10));}throw Error('Missing '+type);}
async function connect(){const s=new WebSocket(url);s.queue=[];sockets.push(s);s.on('message',r=>s.queue.push(JSON.parse(r)));await require('node:events').once(s,'open');return s;}
(async()=>{
 const a=await connect();send(a,{type:'create'});assert.match((await take(a,'error')).message,/登录/);
 send(a,{type:'hello',name:'cannot-bypass-login'});assert.match((await take(a,'error')).message,/登录/);
 const name='积分'+require('node:crypto').randomBytes(5).toString('hex');
 send(a,{type:'register',name,password:'points-test-pass'});const profile=await take(a,'profile');
 send(a,{type:'leaders'});assert.ok((await take(a,'leaders')).players.some(p=>p.id===profile.id));
 const b=await connect();send(b,{type:'login',name,password:'wrong-password'});await take(b,'error');
 send(b,{type:'login',name,password:'points-test-pass'});assert.equal((await take(b,'profile')).id,profile.id);
 send(a,{type:'challenge_start',opponent:'shi-yuqi'});const run=await take(a,'challenge_started');
 send(b,{type:'create'});assert.match((await take(b,'error')).message,/正在比赛/);
 send(a,{type:'challenge_finish',challenge:run.challenge,score:[3,0]});await take(a,'error');
 send(a,{type:'challenge_finish',challenge:'made-up',score:[11,0]});await take(a,'error');
 send(a,{type:'challenge_finish',challenge:run.challenge,score:[11,9]});assert.equal((await take(a,'challenge_recorded')).points,5);
 const update=await take(a,'leaders');assert.equal(update.players.find(p=>p.id===profile.id).points,5);
 send(a,{type:'challenge_finish',challenge:run.challenge,score:[11,9]});assert.equal((await take(a,'challenge_recorded')).points,5);
 send(a,{type:'challenge_start',opponent:'shi-yuqi'});const again=await take(a,'challenge_started');
 send(a,{type:'challenge_finish',challenge:again.challenge,score:[11,0]});const receipt=await take(a,'challenge_recorded');assert.equal(receipt.award,0);assert.equal(receipt.points,5);
 send(a,{type:'challenge_start',opponent:'chen-yufei'});const female=await take(a,'challenge_started');
 send(a,{type:'challenge_finish',challenge:female.challenge,score:[11,0]});assert.equal((await take(a,'challenge_recorded')).points,10);
 const fresh=await connect();send(fresh,{type:'login',name,password:'points-test-pass'});const restored=await take(fresh,'profile');assert.equal(restored.points,10);assert.deepEqual(restored.completed,['chen-yufei','shi-yuqi']);
 send(fresh,{type:'logout'});await take(fresh,'logged_out');send(fresh,{type:'hello',token:restored.token});await take(fresh,'error');
 console.log('PASS: mandatory login, password authentication, cross-device points, live leaderboard, valid challenge sessions, duplicate reward rejection.');
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{for(const s of sockets)s.close();});
