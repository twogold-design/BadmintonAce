const assert=require('node:assert/strict');
const {WebSocket}=require('ws');
const url=process.env.TEST_URL||'ws://127.0.0.1:8765/ws';
async function connect(){const s=await new Promise((resolve,reject)=>{const s=new WebSocket(url);s.queue=[];s.on('message',r=>s.queue.push(JSON.parse(r)));s.once('open',()=>resolve(s));s.once('error',reject)});send(s,{type:'register',name:'测试'+require('node:crypto').randomBytes(6).toString('hex'),password:'test-only-pass'});s.profile=await take(s,'profile');return s;}
async function take(s,type,predicate=()=>true){const end=Date.now()+5000;while(Date.now()<end){const i=s.queue.findIndex(m=>m.type===type&&predicate(m));if(i>=0)return s.queue.splice(i,1)[0];await new Promise(r=>setTimeout(r,10));}throw Error('Missing '+type);}
function send(s,d){s.send(JSON.stringify(d));}
(async()=>{
 const a=await connect(),b=await connect(),c=await connect();
 send(c,{type:'list'});assert.deepEqual((await take(c,'rooms')).rooms,[]);
 send(b,{type:'join',code:'ZZZZZZ'});assert.match((await take(b,'error')).message,/不存在/);
 send(a,{type:'create',goal:21,password:'test-pass'});const room=await take(a,'created');assert.match(room.code,/^[0-9A-F]{6}$/);
 const listing=await take(c,'rooms');assert.equal(listing.rooms.find(r=>r.code===room.code).locked,true);assert.ok(!JSON.stringify(listing).includes('test-pass'));
 assert.ok((await take(a,'rooms')).rooms.some(r=>r.code===room.code),'Host sees their own idle room');
 send(b,{type:'join',code:room.code,password:'bad'});assert.match((await take(b,'error')).message,/密码/);
 send(b,{type:'join',code:room.code,password:'test-pass'});const pair=await take(a,'paired');await take(b,'paired');
 send(a,{type:'signal',match:pair.match,signal:{kind:'offer',sdp:'test-offer'}});assert.equal((await take(b,'signal')).signal.sdp,'test-offer');
 send(a,{type:'peer_ready',match:pair.match});send(b,{type:'peer_ready',match:pair.match});
 const match=await take(a,'start');assert.equal(match.role,'host');assert.equal((await take(b,'start')).goal,11);
 assert.deepEqual((await take(c,'rooms')).rooms,[],'Full room disappears without refreshing');
 send(c,{type:'list'});assert.deepEqual((await take(c,'rooms')).rooms,[],'List endpoint excludes full rooms');
 send(c,{type:'join',code:room.code});assert.match((await take(c,'error')).message,/已满/);
 send(b,{type:'input',action:'move',x:1,y:-1});
 send(a,{type:'state',score:[2,3]});
 send(b,{type:'state',score:[999,0]});await new Promise(r=>setTimeout(r,80));assert.equal(a.queue.some(m=>m.type==='state'),false);
 send(b,{type:'pause',value:true});await new Promise(r=>setTimeout(r,80));
 assert.ok(!a.queue.some(m=>['input','pause'].includes(m.type))&&!b.queue.some(m=>m.type==='state'),'Gameplay never relays through the server');
 send(b,{type:'finish',match:match.match,score:[21,0]});assert.match((await take(b,'error')).message,/结算/);
 send(a,{type:'finish',match:match.match,score:[11,9]});
 send(b,{type:'finish',match:match.match,score:[11,9]});await take(a,'recorded');await take(b,'recorded');
 send(a,{type:'finish',match:match.match,score:[11,9]});await take(a,'recorded');
 send(a,{type:'leaders'});const leaders=await take(a,'leaders');const winner=leaders.players.find(p=>p.id===a.profile.id);assert.equal(winner.wins,1);assert.equal(winner.games,1);assert.equal(winner.points,10);
 send(a,{type:'rematch'});const again=await take(b,'rematch');assert.notEqual(again.match,match.match);await take(a,'rematch');
 b.close();const forfeited=await take(a,'match_result');assert.equal(forfeited.reason,'forfeit');assert.equal(forfeited.winner,0);assert.equal(forfeited.recorded,true);
 send(c,{type:'join',code:room.code});assert.match((await take(c,'error')).message,/不存在/);
 c.queue=c.queue.filter(m=>m.type!=='rooms');
 send(c,{type:'create'});const publicRoom=await take(c,'created');
 assert.equal((await take(c,'rooms',m=>m.rooms.some(r=>r.code===publicRoom.code))).rooms[0].locked,false);
 send(c,{type:'leave'});await take(c,'left');
 assert.deepEqual((await take(c,'rooms')).rooms,[],'Closing an idle room updates its owner');
 await take(a,'rooms',m=>m.rooms.some(r=>r.code===publicRoom.code));
 await take(a,'rooms',m=>m.rooms.length===0);
 await new Promise(r=>setTimeout(r,1050));
 send(c,{type:'create'});const disconnected=await take(c,'created');
 await take(a,'rooms',m=>m.rooms.some(r=>r.code===disconnected.code));
 a.queue=a.queue.filter(m=>m.type!=='rooms');c.close();
 assert.deepEqual((await take(a,'rooms')).rooms,[],'Host disconnect removes idle room');
 a.close();c.close();console.log('PASS: password, room list, relay, role checks, bilateral settlement, duplicate rejection, leaderboard, rematch, disconnect.');
})().catch(e=>{console.error(e);process.exit(1)});
