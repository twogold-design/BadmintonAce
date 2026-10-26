'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer, WebSocket } = require('ws');
const {connectionInfo, invitation} = require('./links');
const {allowRequest} = require('./access');
const {Records} = require('./records');
const isExe = require('node:sea').isSea();
const home = isExe ? path.dirname(process.execPath) : path.join(__dirname,'..');

const port = Number(process.env.PORT || 8766);
const lanOnly = process.env.LAN_ONLY !== '0';
const root = path.resolve(process.env.WEB_ROOT || path.join(home, 'build', 'web'));
const records = new Records(path.join(process.env.DATA_DIR || path.join(home,'data'),'rankings.sqlite'));
const rooms = new Map();
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml','.json':'application/json','.css':'text/css','.txt':'text/plain; charset=utf-8'};
const server = http.createServer((req, res) => {
  if (!allowRequest(req,lanOnly)) {
    res.writeHead(403,{'Content-Type':'text/plain; charset=utf-8'});
    return res.end('仅允许局域网直接连接。请使用主机内网 IP，并关闭公网代理或穿透。');
  }
  if (req.url === '/health') {
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify({ok:true, app:'badminton-ace', version:2, lanOnly, rooms:rooms.size}));
  }
  if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405); return res.end(); }
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); }
  catch { res.writeHead(400); return res.end(); }
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (file !== root && !file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) { res.writeHead(404); return res.end('File not found. Export the Godot Web build first.'); }
    res.writeHead(200, {'Content-Type':mime[path.extname(file)] || 'application/octet-stream', 'Content-Length':stat.size, 'Cache-Control':'no-cache', 'X-Content-Type-Options':'nosniff'});
    if (req.method === 'HEAD') return res.end();
    const stream = fs.createReadStream(file);
    stream.on('error', () => res.destroy());
    stream.pipe(res);
  });
});
const wss = new WebSocketServer({server, path:'/ws', maxPayload:32768, perMessageDeflate:false,
  verifyClient:({req})=>allowRequest(req,lanOnly)});
function send(ws, data) { if (ws && ws.readyState === WebSocket.OPEN && ws.bufferedAmount < 1048576) ws.send(JSON.stringify(data)); }
function error(ws, message) { send(ws, {type:'error', message}); }
function passwordHash(password,salt){return crypto.scryptSync(password,salt,32);}
function validScore(score,goal){
  if(!Array.isArray(score)||score.length!==2||!score.every(n=>Number.isInteger(n)&&n>=0))return false;
  const [high,low]=[Math.max(...score),Math.min(...score)],cap=goal===21?30:15;
  return high<=cap&&low<high&&high>=goal&&(high===cap||high-low>=2)&&!(low>=goal&&high-low>2)&&!(low<goal-1&&high>goal);
}
function start(room,code,type='start'){
  room.match=crypto.randomUUID();room.confirmations=new Map();room.finalScore=null;room.settled=false;
  for(const [role,ws] of [['host',room.host],['guest',room.guest]])send(ws,{type,role,code,goal:room.goal,match:room.match});
}
function leave(ws) {
  if (!ws.code) return;
  const room = rooms.get(ws.code);
  if (room) {
    const other = room.host === ws ? room.guest : room.host;
    if (other) { other.code = null; send(other, {type:'peer_left'}); }
    rooms.delete(ws.code);
  }
  ws.code = null;
}
wss.on('connection', (ws, req) => {
  ws.connectionInfo = connectionInfo(req, port, lanOnly ? '' : process.env.PUBLIC_URL);
  ws.lanAddress = ws.connectionInfo.scope==='lan' ? ws.connectionInfo.base.replace(/^http:/,'ws:').replace(/^https:/,'wss:')+'/ws' : '';
  send(ws,{type:'connection',...ws.connectionInfo,lanOnly,lanAddress:ws.lanAddress});
  ws.alive = true;
  ws.count = 0;
  ws.window = Date.now();
  ws.passwordFailures=0;
  ws.on('pong', () => { ws.alive = true; });
  ws.on('error', () => {});
  ws.on('message', (raw) => {
    if (Date.now() - ws.window > 1000) { ws.window = Date.now(); ws.count = 0; }
    if (++ws.count > 160) return ws.close(1008, 'Too many messages');
    let d;
    try { d = JSON.parse(raw.toString()); } catch { return error(ws, '消息格式错误。'); }
    if (!d || typeof d !== 'object' || Array.isArray(d)) return;
    if (d.type === 'ping') return send(ws, {type:'pong', stamp:Number(d.stamp)||0});
    if(d.type==='hello'){
      if(ws.code)return error(ws,'对局中不能更换身份。');
      try{ws.profile=records.profile(d.token,d.name);send(ws,{type:'profile',...ws.profile});}
      catch(e){error(ws,e.message);}
      return;
    }
    if(!ws.profile)return error(ws,'请先连接并设置昵称。');
    if(d.type==='list')return send(ws,{type:'rooms',rooms:[...rooms.entries()].slice(0,50).map(([code,r])=>({code,name:r.host.profile.name,locked:Boolean(r.password),players:r.guest?2:1,goal:r.goal}))});
    if(d.type==='leaders')return send(ws,{type:'leaders',players:records.leaders(),self:ws.profile.id});
    if (d.type === 'create') {
      const password=String(d.password||'');
      if(password.length>32)return error(ws,'房间密码最多 32 个字符。');
      if(Date.now()-(ws.lastCreate||0)<1000)return error(ws,'请稍后再创建房间。');
      ws.lastCreate=Date.now();
      leave(ws);
      if (rooms.size >= 1000) return error(ws, '服务繁忙，请稍后再试。');
      let code;
      do { code = crypto.randomBytes(4).toString('hex').slice(0,6).toUpperCase(); } while (rooms.has(code));
      const salt=crypto.randomBytes(16);
      rooms.set(code, {host:ws, guest:null, goal:d.goal === 21 ? 21 : 11, created:Date.now(),salt,password:password?passwordHash(password,salt):null});
      ws.code = code;
      return send(ws, {type:'created', code, invitation:lanOnly ? '' : invitation(ws.connectionInfo,code),scope:ws.connectionInfo.scope,lanOnly,lanAddress:ws.lanAddress});
    }
    if (d.type === 'join') {
      const code = String(d.code || '').toUpperCase();
      const room = rooms.get(code);
      if (!room) return error(ws, '房间不存在或已结束，请让房主重新创建并分享邀请链接。');
      if (room.host === ws) return error(ws, '你已经是房主。');
      if (room.guest) return error(ws, '房间已满，请使用另一个房间。');
      if(room.host.profile.id===ws.profile.id)return error(ws,'请使用两个不同玩家身份进行对战。');
      if(String(d.password||'').length>32)return error(ws,'房间密码最多 32 个字符。');
      if(room.password&&!crypto.timingSafeEqual(room.password,passwordHash(String(d.password||''),room.salt))){
        error(ws,'房间密码不正确，请重新输入。');
        if(++ws.passwordFailures>=5)ws.close(1008,'Too many password attempts');
        return;
      }
      leave(ws);
      room.guest = ws;
      ws.code = code;
      start(room,code);
      return;
    }
    const room = rooms.get(ws.code);
    if (!room || !room.guest) return;
    const host = room.host === ws;
    const other = host ? room.guest : room.host;
    if(d.type==='finish'){
      if(d.match!==room.match||!validScore(d.score,room.goal)||JSON.stringify(d.score)!==JSON.stringify(room.finalScore))return error(ws,'结算结果不符合当前对局。');
      if(room.settled)return send(ws,{type:'recorded',match:room.match});
      room.confirmations.set(ws.profile.id,JSON.stringify(d.score));
      if(room.confirmations.size===2){
        try{records.finish(room.match,room.host.profile.id,room.guest.profile.id,d.score);room.settled=true;
          send(room.host,{type:'recorded',match:room.match});send(room.guest,{type:'recorded',match:room.match});
        }catch(e){console.error('Score persistence failed:',e.message);error(ws,'战绩保存失败，请保留房间稍后重试。');}
      }
      return;
    }
    if(d.type==='rematch'){
      if(!room.settled)return error(ws,'请等待双方完成结算后再开始下一局。');
      start(room,ws.code,'rematch');return;
    }
    if ((host && ['state','effect'].includes(d.type)) || (!host && d.type === 'input') || d.type==='pause') {
      if(d.type==='state'&&d.phase==='end'&&validScore(d.score,room.goal))room.finalScore=d.score;
      if (d.type === 'input') {
        if (!['move','shot','jump','dash'].includes(d.action)) return;
        if (d.action === 'move' && (!Number.isFinite(d.x) || !Number.isFinite(d.y))) return;
        if (d.action === 'shot' && (!Number.isInteger(d.shot) || d.shot < 0 || d.shot > 3 || typeof d.pressed !== 'boolean')) return;
      }
      if (d.type === 'pause' && typeof d.value !== 'boolean') return;
      send(other, d);
    }
  });
  ws.on('close', () => leave(ws));
});
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
  for (const [code, room] of rooms) {
    if (!room.guest && Date.now() - room.created > 30*60*1000) {
      room.host.code = null;
      error(room.host, '等待超过 30 分钟，房间已关闭，请重新创建。');
      rooms.delete(code);
    }
  }
}, 15000);
server.listen(port, '0.0.0.0', () => {
  console.log(`Badminton Ace: http://localhost:${port}`);
  console.log(`Web root: ${root}`);
  console.log('谁是羽毛球高手 · 房间与战绩服务器（关闭窗口即停止服务）');
  console.log(`排行榜数据: ${path.join(process.env.DATA_DIR || path.join(home,'data'),'rankings.sqlite')}`);
  console.log(`Access: ${lanOnly ? 'LAN only (direct private-address clients)' : 'Public deployment enabled'}`);
  for (const entries of Object.values(require('node:os').networkInterfaces()))
    for (const a of entries || []) if (a.family === 'IPv4' && !a.internal) console.log(`LAN connection: ws://${a.address}:${port}/ws (open the extracted index.html locally)`);
});
server.on('error',e=>{console.error('服务器启动失败：',e.message);clearInterval(heartbeat);records.close();process.exitCode=1;});
function shutdown() { clearInterval(heartbeat); for (const ws of wss.clients) ws.close(1001,'Server shutdown'); wss.close(); server.close(()=>records.close()); }
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
