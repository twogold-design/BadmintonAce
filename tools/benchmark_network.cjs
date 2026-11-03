'use strict';
// Replay the identical captured game frames through actual WebSocket framing.
// Loopback only. Reports socket bytes, including WS framing but not TLS/IP fees.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {once}=require('node:events');
const {performance}=require('node:perf_hooks');
const {WebSocket,WebSocketServer}=require('../server/node_modules/ws');
const {compressionOptions}=require('../server/network-options');
const source=path.resolve(process.argv[2]||'.runtime/network-baseline/network-samples.json');
const output=path.resolve(process.argv[3]||'artifacts/network-optimization.json');
const pairs=Number(process.env.ACE_BENCH_PAIRS||5);
const capture=JSON.parse(fs.readFileSync(source,'utf8'));
const groups=[0,1].map(player=>capture.samples.filter(s=>s.player===player).map(s=>({...s,raw:Buffer.from(s.data,'base64')})));
assert.ok(groups.every(g=>g.length>0),'Capture both directions first');
const percentile=(values,p)=>values.toSorted((a,b)=>a-b)[Math.min(values.length-1,Math.floor(values.length*p))];
async function replay(options){
 const server=new WebSocketServer({host:'127.0.0.1',port:0,perMessageDeflate:options,maxPayload:32768});
 await once(server,'listening');
 const links=[],latencies=[],categories={};let messages=0,payload=0,wire=0;
 try{
  for(let i=0;i<pairs*2;i++){
   const connection=once(server,'connection');
   const client=new WebSocket(`ws://127.0.0.1:${server.address().port}`,{perMessageDeflate:compressionOptions(),maxPayload:32768});
   await once(client,'open');const [upstream]=await connection;
   assert.equal(client.extensions.includes('permessage-deflate'),Boolean(options));
   links.push({client,upstream,samples:groups[i%2],before:upstream._socket.bytesWritten});
  }
  const cpu=process.cpuUsage(),started=performance.now();
  await Promise.all(links.map(async({client,upstream,samples})=>{
   for(const s of samples){
    const received=once(client,'message'),at=performance.now(),before=upstream._socket.bytesWritten;
    upstream.send(s.raw,{binary:s.binary});
    const [raw,binary]=await received;
    latencies.push(performance.now()-at);
    assert.equal(binary,s.binary);assert.deepEqual(raw,s.raw,'Every decompressed byte must match');
    messages++;payload+=s.raw.length;
    const category=s.binary?['serve','rally','point','end'][s.raw[78]]:'controls';
    categories[category] ||= {messages:0,wire_bytes:0,payload_bytes:0};
    categories[category].messages++;categories[category].wire_bytes+=upstream._socket.bytesWritten-before;categories[category].payload_bytes+=s.raw.length;
   }
  }));
  const elapsed=performance.now()-started,used=process.cpuUsage(cpu);
  for(const link of links)wire+=link.upstream._socket.bytesWritten-link.before;
  return {connections:links.length,messages,payload_bytes:payload,wire_bytes:wire,categories,elapsed_ms:elapsed,cpu_ms:(used.user+used.system)/1000,
   delivery_ms:{p50:percentile(latencies,.5),p95:percentile(latencies,.95),p99:percentile(latencies,.99),max:Math.max(...latencies)},rss_mb:process.memoryUsage().rss/1e6};
 }finally{for(const {client,upstream} of links){client.terminate();upstream.terminate();}await new Promise(r=>server.close(r));}
}
(async()=>{
 const baseline=await replay(false),independent=await replay({...compressionOptions(),serverNoContextTakeover:true,clientNoContextTakeover:true}),optimized=await replay(compressionOptions());
 assert.ok(optimized.wire_bytes<baseline.wire_bytes*.8,'Expected meaningful compression on real game samples');
 const span=(capture.samples.at(-1).time-capture.samples[0].time)/1000;
 const report={method:`Identical real Godot Web game trace; ${pairs} concurrent room pairs; accelerated local replay; exact byte equality checked for every delivery. Socket bytes include WebSocket framing, exclude TLS/TCP/IP overhead, authentication and unrelated host traffic. Not a cloud bill or ECS benchmark.`,trace_seconds:span,baseline,independent,optimized,saved_percent:100*(1-optimized.wire_bytes/baseline.wire_bytes),
  observed_game_trace_gb_per_hour:optimized.wire_bytes/span*3600/1e9,
  reference:'https://github.com/websockets/ws#websocket-compression'};
 fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
