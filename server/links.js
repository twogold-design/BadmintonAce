'use strict';
const os = require('node:os');
function scopeOf(hostname) {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g,'');
  if (host === 'localhost' || host.endsWith('.localhost') || host === '::1' || host === '0.0.0.0' || /^127\./.test(host)) return 'local';
  if (/^(10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host) || (host.includes(':') && /^(fc|fd|fe80:)/.test(host)) || host.endsWith('.local')) return 'lan';
  return 'public';
}
function validOrigin(value) {
  try {
    const url = new URL(value);
    if (!['http:','https:'].includes(url.protocol) || url.username || url.password) return null;
    return url.origin;
  } catch { return null; }
}
function connectionInfo(req, port, configured = process.env.PUBLIC_URL, interfaces = os.networkInterfaces()) {
  const publicOrigin = validOrigin(configured);
  if (publicOrigin) return {scope:scopeOf(new URL(publicOrigin).hostname),base:publicOrigin,configured:true};
  const host = String(req.headers.host || '');
  const protocol = req.socket.encrypted || req.headers['x-forwarded-proto'] === 'https' ? 'https:' : 'http:';
  const origin = validOrigin(protocol+'//'+host);
  if (origin && scopeOf(new URL(origin).hostname) !== 'local') return {scope:scopeOf(new URL(origin).hostname),base:origin,configured:false};
  for (const entries of Object.values(interfaces)) for (const a of entries || [])
    if (a.family === 'IPv4' && !a.internal && scopeOf(a.address) === 'lan') return {scope:'lan',base:`http://${a.address}:${port}`,configured:false};
  return {scope:'local',base:`http://127.0.0.1:${port}`,configured:false};
}
function invitation(info, code) {
  // Godot requires a secure context. Do not offer a LAN HTTP address as a
  // playable invitation, or a loopback address as a link for another person.
  if (info.scope !== 'public' || new URL(info.base).protocol !== 'https:') return '';
  const url = new URL('/index.html',info.base);
  url.searchParams.set('room',code);
  return url.href;
}
module.exports = {scopeOf, validOrigin, connectionInfo, invitation};
