const assert=require('node:assert/strict');
const {allowRequest,privateAddress}=require('./access');
for(const address of ['127.0.0.1','192.168.1.8','10.1.2.3','172.16.0.1','::1','::ffff:192.168.1.8','fd12::1'])assert.ok(privateAddress(address),address);
for(const address of ['8.8.8.8','172.32.1.1','0.0.0.0','example.com','2001:4860:4860::8888'])assert.ok(!privateAddress(address),address);
const req={socket:{remoteAddress:'192.168.1.9'},headers:{host:'192.168.1.8:8766'}};
for(const candidate of [req,
 {...req,socket:{remoteAddress:'10.99.3.8'}},
 {...req,socket:{remoteAddress:'8.8.8.8'}},
 {...req,socket:{remoteAddress:'2001:db8::2'}},
 {...req,headers:{...req.headers,'x-forwarded-for':'192.168.1.9'}},
 {...req,headers:{host:'games.company.example'}}]) {
 assert.ok(allowRequest(candidate),'Default accepts reachable clients regardless of subnet, host or forwarding headers');
 assert.ok(allowRequest(candidate,false));
}
assert.ok(allowRequest(req,true));
assert.ok(!allowRequest({...req,socket:{remoteAddress:'8.8.8.8'}},true));
assert.ok(!allowRequest({...req,headers:{...req.headers,'x-forwarded-for':'192.168.1.9'}},true));
assert.ok(!allowRequest({...req,headers:{host:'public.example.com'}},true));
console.log('PASS: all reachable clients by default; optional LAN-only mode still enforced.');
