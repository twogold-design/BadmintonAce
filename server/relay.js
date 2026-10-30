'use strict';
// The room host simulates the match; the server validates routing and forwards
// only to that room's opponent. It never accepts client-selected recipients.
const { WebSocket } = require('ws');
const finite = n => typeof n === 'number' && Number.isFinite(n) && Math.abs(n) <= 1e6;
const vector = (v, n) => Array.isArray(v) && v.length === n && v.every(finite);
const sequence = n => Number.isSafeInteger(n) && n >= 0 && n <= 0xffffffff;

function snapshotInfo(raw) {
  if (!Buffer.isBuffer(raw) || raw.length < 116 || raw.length > 1200 || raw[0] !== 186 || ![1,2,3].includes(raw[1]) || raw.readUInt32LE(2) !== 36) return null;
  const match = raw.toString('utf8', 6, 42);
  if (!/^[0-9a-f-]{36}$/.test(match) || raw[78] > 3 || raw[79] > 15 || raw[80] > 15 || !Number.isFinite(raw.readDoubleLE(46))) return null;
  for (let offset = 54; offset < 78; offset += 4) if (!finite(raw.readFloatLE(offset))) return null;
  const reason = raw.readUInt32LE(112);
  if (reason > 128) return null;
  const poses = raw[1] === 1 ? 17 : 19, compact = raw[1] >= 3;
  const playerBytes = 84 + poses * (compact ? 2 : 4);
  let cursor = 116 + reason;
  for (let i = 0; i < 2; i++) {
    if (cursor + playerBytes > raw.length) return null;
    for (let offset = 0; offset < 60; offset += 4) if (!finite(raw.readFloatLE(cursor + offset))) return null;
    if (raw[cursor+60]>3 || raw.readInt8(cursor+61)<-1 || raw.readInt8(cursor+61)>3 || raw[cursor+64]>1 || raw[cursor+65]>4 || raw[cursor+66]>10) return null;
    for (let offset = 67; offset < 83; offset += 4) if (!finite(raw.readFloatLE(cursor + offset))) return null;
    if (!compact) for (let offset = 83; offset < playerBytes-1; offset += 4) if (!finite(raw.readFloatLE(cursor + offset))) return null;
    const contact = raw[cursor + playerBytes - 1];
    if (contact > 1) return null;
    cursor += playerBytes;
    if (contact) {
      if (cursor + 12 > raw.length) return null;
      for (let offset = 0; offset < 12; offset += 4) if (!finite(raw.readFloatLE(cursor + offset))) return null;
      cursor += 12;
    }
  }
  return cursor === raw.length ? { match, seq: raw.readUInt32LE(42), terminal: raw[78] === 3 } : null;
}

function controlPacket(packet, host, match) {
  if (!packet || typeof packet !== 'object' || Array.isArray(packet) || packet.match !== match) return null;
  const out = { type: packet.type, match };
  switch (packet.type) {
    case 'input':
      if (host) return null;
      out.action = packet.action;
      if (packet.action === 'move' && sequence(packet.seq) && finite(packet.x) && finite(packet.y)) {
        return {...out,seq:packet.seq,x:Math.max(-1,Math.min(1,packet.x)),y:Math.max(-1,Math.min(1,packet.y))};
      }
      if (packet.action === 'shot' && Number.isInteger(packet.shot) && packet.shot >= 0 && packet.shot <= 3 && typeof packet.pressed === 'boolean') return {...out,shot:packet.shot,pressed:packet.pressed};
      return ['jump','dash'].includes(packet.action) ? out : null;
    case 'pause': return typeof packet.value === 'boolean' ? {...out,value:packet.value} : null;
    case 'appearance': return ['male','female'].includes(packet.avatar) ? {...out,avatar:packet.avatar} : null;
    case 'prepare': return host && finite(packet.remaining) && packet.remaining >= 0 && packet.remaining <= 10 ? {...out,remaining:packet.remaining} : null;
    case 'ping': case 'pong': return Number.isSafeInteger(packet.stamp) && packet.stamp >= 0 ? {...out,stamp:packet.stamp} : null;
    case 'effect':
      if (!host || !vector(packet.pos,2) || !vector(packet.world,3) || !finite(packet.offset_y) || typeof packet.label !== 'string' || packet.label.length > 80 || typeof packet.color !== 'string' || !/^[0-9a-f]{6}([0-9a-f]{2})?$/i.test(packet.color)) return null;
      return {...out,pos:packet.pos,world:packet.world,offset_y:packet.offset_y,label:packet.label,color:packet.color};
    default: return null;
  }
}

function clearPending(ws) {
  if (!ws) return;
  clearTimeout(ws.relayTimer);
  ws.relayTimer = null;
  ws.relayPending = null;
}
function flush(ws) {
  ws.relayTimer = null;
  if (ws.readyState !== WebSocket.OPEN) return clearPending(ws);
  if (ws.bufferedAmount <= 4096) {
    for (const [key, frame] of ws.relayPending || []) {
      ws.relayPending.delete(key);
      ws.send(frame.raw,{binary:frame.binary});
    }
  }
  if (ws.relayPending?.size) ws.relayTimer = setTimeout(() => flush(ws), 16);
}
function forward(ws, raw, binary, replaceKey = '') {
  if (ws.readyState !== WebSocket.OPEN) return false;
  if (ws.bufferedAmount > 262144) { clearPending(ws); ws.close(1013,'Connection congested'); return false; }
  // Replace stale snapshots/movement with the latest one while the receiver is slow.
  if (replaceKey) {
    ws.relayPending?.delete(replaceKey);
    if (ws.bufferedAmount > 4096) {
      ws.relayPending ||= new Map();
      ws.relayPending.set(replaceKey,{raw,binary});
      if (!ws.relayTimer) ws.relayTimer = setTimeout(() => flush(ws),16);
      return true;
    }
  } else if (binary) ws.relayPending?.delete('state'); // Terminal state supersedes a queued flight.
  ws.send(raw,{binary});
  return true;
}
module.exports = { snapshotInfo, controlPacket, clearPending, forward };
