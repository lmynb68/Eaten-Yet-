const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),{spawn}=require('node:child_process'),os=require('node:os');
const root=path.resolve(__dirname,'../site');
const report={scope:'Desktop Chrome mobile viewport and network emulation; not physical-phone validation',checks:[]};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
const server=http.createServer((req,res)=>{const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]==='/'?'/index.html':req.url.split('?')[0]));if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}fs.readFile(file,(e,b)=>{if(e){res.writeHead(404).end();return;}res.setHeader('Content-Type',({'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp'})[path.extname(file)]||'application/octet-stream');res.end(b);});});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=`http://127.0.0.1:${server.address().port}/`;
const profile=fs.mkdtempSync(path.join(os.tmpdir(),'eatenyet-qa-'));
const chrome=spawn(process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',['--headless=new','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
let ws;
try{
 const portFile=path.join(profile,'DevToolsActivePort');for(let i=0;i<100&&!fs.existsSync(portFile);i++)await sleep(100);
 const port=fs.readFileSync(portFile,'utf8').split('\n')[0];
 const tabs=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
 ws=new WebSocket(tabs.find(x=>x.type==='page').webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});
 let seq=0;const pending=new Map();ws.onmessage=e=>{const d=JSON.parse(e.data);if(pending.has(d.id)){const p=pending.get(d.id);pending.delete(d.id);d.error?p.j(Error(JSON.stringify(d.error))):p.r(d.result);}};
 const call=(method,params={})=>new Promise((r,j)=>{const id=++seq;pending.set(id,{r,j});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 const check=(name,ok)=>{report.checks.push({name,pass:!!ok});if(!ok)throw Error(name);};
 await call('Page.enable');await call('Network.enable');
 for(const width of [320,360,390,768]){
  await call('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:true});await call('Page.navigate',{url});
  for(let i=0;i<100;i++){if(await evaluate("document.readyState==='complete'"))break;await sleep(100);}
  check(`no horizontal overflow at ${width}`,await evaluate('document.documentElement.scrollWidth<=innerWidth+1'));
 }
 await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 check('menu opens',await evaluate("document.querySelector('[data-menu-toggle]').click();document.querySelector('[data-menu-toggle]').getAttribute('aria-expanded')==='true'"));
 check('menu link closes menu',await evaluate("document.querySelector('[data-nav] a').click();document.querySelector('[data-menu-toggle]').getAttribute('aria-expanded')==='false'"));
 await evaluate("Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.copied=text}}});document.querySelector('[data-copy-release]').click()");await sleep(100);
 check('clipboard success handler and exact URL',await evaluate("window.copied==='https://github.com/lmynb68/Eaten-Yet-/releases/tag/v1.0.0' && document.querySelector('[data-copy-status]').textContent.includes('已复制')"));
 await evaluate("Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw Error('denied')}}});document.querySelector('[data-copy-release]').click()");await sleep(100);
 check('clipboard denied fallback',await evaluate("document.querySelector('[data-copy-status]').textContent.includes('手动复制')"));
 check('gallery switches to stores',await evaluate("document.querySelectorAll('[role=tab]')[1].click();document.querySelector('[data-gallery-image]').getAttribute('src')==='assets/android-stores.jpg'"));
 check('gallery keyboard End selects last',await evaluate("document.querySelectorAll('[role=tab]')[1].dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true}));document.querySelectorAll('[role=tab]')[4].getAttribute('aria-selected')==='true'"));
 await call('Network.setCacheDisabled' ,{cacheDisabled:true});await call('Network.emulateNetworkConditions',{offline:false,latency:400,downloadThroughput:50000,uploadThroughput:25000});
 const started=Date.now();await call('Page.navigate',{url});let ready=false;
 for(let i=0;i<450;i++){ready=await evaluate("document.readyState==='complete' && !!document.querySelector('[data-copy-release]')");if(ready)break;await sleep(100);}
 check('weak-network page ready within 45s',ready);report.weakNetworkReadyMs=Date.now()-started;
 check('weak-network menu interaction',await evaluate("document.querySelector('[data-menu-toggle]').click();document.querySelector('[data-menu-toggle]').getAttribute('aria-expanded')==='true'"));
 report.clipboardScope='Handlers tested with injected success/denial; actual OS clipboard and phone permissions remain unverified';
 report.pass=true;
}finally{if(ws)ws.close();chrome.kill();server.close();fs.writeFileSync(process.env.QA_REPORT||'browser-qa-result.json',JSON.stringify(report,null,2));}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
