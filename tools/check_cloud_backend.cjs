// Isolated HTTPS reverse proxy + backend-only service; never touches live data.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),https=require('node:https'),net=require('node:net');
const {spawn,execFileSync}=require('node:child_process');
const {once}=require('node:events'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..'),dir=fs.mkdtempSync(path.join(root,'.runtime/cloud-test-'));
const backendPort=18782,tlsPort=18783,requests=[],connections=new Set();
function run(file,env){return new Promise((resolve,reject)=>{
 const child=spawn(process.execPath,[file],{cwd:root,env,stdio:'inherit',windowsHide:true});
 child.once('error',reject);child.once('exit',code=>code===0?resolve():reject(Error(`${file}: ${code}`)));
});}
(async()=>{
 const key=path.join(dir,'key.pem'),cert=path.join(dir,'cert.pem');
 execFileSync(process.env.OPENSSL_BIN||'openssl',['req','-x509','-newkey','rsa:2048','-sha256','-days','1','-nodes','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1','-keyout',key,'-out',cert],{cwd:dir,windowsHide:true,stdio:'pipe'});
 const env={...process.env,PORT:String(backendPort),SERVE_WEB:'0',LAN_ONLY:'0',TRUST_PROXY:'1',DATA_DIR:path.join(dir,'data'),PUBLIC_URL:'',ACE_ARTIFACT_DIR:path.join(dir,'screenshots'),ACE_TEST_TLS:'1',ACE_TEST_URL:`https://127.0.0.1:${tlsPort}`,ACE_ENTRY_URL:pathToFileURL(path.join(root,'index.html')).href};
 // WEB_ROOT is deliberately absent on this backend.
 env.WEB_ROOT=path.join(dir,'no-game-assets');
 const executable=process.env.ACE_TEST_SERVER_EXE;
 const service=spawn(executable||process.execPath,executable?[]:['server/server.js'],{cwd:root,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
 const serviceExit=once(service,'exit');
 const proxy=https.createServer({key:fs.readFileSync(key),cert:fs.readFileSync(cert)},(req,res)=>{
  requests.push(req.url);
  const upstream=http.request({hostname:'127.0.0.1',port:backendPort,path:req.url,method:req.method,headers:{...req.headers,'x-forwarded-proto':'https','x-forwarded-for':req.socket.remoteAddress}},r=>{res.writeHead(r.statusCode,r.headers);r.pipe(res);});
  upstream.on('error',()=>{res.writeHead(502);res.end();});req.pipe(upstream);
 });
 proxy.on('connection',socket=>{connections.add(socket);socket.on('close',()=>connections.delete(socket));});
 proxy.on('upgrade',(req,socket,head)=>{
  const upstream=net.connect(backendPort,'127.0.0.1',()=>{
   const headers={...req.headers,'x-forwarded-proto':'https','x-forwarded-for':req.socket.remoteAddress};
   upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`+Object.entries(headers).map(([k,v])=>`${k}: ${v}\r\n`).join('')+'\r\n');
   if(head.length)upstream.write(head);upstream.pipe(socket);socket.pipe(upstream);
  });
  upstream.on('error',()=>socket.destroy());socket.on('error',()=>upstream.destroy());socket.on('close',()=>upstream.destroy());
 });
 try{
  await new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>reject(Error('Backend startup timed out')),10000);
   service.once('error',e=>{clearTimeout(timer);reject(e);});service.once('exit',code=>{clearTimeout(timer);reject(Error(`Backend exit ${code}`));});
   service.stdout.on('data',data=>{if(data.toString().includes(`localhost:${backendPort}`)){clearTimeout(timer);resolve();}});
   service.stderr.on('data',data=>process.stderr.write(data));
  });
  proxy.listen(tlsPort,'127.0.0.1');await once(proxy,'listening');
  for(const route of ['/index.html','/index.pck','/index.wasm','/local-data.js'])assert.equal((await fetch(`http://127.0.0.1:${backendPort}${route}`)).status,404,route+' is not served');
  const health=await (await fetch(`http://127.0.0.1:${backendPort}/health`)).json();assert.equal(health.transport,'websocket-relay');
  await run('tools/online_check.cjs',env);
  assert.ok(!requests.some(url=>/\.(pck|wasm|png|js)(\?|$)/.test(url)),'Players load no game assets from backend');
  const online=JSON.parse(fs.readFileSync(path.join(env.ACE_ARTIFACT_DIR,'online-test.json'),'utf8'));
  fs.writeFileSync(path.join(root,'artifacts/cloud-backend-test.json'),JSON.stringify({ok:true,backend_only:true,https_proxy:true,wss_gameplay:true,game_resources_served:false,real_public_deployment:false,online},null,2)+'\n');
  fs.copyFileSync(path.join(env.ACE_ARTIFACT_DIR,'guest.png'),path.join(root,'artifacts/cloud-relay.png'));
  console.log('PASS cloud backend: local game packages → WSS through HTTPS proxy → backend-only service; WebRTC disabled; no assets on backend.');
 }finally{
  for(const socket of connections)socket.destroy();proxy.close();service.kill();await serviceExit;
 }
})().catch(error=>{console.error(error);process.exitCode=1;});
