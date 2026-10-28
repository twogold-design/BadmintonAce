const crypto=require('node:crypto');
const testAccounts=new WeakMap();
async function fill(page,x,y,text){await page.mouse.click(x,y);await page.keyboard.press('Control+A');await page.keyboard.type(text,{delay:15});}
async function enterAccount(page,prefix='测试'){
 await page.waitForFunction(()=>['login','menu'].includes(window.badmintonState?.screen),null,{timeout:30000});
 if(await page.evaluate(()=>window.badmintonState.screen==='menu'))return;
 if(!testAccounts.has(page))testAccounts.set(page,'test'+crypto.randomBytes(5).toString('hex'));
 await fill(page,700,355,testAccounts.get(page));
 await fill(page,700,455,'browser-test-pass');await page.mouse.click(720,555);
 await page.waitForFunction(()=>window.badmintonState?.screen==='menu',null,{timeout:15000});
}
async function challenge(page,index=0){
 await page.mouse.click(200,585);await page.waitForFunction(()=>window.badmintonState?.screen==='challenges');
 await page.mouse.click(230+(index%4)*320,340+Math.floor(index/4)*235);
 await page.waitForFunction(()=>window.badmintonState?.screen==='game');
}
module.exports={enterAccount,challenge,fill};
