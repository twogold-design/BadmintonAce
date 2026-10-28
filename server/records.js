'use strict';
const {DatabaseSync}=require('node:sqlite');
const crypto=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
const scrypt=require('node:util').promisify(crypto.scrypt);
const opponents=new Set(require('../assets/challenges.json').map(row=>row.id));
function accountName(value){
 const name=String(value||'').normalize('NFKC').trim();
 if(!/^[\p{L}\p{N}_-]{2,16}$/u.test(name))throw Error('账号须为 2–16 个字母、汉字、数字、下划线或短横线。');
 return {name,key:name.toLowerCase()};
}
function checkPassword(value){if(typeof value!=='string'||value.length<3||value.length>128)throw Error('密码须为 3–128 个字符。');}
class Records {
 constructor(file){
  fs.mkdirSync(path.dirname(file),{recursive:true});
  this.db=new DatabaseSync(file);
  this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
   CREATE TABLE IF NOT EXISTS players(id TEXT PRIMARY KEY,token TEXT UNIQUE NOT NULL,name TEXT NOT NULL,wins INTEGER NOT NULL DEFAULT 0,games INTEGER NOT NULL DEFAULT 0);
   CREATE TABLE IF NOT EXISTS matches(id TEXT PRIMARY KEY,host TEXT NOT NULL,guest TEXT NOT NULL,a INTEGER NOT NULL,b INTEGER NOT NULL,finished INTEGER NOT NULL);`);
  const columns=this.db.prepare('PRAGMA table_info(matches)').all().map(c=>c.name);
  if(!columns.includes('winner'))this.db.exec('ALTER TABLE matches ADD COLUMN winner TEXT');
  if(!columns.includes('reason'))this.db.exec("ALTER TABLE matches ADD COLUMN reason TEXT NOT NULL DEFAULT 'played'");
  this.db.exec('UPDATE matches SET winner=CASE WHEN a>b THEN host ELSE guest END WHERE winner IS NULL');
  const playerColumns=this.db.prepare('PRAGMA table_info(players)').all().map(c=>c.name);
  if(!playerColumns.includes('points')){this.db.exec('ALTER TABLE players ADD COLUMN points INTEGER NOT NULL DEFAULT 0; UPDATE players SET points=wins*10');}
  this.db.exec(`CREATE TABLE IF NOT EXISTS accounts(account TEXT PRIMARY KEY,player TEXT NOT NULL UNIQUE REFERENCES players(id),salt TEXT NOT NULL,password TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,player TEXT NOT NULL REFERENCES players(id),expires INTEGER NOT NULL);
   CREATE TABLE IF NOT EXISTS challenge_runs(id TEXT PRIMARY KEY,player TEXT NOT NULL REFERENCES players(id),opponent TEXT NOT NULL,status TEXT NOT NULL,award INTEGER NOT NULL DEFAULT 0);
   CREATE TABLE IF NOT EXISTS challenge_rewards(player TEXT NOT NULL REFERENCES players(id),opponent TEXT NOT NULL,finished INTEGER NOT NULL,PRIMARY KEY(player,opponent));`);
 }
 profile(token,name){
  name=String(name||'').replace(/[\p{C}]/gu,'').trim().slice(0,16);
  if(token){
   const p=this.db.prepare('SELECT id,name FROM players WHERE token=?').get(digest(String(token)));
   if(!p)throw Error('身份已失效，请清除本服务的本地身份后重连。');
   if(name){this.db.prepare('UPDATE players SET name=? WHERE id=?').run(name,p.id);p.name=name;}
   return {...p,token};
  }
  const id=crypto.randomBytes(8).toString('hex');token=crypto.randomBytes(32).toString('hex');
  name ||= '球友'+id.slice(0,4);
  this.db.prepare('INSERT INTO players(id,token,name) VALUES(?,?,?)').run(id,digest(token),name);
  return {id,name,token};
 }
 summary(id){
  const player=this.db.prepare('SELECT id,name,wins,games,points FROM players WHERE id=?').get(id);
  if(!player)throw Error('账号不存在，请重新登录。');
  return {...player,completed:this.db.prepare('SELECT opponent FROM challenge_rewards WHERE player=? ORDER BY opponent').all(id).map(r=>r.opponent)};
 }
 session(id){
  const token=crypto.randomBytes(32).toString('hex');
  this.db.prepare('DELETE FROM sessions WHERE expires<?').run(Date.now());
  this.db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(digest(token),id,Date.now()+30*24*60*60*1000);
  return {...this.summary(id),token};
 }
 async register(value,password){
  const {name,key}=accountName(value);checkPassword(password);
  if(this.db.prepare('SELECT player FROM accounts WHERE account=?').get(key))throw Error('该账号已注册，请直接登录。');
  const salt=crypto.randomBytes(16).toString('hex'),hash=(await scrypt(password,salt,64)).toString('hex');
  this.db.exec('BEGIN IMMEDIATE');
  try{
   if(this.db.prepare('SELECT player FROM accounts WHERE account=?').get(key))throw Error('该账号已注册，请直接登录。');
   const player=this.profile('',name);
   this.db.prepare('INSERT INTO accounts VALUES(?,?,?,?)').run(key,player.id,salt,hash);
   const result=this.session(player.id);this.db.exec('COMMIT');return result;
  }catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 async login(value,password){
  const {key}=accountName(value);checkPassword(password);
  const account=this.db.prepare('SELECT * FROM accounts WHERE account=?').get(key);
  if(!account){
   try{return await this.register(value,password);}
   catch(e){
    // Another first login may have created this name while scrypt was pending.
    // Always validate that account's password; never replace its credentials.
    if(this.db.prepare('SELECT player FROM accounts WHERE account=?').get(key))return this.login(value,password);
    throw e;
   }
  }
  const candidate=await scrypt(password,account?.salt||'missing-account',64);
  if(!account||!crypto.timingSafeEqual(candidate,Buffer.from(account.password,'hex')))throw Error('账号或密码不正确。');
  return this.session(account.player);
 }
 resume(token){
  const session=this.db.prepare('SELECT player FROM sessions WHERE token=? AND expires>?').get(digest(String(token||'')),Date.now());
  if(!session)throw Error('登录已过期，请输入账号和密码。');
  return {...this.summary(session.player),token};
 }
 logout(token){this.db.prepare('DELETE FROM sessions WHERE token=?').run(digest(String(token||'')));}
 startChallenge(player,opponent){
  if(!opponents.has(opponent))throw Error('请选择列表中的挑战对手。');
  const id=crypto.randomUUID();
  this.db.exec('BEGIN IMMEDIATE');
  try{
   this.db.prepare("UPDATE challenge_runs SET status='cancelled' WHERE player=? AND status='active'").run(player);
   this.db.prepare("INSERT INTO challenge_runs(id,player,opponent,status) VALUES(?,?,?,'active')").run(id,player,opponent);
   this.db.exec('COMMIT');return id;
  }catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 cancelChallenge(player){this.db.prepare("UPDATE challenge_runs SET status='cancelled' WHERE player=? AND status='active'").run(player);}
 finishChallenge(player,id,won){
  this.db.exec('BEGIN IMMEDIATE');
  try{
   const run=this.db.prepare('SELECT * FROM challenge_runs WHERE id=? AND player=?').get(id,player);
   if(!run||run.status==='cancelled')throw Error('挑战已失效，请重新选择对手。');
   let award=run.award;
   if(run.status==='active'){
    award=won&&this.db.prepare('INSERT OR IGNORE INTO challenge_rewards VALUES(?,?,?)').run(player,run.opponent,Date.now()).changes?5:0;
    this.db.prepare('UPDATE players SET points=points+? WHERE id=?').run(award,player);
    this.db.prepare("UPDATE challenge_runs SET status='finished',award=? WHERE id=?").run(award,id);
   }
   this.db.exec('COMMIT');return {challenge:id,opponent:run.opponent,award,...this.summary(player)};
  }catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 finish(id,host,guest,score,winner=score[0]>score[1]?0:1,reason='played'){
  if(![0,1].includes(winner)||!['played','forfeit'].includes(reason))throw Error('Invalid match result');
  this.db.exec('BEGIN IMMEDIATE');
  try{
   const inserted=this.db.prepare('INSERT OR IGNORE INTO matches(id,host,guest,a,b,finished,winner,reason) VALUES(?,?,?,?,?,?,?,?)').run(id,host,guest,score[0],score[1],Date.now(),winner===0?host:guest,reason);
   if(inserted.changes){
    this.db.prepare('UPDATE players SET games=games+1,wins=wins+? WHERE id=?').run(winner===0?1:0,host);
    this.db.prepare('UPDATE players SET games=games+1,wins=wins+? WHERE id=?').run(winner===1?1:0,guest);
    this.db.prepare('UPDATE players SET points=points+10 WHERE id=?').run(winner===0?host:guest);
   }
   this.db.exec('COMMIT');return Boolean(inserted.changes);
  }catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 leaders(){return this.db.prepare('SELECT p.id,p.name,p.wins,p.games,p.points FROM players p JOIN accounts a ON a.player=p.id ORDER BY p.points DESC,p.wins DESC,p.name COLLATE NOCASE,p.id LIMIT 20').all();}
 close(){this.db.close();}
}
module.exports={Records};
