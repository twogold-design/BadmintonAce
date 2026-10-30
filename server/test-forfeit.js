'use strict';
// Own isolated server/database; the running game service is never touched.
if(process.argv.includes('--service')){
  require('./server');
  process.on('message',message=>{if(message==='shutdown'){process.disconnect();process.emit('SIGTERM');}});
}else{
  const assert=require('node:assert/strict');
  const fs=require('node:fs'),path=require('node:path');
  const {fork}=require('node:child_process');
  const {once}=require('node:events');
  const {WebSocket}=require('ws');
  const {Records}=require('./records');
  const dir=fs.mkdtempSync(path.join(process.env.TEMP||require('node:os').tmpdir(),'ace-forfeit-'));
  const port=18767,sockets=[];
  const service=fork(__filename,['--service'],{env:{...process.env,PORT:String(port),DATA_DIR:dir,LAN_ONLY:'1'},silent:true,windowsHide:true});
  service.stderr.pipe(process.stderr);
  function send(s,d){s.send(JSON.stringify({protocol:5,...d}));}
  async function take(s,type){
    const end=Date.now()+5000;
    while(Date.now()<end){const i=s.queue.findIndex(m=>m.type===type);if(i>=0)return s.queue.splice(i,1)[0];await new Promise(r=>setTimeout(r,10));}
    throw Error('Missing '+type);
  }
  async function connect(token=''){
    const s=new WebSocket(`ws://127.0.0.1:${port}/ws`);s.queue=[];sockets.push(s);
    s.on('message',r=>s.queue.push(JSON.parse(r)));await once(s,'open');
    send(s,token?{type:'hello',token}:{type:'register',name:'退出'+require('node:crypto').randomBytes(6).toString('hex'),password:'test-only-pass'});s.profile=await take(s,'profile');return s;
  }
  async function match(){
    const a=await connect(),b=await connect();send(a,{type:'create'});const room=await take(a,'created');
    send(b,{type:'join',code:room.code});const pair=await take(a,'paired');await take(b,'paired');
    send(a,{type:'relay_ready',match:pair.match});send(b,{type:'relay_ready',match:pair.match});
    const start=await take(a,'start');await take(b,'start');return {a,b,id:start.match};
  }
  async function stats(s,id){send(s,{type:'leaders'});return (await take(s,'leaders')).players.find(p=>p.id===id);}
  (async()=>{
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error('Server startup timeout')),10000);
      service.once('error',reject);service.once('exit',code=>reject(Error('Server exited: '+code)));
      service.stdout.on('data',data=>{if(data.toString().includes('Badminton Ace:')){clearTimeout(timer);resolve();}});
    });
    for(const loser of [0,1]){
      const {a,b,id}=await match(),pair=[a,b];
      if(loser===0)pair[loser].terminate();else send(pair[loser],{type:'leave'});
      const result=await take(pair[1-loser],'match_result');
      assert.deepEqual(result,{type:'match_result',match:id,winner:1-loser,score:null,reason:'forfeit',recorded:true});
      const loserAgain=await connect(pair[loser].profile.token);
      assert.equal((await stats(loserAgain,pair[loser].profile.id)).wins,0);
      assert.equal((await stats(loserAgain,pair[loser].profile.id)).games,1);
      assert.equal((await stats(loserAgain,pair[1-loser].profile.id)).wins,1);
      assert.equal((await stats(loserAgain,pair[1-loser].profile.id)).points,10);
      assert.equal((await stats(loserAgain,pair[loser].profile.id)).points,0);
      // A duplicate leave or late finish cannot count the match twice.
      send(pair[1-loser],{type:'finish',match:id,score:[11,0]});send(pair[1-loser],{type:'leave'});await take(pair[1-loser],'left');
      assert.equal((await stats(loserAgain,pair[1-loser].profile.id)).games,1);
    }
    for(const phase of ['point','end']){
      const {a,b,id}=await match();send(a,{type:'finish',match:id,score:[11,9]});
      if(phase==='end'){send(b,{type:'finish',match:id,score:[11,9]});await take(a,'recorded');await take(b,'recorded');}
      // The winner leaving before finish acknowledgements must not reverse it.
      a.close();const result=await take(b,'match_result');
      assert.equal(result.reason,'played');assert.equal(result.winner,0);assert.equal(result.recorded,true);
      assert.equal((await stats(b,a.profile.id)).wins,1);
    }
    const idle=await connect();send(idle,{type:'create'});await take(idle,'created');send(idle,{type:'leave'});await take(idle,'left');
    assert.equal((await stats(idle,idle.profile.id)).games,0,'Waiting-room departure is not a loss');
    const preHost=await connect(),preGuest=await connect();
    send(preHost,{type:'create'});const pending=await take(preHost,'created');
    send(preGuest,{type:'join',code:pending.code});const pairing=await take(preGuest,'paired');await take(preHost,'paired');
    send(preGuest,{type:'relay_failed',match:pairing.match});await take(preHost,'peer_unavailable');await take(preGuest,'peer_unavailable');
    send(preGuest,{type:'list'});assert.ok(!(await take(preGuest,'rooms')).rooms.some(r=>r.code===pending.code));
    assert.equal((await stats(preGuest,preHost.profile.id)).games,0,'Failed direct connection does not count a match');
    const shutdownMatch=await match();
    const exited=once(service,'exit');service.send('shutdown');await exited;
    const db=new Records(path.join(dir,'rankings.sqlite'));
    assert.equal(db.db.prepare('SELECT count(*) AS n FROM matches').get().n,4,'Shutdown creates no forfeit');
    assert.equal(db.db.prepare('SELECT games FROM players WHERE id=?').get(shutdownMatch.a.profile.id).games,0);
    assert.equal(db.db.prepare("SELECT count(*) AS n FROM matches WHERE reason='forfeit'").get().n,2);
    db.close();
    console.log('PASS: host/guest departure, leading player forfeits, reconnect persistence, no duplicate, terminal score preserved, idle departure, server shutdown.');
  })().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{for(const s of sockets)s.terminate();if(service.exitCode===null)service.kill();});
}
