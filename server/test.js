const assert=require('node:assert/strict');
const {WebSocket}=require('ws');
const url=process.env.TEST_URL||'ws://127.0.0.1:8765/ws';
async function connect(){const s=await new Promise((resolve,reject)=>{const s=new WebSocket(url);s.queue=[];s.on('message',r=>s.queue.push(JSON.parse(r)));s.once('open',()=>resolve(s));s.once('error',reject)});send(s,{type:'hello',name:'测试球友'});s.profile=await take(s,'profile');return s;}
async function take(s,type){const end=Date.now()+5000;while(Date.now()<end){const i=s.queue.findIndex(m=>m.type===type);if(i>=0)return s.queue.splice(i,1)[0];await new Promise(r=>setTimeout(r,10));}throw Error('Missing '+type);}
function send(s,d){s.send(JSON.stringify(d));}
(async()=>{
 const a=await connect(),b=await connect(),c=await connect();
 send(b,{type:'join',code:'ZZZZZZ'});assert.match((await take(b,'error')).message,/不存在/);
 send(a,{type:'create',goal:21,password:'test-pass'});const room=await take(a,'created');assert.match(room.code,/^[0-9A-F]{6}$/);
 send(c,{type:'list'});const listing=await take(c,'rooms');assert.equal(listing.rooms.find(r=>r.code===room.code).locked,true);assert.ok(!JSON.stringify(listing).includes('test-pass'));
 send(b,{type:'join',code:room.code,password:'bad'});assert.match((await take(b,'error')).message,/密码/);
 send(b,{type:'join',code:room.code,password:'test-pass'});const match=await take(a,'start');assert.equal(match.role,'host');assert.equal((await take(b,'start')).goal,21);
 send(c,{type:'join',code:room.code});assert.match((await take(c,'error')).message,/已满/);
 send(b,{type:'input',action:'move',x:1,y:-1});assert.equal((await take(a,'input')).x,1);
 send(a,{type:'state',score:[2,3]});assert.deepEqual((await take(b,'state')).score,[2,3]);
 send(b,{type:'state',score:[999,0]});await new Promise(r=>setTimeout(r,80));assert.equal(a.queue.some(m=>m.type==='state'),false);
 send(b,{type:'pause',value:true});assert.equal((await take(a,'pause')).value,true);
 send(b,{type:'finish',match:match.match,score:[21,0]});assert.match((await take(b,'error')).message,/结算/);
 send(a,{type:'state',phase:'end',score:[21,9]});await take(b,'state');
 send(a,{type:'finish',match:match.match,score:[21,9]});
 send(b,{type:'finish',match:match.match,score:[21,9]});await take(a,'recorded');await take(b,'recorded');
 send(a,{type:'finish',match:match.match,score:[21,9]});await take(a,'recorded');
 send(a,{type:'leaders'});const leaders=await take(a,'leaders');const winner=leaders.players.find(p=>p.id===a.profile.id);assert.equal(winner.wins,1);assert.equal(winner.games,1);
 send(a,{type:'rematch'});const again=await take(b,'rematch');assert.notEqual(again.match,match.match);await take(a,'rematch');
 b.close();await take(a,'peer_left');
 send(c,{type:'join',code:room.code});assert.match((await take(c,'error')).message,/不存在/);
 a.close();c.close();console.log('PASS: password, room list, relay, role checks, bilateral settlement, duplicate rejection, leaderboard, rematch, disconnect.');
})().catch(e=>{console.error(e);process.exit(1)});
