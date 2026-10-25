const toggle=document.querySelector('#toggle');const nav=document.querySelector('#nav');toggle.addEventListener('click',()=>{const open=nav.classList.toggle('open');toggle.setAttribute('aria-expanded',String(open));});nav.addEventListener('click',e=>{if(e.target.closest('a')){nav.classList.remove('open');toggle.setAttribute('aria-expanded','false');}});

document.querySelector('#copy-download').addEventListener('click',async()=>{
 const url='https://github.com/lmynb68/Eaten-Yet-/releases/tag/v1.0.0';
 const status=document.querySelector('#copy-status');
 if(location.protocol==='file:'){status.textContent='这是本地预览。网站上线后，可复制公开下载链接。';return;}
 try{await navigator.clipboard.writeText(url);status.textContent='发布页链接已复制。';}
 catch{status.textContent='请长按复制下载链接：'+url;}
});
