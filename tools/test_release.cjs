// Isolated test service; never stop or change the user's running game service.
const {spawn}=require('node:child_process');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const port=18765;
const env={...process.env,PORT:String(port),LAN_ONLY:'1',DATA_DIR:path.join(root,'.runtime','release-server-data'),PUBLIC_URL:'',ACE_TEST_URL:`http://127.0.0.1:${port}`,TEST_URL:`ws://127.0.0.1:${port}/ws`};
function run(file){return new Promise((resolve,reject)=>{
 const child=spawn(process.execPath,[file],{cwd:root,env,stdio:'inherit',windowsHide:true});
 child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(Error(`${file}: exit ${code}`)));
});}
(async()=>{
 const service=spawn(process.execPath,['server/server.js'],{cwd:root,env,stdio:['ignore','pipe','inherit'],windowsHide:true});
 try{
  await new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>reject(Error('Test service startup timeout')),10000);
   service.once('error',e=>{clearTimeout(timer);reject(e)});
   service.once('exit',code=>{clearTimeout(timer);reject(Error(`Test service exited: ${code}`))});
   service.stdout.on('data',data=>{if(data.toString().includes(String(port))){clearTimeout(timer);resolve()}});
  });
  await run('server/test-links.js');
  await run('server/test-access.js');
  await run('server/test-records.js');
  await run('server/test.js');
  await run('tools/online_check.cjs');
  await run('tools/check_local_entry.cjs');
 }finally{service.kill();}
})().catch(e=>{console.error(e);process.exitCode=1});
