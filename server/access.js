'use strict';
const {isIP}=require('node:net');
function privateAddress(value) {
  let address=String(value||'').toLowerCase().replace(/^\[|\]$/g,'').split('%')[0];
  if(address.startsWith('::ffff:'))address=address.slice(7);
  if(isIP(address)===4){
    const [a,b]=address.split('.').map(Number);
    return a===127||a===10||(a===172&&b>=16&&b<=31)||(a===192&&b===168)||(a===169&&b===254);
  }
  return isIP(address)===6&&(address==='::1'||/^(fc|fd)/.test(address)||/^fe[89ab]/.test(address));
}
function allowRequest(req,lanOnly=false){
  if(!lanOnly)return true;
  if(!privateAddress(req.socket.remoteAddress))return false;
  // LAN mode accepts direct clients only; do not trust public proxy headers.
  if(['forwarded','x-forwarded-for','x-real-ip','cf-connecting-ip','x-forwarded-host','x-forwarded-proto'].some(k=>req.headers[k]!==undefined))return false;
  try{
    const host=new URL('http://'+req.headers.host).hostname;
    return host==='localhost'||privateAddress(host);
  }catch{return false;}
}
module.exports={privateAddress,allowRequest};
