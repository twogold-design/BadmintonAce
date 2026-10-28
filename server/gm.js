'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const ui=require('./gm-ui');
const hash=value=>crypto.createHash('sha256').update(String(value)).digest();
const localAddress=value=>['127.0.0.1','::1','::ffff:127.0.0.1'].includes(value);
function localRequest(req){
 if(!localAddress(req.socket.remoteAddress))return false;
 if(['forwarded','x-forwarded-for','x-real-ip','cf-connecting-ip','x-forwarded-host','x-forwarded-proto'].some(k=>req.headers[k]!==undefined))return false;
 try{
  const origin=new URL('http://'+req.headers.host);
  if(!['127.0.0.1','localhost','[::1]'].includes(origin.hostname))return false;
  if(req.headers.origin&&req.headers.origin!==origin.origin)return false;
  return req.headers['sec-fetch-site']!=='cross-site';
 }catch{return false;}
}
class GM {
 constructor(records,directory,onChange){
  this.db=records.db;this.directory=directory;this.onChange=onChange;
  const keyFile=path.join(directory,'gm-key.txt');
  fs.mkdirSync(directory,{recursive:true});
  try{fs.writeFileSync(keyFile,crypto.randomBytes(32).toString('hex'),{flag:'wx',mode:0o600});}
  catch(e){if(e.code!=='EEXIST')throw e;}
  this.key=fs.readFileSync(keyFile,'utf8').trim();
  if(!/^[a-f0-9]{64}$/.test(this.key))throw Error('GM key file is invalid: '+keyFile);
  this.db.exec(`CREATE TABLE IF NOT EXISTS gm_audit(id INTEGER PRIMARY KEY,created INTEGER NOT NULL,action TEXT NOT NULL,target TEXT NOT NULL,affected INTEGER NOT NULL,backup TEXT NOT NULL)`);
 }
 list(query){
  const search=String(query.get('search')||'').slice(0,64);
  const pattern='%'+search.replace(/[\\%_]/g,'\\$&')+'%';
  const where="WHERE p.name LIKE ? ESCAPE '\\' OR COALESCE(a.account,'') LIKE ? ESCAPE '\\'";
  const total=this.db.prepare(`SELECT COUNT(*) AS n FROM players p LEFT JOIN accounts a ON a.player=p.id ${where}`).get(pattern,pattern).n;
  const page=Math.min(Math.max(1,parseInt(query.get('page'),10)||1),Math.max(1,Math.ceil(total/30)));
  const players=this.db.prepare(`SELECT p.id,p.name,a.account,p.points,p.wins,p.games FROM players p LEFT JOIN accounts a ON a.player=p.id ${where} ORDER BY p.name COLLATE NOCASE,p.id LIMIT 30 OFFSET ?`).all(pattern,pattern,(page-1)*30);
  const totals=this.db.prepare('SELECT COUNT(*) AS players,COALESCE(SUM(points),0) AS points FROM players').get();
  return {players,total,page,pages:Math.max(1,Math.ceil(total/30)),totals,audit:this.db.prepare('SELECT created,action,target,affected,backup FROM gm_audit ORDER BY id DESC LIMIT 10').all()};
 }
 change(data){
  const actions={'reset_points':'清除积分','delete_account':'删除账号'};
  if(!Object.hasOwn(actions,data.action))throw Error('未知管理操作。');
  const all=data.target==='all';
  const player=all?null:this.db.prepare('SELECT id,name FROM players WHERE id=?').get(String(data.target||''));
  if(!all&&!player)throw Error('账号不存在，请刷新列表。');
  const confirmation=all?(data.action==='reset_points'?'清除全部积分':'删除全部账号'):player.name;
  if(data.confirm!==confirmation)throw Error('确认文字不匹配，未执行任何修改。');
  const ids=all?this.db.prepare('SELECT id FROM players').all().map(p=>p.id):[player.id];
  if(!ids.length)throw Error('没有可处理的账号。');
  // SQLite creates a consistent snapshot including WAL data before any mutation.
  const backupDir=path.join(this.directory,'gm-backups');fs.mkdirSync(backupDir,{recursive:true});
  const backup=Date.now()+'-'+crypto.randomBytes(4).toString('hex')+'.sqlite';
  this.db.prepare('VACUUM INTO ?').run(path.join(backupDir,backup));
  const target=all?'全部账号':player.name;
  this.db.exec('BEGIN IMMEDIATE');
  try{
   for(const id of ids){
    this.db.prepare('DELETE FROM sessions WHERE player=?').run(id);
    this.db.prepare('DELETE FROM challenge_runs WHERE player=?').run(id);
    this.db.prepare('DELETE FROM challenge_rewards WHERE player=?').run(id);
    if(data.action==='reset_points')this.db.prepare('UPDATE players SET points=0 WHERE id=?').run(id);
    else{
     this.db.prepare('DELETE FROM matches WHERE host=? OR guest=?').run(id,id);
     this.db.prepare('DELETE FROM accounts WHERE player=?').run(id);
     this.db.prepare('DELETE FROM players WHERE id=?').run(id);
    }
   }
   this.db.prepare('INSERT INTO gm_audit(created,action,target,affected,backup) VALUES(?,?,?,?,?)').run(Date.now(),actions[data.action],target,ids.length,backup);
   this.db.exec('COMMIT');
  }catch(e){this.db.exec('ROLLBACK');throw e;}
  this.onChange(ids);
  return {ok:true,affected:ids.length,backup,message:`已${actions[data.action]}：${target}（${ids.length} 个账号）。已自动备份。`};
 }
 handle(req,res){
  let url;try{url=new URL(req.url,'http://localhost');}catch{return false;}
  if(url.pathname!=='/gm'&&!url.pathname.startsWith('/gm/'))return false;
  const reply=(status,value,type='application/json; charset=utf-8')=>{
   res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"});
   res.end(type.startsWith('application/json')?JSON.stringify(value):value);
  };
  if(!localRequest(req)){reply(403,{error:'GM 仅允许服务器本机访问。'});return true;}
  if(req.method==='GET'&&['/gm','/gm/'].includes(url.pathname)){reply(200,ui.html,'text/html; charset=utf-8');return true;}
  if(req.method==='GET'&&url.pathname==='/gm/app.js'){reply(200,ui.script,'text/javascript; charset=utf-8');return true;}
  const token=String(req.headers.authorization||'').replace(/^Bearer /,'');
  if(!crypto.timingSafeEqual(hash(token),hash(this.key))){reply(401,{error:'管理密钥不正确，请从服务器本机打开 GM 管理。'});return true;}
  if(req.method==='GET'&&url.pathname==='/gm/api/players'){
   try{reply(200,this.list(url.searchParams));}catch(e){console.error('GM list:',e.message);reply(500,{error:'读取账号失败。'});}return true;
  }
  if(req.method==='POST'&&url.pathname==='/gm/api/action'){
   if(!String(req.headers['content-type']).startsWith('application/json')){reply(415,{error:'需要 JSON 请求。'});return true;}
   const chunks=[];let size=0,oversized=false;
   req.on('data',chunk=>{size+=chunk.length;if(size>4096){if(!oversized)reply(413,{error:'请求过长。'});oversized=true;}else chunks.push(chunk);});
   req.on('end',()=>{
    if(oversized)return;
    try{const data=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(!data||typeof data!=='object'||Array.isArray(data))throw Error('请求格式错误。');reply(200,this.change(data));}
    catch(e){console.error('GM action:',e.message);reply(400,{error:e.message});}
   });
   req.on('error',()=>{});return true;
  }
  reply(404,{error:'管理接口不存在。'});return true;
 }
}
module.exports={GM,localRequest};
