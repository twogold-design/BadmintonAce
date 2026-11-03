'use strict';
// Negotiated by standard WebSocket clients; unsupported clients stay uncompressed.
// Small per-connection dictionaries exploit repeated snapshot fields without
// changing a single coordinate, pose, score or packet sequence.
function compressionOptions(enabled=true){
 if(!enabled)return false;
 return {
  zlibDeflateOptions:{level:1,memLevel:4},
  serverMaxWindowBits:12,
  clientMaxWindowBits:12,
  concurrencyLimit:4,
  threshold:128
 };
}
module.exports={compressionOptions};
