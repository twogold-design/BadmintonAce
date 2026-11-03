'use strict';
// Isolated database/port. Never connects to the public game server.
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),net=require('node:net');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const {WebSocket}=require('ws');
const {Records}=require('./records');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
  const probe=net.createServer();probe.listen(0,'127.0.0.1');await once(probe,'listening');
  const port=probe.address().port;await new Promise(r=>probe.close(r));
  const dir=fs.mkdtempSync(path.join(process.env.TEMP,'ace-traffic-'));
  const request=path.join(dir,'stop.request');
  const executable=process.env.ACE_TEST_SERVER_EXE||process.execPath;
  const service=spawn(executable,process.env.ACE_TEST_SERVER_EXE?[]:[path.join(__dirname,'server.js')],{
    env:{...process.env,PORT:String(port),DATA_DIR:dir,LAN_ONLY:'1',SERVE_WEB:'0',ACE_STOP_REQUEST:request},stdio:['ignore','pipe','pipe'],windowsHide:true
  });
  const sockets=[];let logs='';service.stdout.on('data',d=>logs+=d);service.stderr.on('data',d=>logs+=d);
  const exit=once(service,'exit');
  async function take(s,type){
    for(let n=0;n<500;n++){const i=s.queue.findIndex(m=>m.type===type);if(i>=0)return s.queue.splice(i,1)[0];await delay(10);}
    throw Error('Missing '+type+' '+logs);
  }
  function send(s,d){s.send(JSON.stringify({protocol:5,...d}));}
  async function connect(name){
    const s=new WebSocket(`ws://127.0.0.1:${port}/ws`);s.queue=[];sockets.push(s);
    s.on('message',r=>s.queue.push(JSON.parse(r)));s.on('close',code=>s.closedCode=code);await once(s,'open');
    send(s,{type:'register',name,password:'isolated-test-password'});s.profile=await take(s,'profile');return s;
  }
  try {
    let health;
    for(let i=0;i<100;i++){try{health=await (await fetch(`http://127.0.0.1:${port}/health`)).json();break;}catch{await delay(100);}}
    assert.equal(health?.trafficGuardControl,true,logs);
    const a=await connect('流量甲'),b=await connect('流量乙');
    send(a,{type:'create'});const room=await take(a,'created');send(b,{type:'join',code:room.code});
    const pair=await take(a,'paired');await take(b,'paired');
    send(a,{type:'relay_ready',match:pair.match});send(b,{type:'relay_ready',match:pair.match});
    await take(a,'start');await take(b,'start');
    // An uncooperative upgraded socket must not keep the process alive.
    const stalled=await connect('流量慢客户端');stalled._socket.pause();
    const started=Date.now();fs.writeFileSync(request,'test shutdown');
    let timeout;
    const result=await Promise.race([exit,new Promise((_,reject)=>{timeout=setTimeout(()=>reject(Error('Stop timeout '+logs)),6000);})]).finally(()=>clearTimeout(timeout));
    assert.equal(result[0],0,logs);assert.ok(Date.now()-started<5000);
    assert.equal(a.closedCode,1001);assert.equal(b.closedCode,1001);
    const db=new Records(path.join(dir,'rankings.sqlite'));
    try {
      assert.equal(db.db.prepare('SELECT count(*) AS n FROM matches').get().n,0,'Protection stop must not create a forfeit');
      assert.equal(db.db.prepare('SELECT games FROM players WHERE id=?').get(a.profile.id).games,0);
      assert.equal(db.db.prepare('SELECT games FROM players WHERE id=?').get(b.profile.id).games,0);
    } finally { db.close(); }
    console.log('PASS: '+(process.env.ACE_TEST_SERVER_EXE?'packaged EXE':'source')+' controlled traffic shutdown, slow client deadline, account persistence and no forfeit.');
  } finally {for(const s of sockets)s.terminate();if(service.exitCode===null)service.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
