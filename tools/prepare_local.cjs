const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.resolve(__dirname, '..');
const web = path.join(root, 'build', 'web');
const bundle = {files:{},worklets:{}};
for (const name of ['index.wasm','index.pck']) {
  const bytes = fs.readFileSync(path.join(web,name));
  bundle.files[name] = {size:bytes.length,mime:name.endsWith('.wasm')?'application/wasm':'application/octet-stream',gzip:zlib.gzipSync(bytes,{level:9}).toString('base64')};
}
for (const name of ['index.audio.worklet.js','index.audio.position.worklet.js']) bundle.worklets[name] = fs.readFileSync(path.join(web,name),'utf8');
fs.writeFileSync(path.join(web,'local-data.js'),'window.ACE_LOCAL_DATA='+JSON.stringify(bundle)+';\n');
fs.copyFileSync(path.join(__dirname,'local-loader.js'),path.join(web,'local-loader.js'));
// Godot probes PWA updates even with PWA export disabled. file: has no service workers.
const enginePath = path.join(web,'index.js');
const engine = fs.readFileSync(enginePath,'utf8');
const hook = 'function _godot_js_pwa_cb(p_update_cb){';
const guardedHook = hook + 'if(location.protocol==="file:")return;';
if (!engine.includes(hook)) throw new Error('Godot PWA callback changed; review the local-file guard.');
if (!engine.includes(guardedHook)) fs.writeFileSync(enginePath,engine.replace(hook,guardedHook));
console.log('Prepared local-file resources: '+(fs.statSync(path.join(web,'local-data.js')).size/1e6).toFixed(2)+' MB');
