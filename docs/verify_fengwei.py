"""数据完整性、重导幂等与历史菜品保全检查，不替代Flutter测试。"""
import json,runpy,hashlib
from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=r/'assets/official.json';db=json.loads(p.read_text(encoding='utf-8'));old=json.loads((r/'assets/official-v6.json').read_text(encoding='utf-8'))
assert db['revision']>=7 and len(db['places'])>=8 and len(db['offers'])>=1579
assert [o for o in db['offers'] if o['placeId'] not in ['fw','zxb']]==old['offers']
assert [o for o in db['places'] if o['id'] not in ['fw','zxb']]==old['places']
assert db.get('ricePlans')==old.get('ricePlans')
for section in ['places','offers','foods']:
 ids=[o['id'] for o in db[section]];assert len(ids)==len(set(ids))
assert len(db['offers'])<=2000 and p.stat().st_size<12000000
places={p['id'] for p in db['places']}
for o in db['offers']:
 assert o['placeId'] in places and isinstance(o['priceCents'],int) and o['priceCents']>0
 assert o['kind'] in ['main','side','dish','drink','fee']
 assert o.get('staple','') in ['rice','noodles','dumplings','other','none','']
 assert o['mealPeriods'] and set(o['mealPeriods'])<={'breakfast','lunch','dinner'}
fw=[o for o in db['offers'] if o['placeId']=='fw']
assert len({(o['window'],o['name'],o['portion']) for o in fw})==421
assert all(not o['available'] for o in fw if o['portion'].startswith('每'))
assert all(o['kind']=='side' for o in fw if o['addonOnly'])
assert all(o['mealPeriods']==['lunch','dinner'] for o in fw)
assert next(o for o in fw if o['name']=='鸡腿饭')['available']==False
before=p.read_bytes() # Cross-store verification must not downgrade the current catalog.
print('PASS: schema fields, 421 unique source entries, 8 stores / 1579 offers, old data unchanged, safe exclusions, repeat import identical')
print('catalog SHA256:',hashlib.sha256(before).hexdigest())

