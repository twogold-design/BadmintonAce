'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer, WebSocket } = require('ws');
const {connectionInfo, invitation} = require('./links');
const {allowRequest} = require('./access');
const {Records} = require('./records');
const relay = require('./relay');
const isExe = require('node:sea').isSea();
const home = isExe ? path.dirname(process.execPath) : path.join(__dirname,'..');

const port = Number(process.env.PORT || 8766);
const lanOnly = process.env.LAN_ONLY === '1';
const serveWeb = process.env.SERVE_WEB !== '0';
// Enable only behind a trusted reverse proxy that overwrites forwarding headers.
const trustProxy = process.env.TRUST_PROXY === '1';
const root = path.resolve(process.env.WEB_ROOT || path.join(home, 'build', 'web'));
const records = new Records(path.join(process.env.DATA_DIR || path.join(home,'data'),'rankings.sqlite'));
const gm = new (require('./gm').GM)(records,process.env.DATA_DIR || path.join(home,'data'),invalidateManagedAccounts);
const rooms = new Map();
const authAttempts=new Map();
let shuttingDown=false;
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml','.json':'application/json','.css':'text/css','.txt':'text/plain; charset=utf-8'};
const server = http.createServer((req, res) => {
  if(gm.handle(req,res))return;
  if (!allowRequest(req,lanOnly)) {
    res.writeHead(403,{'Content-Type':'text/plain; charset=utf-8'});
    return res.end('仅允许局域网直接连接。请使用主机内网 IP，并关闭公网代理或穿透。');
  }
  if (req.url === '/health') {
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify({ok:true, app:'badminton-ace', version:5, transport:'websocket-relay',lanOnly, rooms:rooms.size}));
  }
  if (!serveWeb) {
    res.writeHead(req.url==='/'?200:404,{'Content-Type':'application/json; charset=utf-8'});
    return res.end(JSON.stringify({app:'badminton-ace',service:'multiplayer-backend',websocket:'/ws'}));
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
function error(ws, message, action='') { send(ws, {type:'error', message,action}); }
function accountBusy(ws){return [...wss.clients].some(c=>c!==ws&&c.profile?.id===ws.profile.id&&(c.code||c.challenge));}
function broadcastScores(){
  const players=records.leaders();
  for(const client of wss.clients)if(client.profile){
    send(client,{type:'account_stats',...records.summary(client.profile.id)});
    if(client.watchLeaders)send(client,{type:'leaders',players,self:client.profile.id});
  }
}
function roomList() {
  return {type:'rooms', rooms:[...rooms.entries()].filter(([,r])=>!r.guest).map(([code,r])=>({code,name:r.host.profile.name,locked:Boolean(r.password),players:1,goal:r.goal}))};
}
function broadcastRooms() {
  const listing=roomList();
  for(const client of wss.clients)if(client.profile&&client.watchRooms)send(client,listing);
}
function invalidateManagedAccounts(ids){
  const affected=new Set(ids);
  // Administrative cancellation is not a player departure: never award a forfeit.
  for(const [code,room] of rooms){
    if(!affected.has(room.host.profile.id)&&!affected.has(room.guest?.profile.id))continue;
    rooms.delete(code);
    for(const client of [room.host,room.guest])if(client){relay.clearPending(client);client.code=null;if(!affected.has(client.profile.id))send(client,{type:'peer_unavailable',message:'管理员已取消本局，双方不计胜负或积分。'});}
  }
  for(const client of wss.clients)if(affected.has(client.profile?.id)){
    client.challenge=null;client.profile=null;client.watchLeaders=false;client.watchRooms=false;
    send(client,{type:'logged_out',message:'管理员已更新你的账号数据，请重新登录；账号若已删除，首次登录时会重新创建。'});client.close(1008,'Account updated by administrator');
  }
  broadcastRooms();broadcastScores();
}
function passwordHash(password,salt){return crypto.scryptSync(password,salt,32);}
function validScore(score){
  if(!Array.isArray(score)||score.length!==2||!score.every(n=>Number.isInteger(n)&&n>=0))return false;
  const [high,low]=[Math.max(...score),Math.min(...score)],goal=11,cap=15;
  return high<=cap&&low<high&&high>=goal&&(high===cap||high-low>=2)&&!(low>=goal&&high-low>2)&&!(low<goal-1&&high>goal);
}
function start(room,code,type='paired'){
  room.match=crypto.randomUUID();room.confirmations=new Map();room.finalScore=null;room.score=[0,0];room.settled=false;
  room.live=type==='rematch';room.ready=new Set();room.pairedAt=Date.now();
  room.stateSeq=-1;room.moveSeq=-1;
  relay.clearPending(room.host);relay.clearPending(room.guest);
  for(const [role,ws] of [['host',room.host],['guest',room.guest]])send(ws,{type,role,code,goal:room.goal,match:room.match});
}
function leave(ws) {
  relay.clearPending(ws);
  if (!ws.code) return;
  const room = rooms.get(ws.code);
  if (room) {
    const other = room.host === ws ? room.guest : room.host;
    relay.clearPending(other);
    if (other) {
      other.code = null;
      if(!shuttingDown&&!room.live){send(other,{type:'peer_left'});}
      else if(!shuttingDown){
        // A terminal score already received from the host stays final, even if
        // someone closes the page before both finish acknowledgements arrive.
        const score=room.finalScore||room.score;
        const winner=room.finalScore?(score[0]>score[1]?0:1):(room.host===ws?1:0);
        const reason=room.finalScore?'played':'forfeit';
        if(!room.settled){
          try{records.finish(room.match,room.host.profile.id,room.guest.profile.id,score,winner,reason);room.settled=true;broadcastScores();}
          catch(e){console.error('Departure settlement failed:',e.message);}
        }
        const result={type:'match_result',match:room.match,winner,score:reason==='played'?score:null,reason,recorded:room.settled};
        send(other,result);send(ws,result);
      }
    }
    rooms.delete(ws.code);
    broadcastRooms();
  }
  ws.code = null;
}
wss.on('connection', (ws, req) => {
  ws.connectionInfo = connectionInfo(req, port, lanOnly ? '' : process.env.PUBLIC_URL);
  ws.lanAddress = ws.connectionInfo.scope==='lan' ? ws.connectionInfo.base.replace(/^http:/,'ws:').replace(/^https:/,'wss:')+'/ws' : '';
  send(ws,{type:'connection',version:5,transport:'websocket-relay',...ws.connectionInfo,lanOnly,lanAddress:ws.lanAddress});
  ws.alive = true;
  ws.count = 0;
  ws.window = Date.now();
  ws.passwordFailures=0;
  ws.authBusy=false;
  ws.on('pong', () => { ws.alive = true; });
  ws.on('error', () => {});
  ws.on('message', async (raw,isBinary) => {
    if (Date.now() - ws.window > 1000) { ws.window = Date.now(); ws.count = 0; }
    if (++ws.count > 160) return ws.close(1008, 'Too many messages');
    if(isBinary){
      const room=rooms.get(ws.code);
      if(!ws.profile||ws.authBusy||!room?.live||room.host!==ws||!room.guest)return;
      const frame=relay.snapshotInfo(raw);
      if(!frame||frame.match!==room.match||frame.seq<=room.stateSeq)return;
      room.stateSeq=frame.seq;
      return relay.forward(room.guest,raw,true,frame.terminal?'':'state');
    }
    let d;
    try { d = JSON.parse(raw.toString()); } catch { return error(ws, '消息格式错误。'); }
    if (!d || typeof d !== 'object' || Array.isArray(d)) return;
    if (d.type === 'ping') return send(ws, {type:'pong', stamp:Number(d.stamp)||0});
    if(['register','login','hello'].includes(d.type)){
      if(ws.code||ws.challenge)return error(ws,'请先退出当前比赛再更换账号。',d.type);
      if(ws.authBusy)return;
      const forwarded=String(req.headers['x-forwarded-for']||'').split(',').at(-1).trim();
      const ip=trustProxy&&require('node:net').isIP(forwarded)?forwarded:req.socket.remoteAddress,now=Date.now();
      let attempt=authAttempts.get(ip);
      if(!attempt||now-attempt.since>60000){attempt={since:now,count:0};authAttempts.set(ip,attempt);}
      if(++attempt.count>120)return error(ws,'登录尝试过于频繁，请一分钟后重试。',d.type);
      ws.authBusy=true;
      try{
        const profile=d.type==='hello'?records.resume(d.token):await records[d.type](d.name,d.password);
        if(ws.readyState!==WebSocket.OPEN)return;
        ws.profile=profile;send(ws,{type:'profile',...profile});
      }catch(e){error(ws,e.message,d.type);}
      finally{ws.authBusy=false;}
      return;
    }
    if(!ws.profile||ws.authBusy)return error(ws,'请先登录账号。',d.type);
    if(['create','join'].includes(d.type)&&d.protocol!==5)return error(ws,'请更新网页到服务器转发版后再进入在线对战。',d.type);
    if(d.type==='logout'){
      leave(ws);if(ws.challenge)records.cancelChallenge(ws.profile.id);ws.challenge=null;records.logout(ws.profile.token);ws.profile=null;ws.watchLeaders=false;ws.watchRooms=false;
      return send(ws,{type:'logged_out'});
    }
    if(d.type==='list'){ws.watchRooms=true;return send(ws,roomList());}
    if(d.type==='leave'){leave(ws);return send(ws,{type:'left'});}
    if(d.type==='leaders'){ws.watchLeaders=true;return send(ws,{type:'leaders',players:records.leaders(),self:ws.profile.id});}
    if(d.type==='challenge_start'){
      if(ws.code||accountBusy(ws))return error(ws,'这个账号正在比赛，请先结束当前比赛。',d.type);
      try{const id=records.startChallenge(ws.profile.id,String(d.opponent));ws.challenge=id;send(ws,{type:'challenge_started',challenge:id,opponent:d.opponent});}
      catch(e){error(ws,e.message,d.type);}return;
    }
    if(d.type==='challenge_cancel'){if(ws.challenge){records.cancelChallenge(ws.profile.id);ws.challenge=null;}return;}
    if(d.type==='challenge_finish'){
      if(ws.code||accountBusy(ws)||!validScore(d.score))return error(ws,'挑战结果无效，请完成当前挑战后结算。',d.type);
      try{const result=records.finishChallenge(ws.profile.id,String(d.challenge),d.score[0]>d.score[1]);ws.challenge=null;send(ws,{type:'challenge_recorded',...result});broadcastScores();}
      catch(e){error(ws,e.message,d.type);}return;
    }
    if (d.type === 'create') {
      if(ws.challenge||accountBusy(ws))return error(ws,'这个账号正在比赛，请先结束当前比赛。',d.type);
      const password=String(d.password||'');
      if(password.length>32)return error(ws,'房间密码最多 32 个字符。');
      if(Date.now()-(ws.lastCreate||0)<1000)return error(ws,'请稍后再创建房间。');
      ws.lastCreate=Date.now();
      leave(ws);
      if (rooms.size >= 1000) return error(ws, '服务繁忙，请稍后再试。');
      let code;
      do { code = crypto.randomBytes(4).toString('hex').slice(0,6).toUpperCase(); } while (rooms.has(code));
      const salt=crypto.randomBytes(16);
      rooms.set(code, {host:ws, guest:null, goal:11, created:Date.now(),salt,password:password?passwordHash(password,salt):null});
      ws.code = code;
      send(ws, {type:'created', code, invitation:lanOnly||!serveWeb ? '' : invitation(ws.connectionInfo,code),scope:ws.connectionInfo.scope,lanOnly,lanAddress:ws.lanAddress});
      ws.watchRooms=true;
      broadcastRooms();
      return;
    }
    if (d.type === 'join') {
      if(ws.challenge||accountBusy(ws))return error(ws,'这个账号正在比赛，请先结束当前比赛。',d.type);
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
      broadcastRooms();
      return;
    }
    const room = rooms.get(ws.code);
    if (!room || !room.guest) return;
    const host = room.host === ws;
    const other = host ? room.guest : room.host;
    if(d.type==='relay'){
      if(!room.live)return;
      const packet=relay.controlPacket(d.packet,host,room.match);
      if(!packet)return;
      const move=packet.type==='input'&&packet.action==='move';
      if(move){if(packet.seq<=room.moveSeq)return;room.moveSeq=packet.seq;}
      return relay.forward(other,JSON.stringify({type:'relay',packet}),false,move?'move':'');
    }
    if(d.type==='relay_ready'){
      if(d.match!==room.match||room.live)return;
      room.ready.add(ws.profile.id);
      if(room.ready.size===2){room.live=true;for(const [role,client] of [['host',room.host],['guest',room.guest]])send(client,{type:'start',role,code:ws.code,goal:11,match:room.match});}
      return;
    }
    if(d.type==='relay_failed'){
      if(d.match!==room.match)return;
      const code=ws.code;
      // Startup cancellation is not a loss. Live departures use leave().
      if(room.live)return;
      for(const client of [room.host,room.guest]){relay.clearPending(client);client.code=null;send(client,{type:'peer_unavailable'});}
      rooms.delete(code);broadcastRooms();return;
    }
    if(d.type==='finish'){
      if(!room.live||d.match!==room.match||!validScore(d.score))return error(ws,'结算结果不符合当前对局。');
      if(room.settled)return send(ws,{type:'recorded',match:room.match});
      if(host){if(room.finalScore&&JSON.stringify(room.finalScore)!==JSON.stringify(d.score))return error(ws,'比赛结果不能更改。');room.finalScore=[...d.score];}
      room.confirmations.set(ws.profile.id,JSON.stringify(d.score));
      if(room.confirmations.size===2){
        if(new Set(room.confirmations.values()).size!==1)return error(ws,'双方结果不一致，请等待结果同步。');
        try{records.finish(room.match,room.host.profile.id,room.guest.profile.id,d.score);room.settled=true;broadcastScores();
          send(room.host,{type:'recorded',match:room.match});send(room.guest,{type:'recorded',match:room.match});
        }catch(e){console.error('Score persistence failed:',e.message);error(ws,'战绩保存失败，请保留房间稍后重试。');}
      }
      return;
    }
    if(d.type==='rematch'){
      if(!room.settled)return error(ws,'请等待双方完成结算后再开始下一局。');
      start(room,ws.code,'rematch');return;
    }
    // Unknown and legacy peer messages are not forwarded.
  });
  ws.on('close', () => leave(ws));
});
const heartbeat = setInterval(() => {
  for(const [ip,attempt] of authAttempts)if(Date.now()-attempt.since>60000)authAttempts.delete(ip);
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
  for (const [code, room] of rooms) {
    if(room.guest&&!room.live&&Date.now()-room.pairedAt>30000){
      for(const client of [room.host,room.guest]){client.code=null;send(client,{type:'peer_unavailable'});}
      rooms.delete(code);broadcastRooms();continue;
    }
    if (!room.guest && Date.now() - room.created > 30*60*1000) {
      room.host.code = null;
      error(room.host, '等待超过 30 分钟，房间已关闭，请重新创建。');
      rooms.delete(code);
      send(room.host,{type:'left'});
      broadcastRooms();
    }
  }
}, 15000);
server.listen(port, '0.0.0.0', () => {
  console.log(`Badminton Ace: http://localhost:${port}`);
  console.log(serveWeb ? `Web root: ${root}` : 'Backend only: game resources are not served.');
  console.log(`GM 管理（仅本机）: http://127.0.0.1:${port}/gm`);
  console.log('双击 GM管理.cmd 自动验证；或使用数据目录的 gm-key.txt。');
  console.log('谁是羽毛球高手 · 房间与战绩服务器（关闭窗口即停止服务）');
  console.log(`排行榜数据: ${path.join(process.env.DATA_DIR || path.join(home,'data'),'rankings.sqlite')}`);
  console.log(`Access: ${lanOnly ? 'LAN only (direct private-address clients)' : 'All reachable clients (no source subnet restriction)'}`);
  for (const entries of Object.values(require('node:os').networkInterfaces()))
    for (const a of entries || []) if (a.family === 'IPv4' && !a.internal) console.log(`LAN connection: ws://${a.address}:${port}/ws (open the extracted index.html locally)`);
});
server.on('error',e=>{console.error('服务器启动失败：',e.message);clearInterval(heartbeat);records.close();process.exitCode=1;});
function shutdown() { shuttingDown=true;clearInterval(heartbeat); for (const ws of wss.clients) ws.close(1001,'Server shutdown'); wss.close(); server.close(()=>records.close()); }
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
