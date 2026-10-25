const toggle=document.querySelector('#toggle');const nav=document.querySelector('#nav');toggle.addEventListener('click',()=>{const open=nav.classList.toggle('open');toggle.setAttribute('aria-expanded',String(open));});nav.addEventListener('click',e=>{if(e.target.closest('a')){nav.classList.remove('open');toggle.setAttribute('aria-expanded','false');}});

const wechatHint=document.querySelector('#wechat-hint');
wechatHint.hidden=!/MicroMessenger/i.test(navigator.userAgent);
document.querySelector('#copy-download').addEventListener('click',async()=>{
 const url='https://github.com/lmynb68/Eaten-Yet-/releases';
 const status=document.querySelector('#copy-status');
 if(location.protocol==='file:'){status.textContent='这是本地预览。网站上线后，可复制公开下载链接。';return;}
 try{await navigator.clipboard.writeText(url);status.textContent='下载链接已复制，请粘贴到手机浏览器打开。';}
 catch{status.textContent='请长按复制下载链接：'+url;}
});
