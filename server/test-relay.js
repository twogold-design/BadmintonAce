'use strict';
const assert=require('node:assert/strict');
const {snapshotInfo,controlPacket,forward,clearPending}=require('./relay');
const match='12345678-1234-1234-1234-123456789012';
function snapshot(id=match,seq=1){
 const frame=Buffer.alloc(360);frame[0]=186;frame[1]=3;frame.writeUInt32LE(36,2);frame.write(id,6,36);frame.writeUInt32LE(seq,42);
 return frame;
}
async function test(){
 const frame=snapshot();assert.deepEqual(snapshotInfo(frame),{match,seq:1,terminal:false});
 for(const bad of [frame.subarray(0,359),Buffer.concat([frame,Buffer.alloc(1)])])assert.equal(snapshotInfo(bad),null);
 const nan=Buffer.from(frame);nan.writeFloatLE(NaN,54);assert.equal(snapshotInfo(nan),null);
 const reason=Buffer.from(frame);reason.writeUInt32LE(10000,112);assert.equal(snapshotInfo(reason),null);
 const touch=Buffer.from(frame);touch[237]=1;assert.equal(snapshotInfo(touch),null);
 assert.equal(controlPacket({type:'input',match,action:'jump'},true,match),null);
 assert.equal(controlPacket({type:'input',match,action:'move',seq:1,x:NaN,y:0},false,match),null);
 assert.equal(controlPacket({type:'pause',match:'old',value:true},false,match),null);
 assert.equal(controlPacket({type:'logged_out',match},true,match),null);
 assert.deepEqual(controlPacket({type:'pause',match,value:true,recipient:'outsider'},false,match),{type:'pause',match,value:true});
 const delivered=[],ws={readyState:1,bufferedAmount:5000,send:(raw,options)=>delivered.push({raw,options}),close(code){this.closed=code;}};
 for(let i=0;i<100;i++)forward(ws,snapshot(match,i),true,'state');
 assert.equal(ws.relayPending.size,1);assert.equal(delivered.length,0);
 ws.bufferedAmount=0;await new Promise(r=>setTimeout(r,30));
 assert.equal(delivered.length,1);assert.equal(snapshotInfo(delivered[0].raw).seq,99);
 ws.bufferedAmount=5000;forward(ws,frame,true,'state');forward(ws,frame,true);
 assert.equal(ws.relayPending.size,0,'Terminal state removes queued flight');
 forward(ws,frame,true,'state');clearPending(ws);ws.bufferedAmount=0;
 await new Promise(r=>setTimeout(r,30));assert.equal(delivered.length,2,'Cleared room cannot deliver queued snapshots');
 ws.bufferedAmount=262145;assert.equal(forward(ws,'control',false),false);assert.equal(ws.closed,1013);
 console.log('PASS relay: binary framing, finite numbers, role/match/type validation, bounded latest-frame queues, terminal ordering, congestion handling.');
}
if(require.main===module)test().catch(e=>{console.error(e);process.exitCode=1;});
module.exports={snapshot};
