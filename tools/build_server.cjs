const fs=require('node:fs');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const {inject}=require('postject');
const esbuild=require('esbuild');
const root=path.resolve(__dirname,'..');
const out=path.join(root,'build','server');
(async()=>{
 fs.mkdirSync(out,{recursive:true});
 const bundle=path.join(out,'server.cjs');
 await esbuild.build({entryPoints:[path.join(root,'server/server.js')],outfile:bundle,bundle:true,platform:'node',format:'cjs',target:'node24',external:['bufferutil','utf-8-validate'],banner:{js:"process.env.WS_NO_BUFFER_UTIL='1';process.env.WS_NO_UTF_8_VALIDATE='1';"}});
 const blob=path.join(out,'server.blob');
 const config=path.join(out,'sea.json');
 fs.writeFileSync(config,JSON.stringify({main:bundle,output:blob,disableExperimentalSEAWarning:true,useSnapshot:false,useCodeCache:false}));
 const p=spawnSync(process.execPath,['--experimental-sea-config',config],{cwd:root,stdio:'inherit',windowsHide:true});
 if(p.status!==0)throw Error('SEA preparation failed');
 const exe=path.join(root,'BadmintonAce-Server.exe');
 const binary=fs.readFileSync(process.execPath);
 // Strip the copied runtime's Authenticode certificate before adding our resource.
 const pe=binary.readUInt32LE(0x3c),optional=pe+24;
 const directory=optional+(binary.readUInt16LE(optional)===0x20b?112:96);
 const cert=binary.readUInt32LE(directory+4*8),size=binary.readUInt32LE(directory+4*8+4);
 binary.writeUInt32LE(0,directory+4*8);binary.writeUInt32LE(0,directory+4*8+4);
 binary.writeUInt32LE(0,optional+64);
 fs.writeFileSync(exe,cert&&cert+size===binary.length?binary.subarray(0,cert):binary);
 await inject(exe,'NODE_SEA_BLOB',fs.readFileSync(blob),{sentinelFuse:'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2'});
 console.log('Built standalone server:',exe,'MB:',(fs.statSync(exe).size/1e6).toFixed(2));
})().catch(e=>{console.error(e);process.exitCode=1});
