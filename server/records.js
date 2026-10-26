'use strict';
const {DatabaseSync}=require('node:sqlite');
const crypto=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
class Records {
 constructor(file){
  fs.mkdirSync(path.dirname(file),{recursive:true});
  this.db=new DatabaseSync(file);
  this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
   CREATE TABLE IF NOT EXISTS players(id TEXT PRIMARY KEY,token TEXT UNIQUE NOT NULL,name TEXT NOT NULL,wins INTEGER NOT NULL DEFAULT 0,games INTEGER NOT NULL DEFAULT 0);
   CREATE TABLE IF NOT EXISTS matches(id TEXT PRIMARY KEY,host TEXT NOT NULL,guest TEXT NOT NULL,a INTEGER NOT NULL,b INTEGER NOT NULL,finished INTEGER NOT NULL);`);
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
 finish(id,host,guest,score){
  this.db.exec('BEGIN IMMEDIATE');
  try{
   const inserted=this.db.prepare('INSERT OR IGNORE INTO matches VALUES(?,?,?,?,?,?)').run(id,host,guest,score[0],score[1],Date.now());
   if(inserted.changes){
    this.db.prepare('UPDATE players SET games=games+1,wins=wins+? WHERE id=?').run(score[0]>score[1]?1:0,host);
    this.db.prepare('UPDATE players SET games=games+1,wins=wins+? WHERE id=?').run(score[1]>score[0]?1:0,guest);
   }
   this.db.exec('COMMIT');return Boolean(inserted.changes);
  }catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 leaders(){return this.db.prepare('SELECT id,name,wins,games FROM players WHERE games>0 ORDER BY wins DESC,1.0*wins/games DESC,games ASC,id ASC LIMIT 20').all();}
 close(){this.db.close();}
}
module.exports={Records};
