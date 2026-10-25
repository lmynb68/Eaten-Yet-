"""Validate static Pages assets, fragments, scripts and release metadata."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json, subprocess, sys, urllib.request
ROOT=Path(__file__).resolve().parents[1]
SITE=ROOT/'site'
class Page(HTMLParser):
    def __init__(self,text):
        super().__init__();self.ids=set();self.refs=[];self.feed(text)
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:
            assert a['id'] not in self.ids, 'Duplicate id: '+a['id']
            self.ids.add(a['id'])
        for k in ('href','src'):
            if a.get(k):self.refs.append(a[k])

def main():
    pages={p:Page(p.read_text(encoding='utf-8-sig')) for p in SITE.rglob('*.html')}
    for path,page in pages.items():
        for ref in page.refs:
            u=urlsplit(ref)
            if u.scheme or u.netloc:continue
            assert not u.path.startswith('/'),f'Project Pages requires relative URL: {ref}'
            target=(path.parent/unquote(u.path)).resolve() if u.path else path
            assert target.is_relative_to(SITE.resolve()),f'Path escapes site: {ref}'
            assert target.exists(),f'Missing asset: {path.name} -> {ref}'
            if u.fragment and target in pages:
                assert unquote(u.fragment) in pages[target].ids,f'Missing fragment: {ref}'
    for js in SITE.rglob('*.js'):subprocess.run(['node','--check',str(js)],check=True)
    release=json.loads((SITE/'release.json').read_text(encoding='utf-8'))
    if release['status']=='published':
        assert release['version'] and release['publishedAt'] and release['minAndroid']
        assert release['assets']
        for a in release['assets']:
            assert len(a['sha256'])==64 and all(c in '0123456789abcdef' for c in a['sha256'])
            assert a['bytes']>0 and a['abi']
            assert a['url'].startswith('https://github.com/lmynb68/Eaten-Yet-/releases/download/'+release['tag']+'/')
        if '--online' in sys.argv:
            req=urllib.request.Request('https://api.github.com/repos/lmynb68/Eaten-Yet-/releases/tags/'+release['tag'],headers={'Accept':'application/vnd.github+json','User-Agent':'EatenYet-site-check'})
            with urllib.request.urlopen(req,timeout=30) as response:actual=json.load(response)
            assert not actual['draft'] and not actual['prerelease']
            for a in release['assets']:
                found=next(x for x in actual['assets'] if x['browser_download_url']==a['url'])
                assert found['size']==a['bytes']
                assert found.get('digest')=='sha256:'+a['sha256'],'Published asset digest does not match'
    else:
        assert release['status']=='pending' and not release['assets']
        assert '正式版尚未发布' in (SITE/'index.html').read_text(encoding='utf-8')
    print(f'PASS: {len(pages)} HTML pages, local resources/fragments, JS syntax and release metadata')
if __name__=='__main__':main()
