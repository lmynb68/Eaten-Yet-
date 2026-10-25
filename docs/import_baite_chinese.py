"""Import 百特快客 traditional Chinese counter, four source photographs."""
import json
from pathlib import Path
from decimal import Decimal
r=Path(__file__).resolve().parents[1]
p=r/'assets/official.json'
db=json.loads(p.read_text(encoding='utf-8'))
db['places']=[x for x in db['places'] if x['id']!='btz']
db['offers']=[x for x in db['offers'] if x['placeId']!='btz']
for place in db['places']:
 if place['id']=='btk':place['name']='百特快客（美味西餐）'
db['places'].append(dict(id='btz',name='百特快客（传统中餐）',area='用户提供独立中餐门头，具体位置待补充',photo=''))
rows=[]
def add(text,photo,kind='side',portion='一个',staple='other',available=True,note=''):
 for x in text.split('|'):
  n,v=x.rsplit('=',1)
  rows.append(dict(id=f'btz_{len(rows)+1:03}',placeId='btz',name=n,portion=portion,priceCents=int(Decimal(v)*100),roles=['staple'] if kind=='main' else [],foodIds=[],available=available,ingredientsKnown=False,example=False,kind=kind,window='',channel='regular',notes=note,evidence=f'百特快客传统中餐用户照片{photo}，2026-10-21',observedAt='2026-10-21',updatedAt='2026-10-21',photo='',staple=staple,addonOnly=False,alcohol=False))
add('开花馒头=0.6|豆包=1.2|木耳鸡蛋萝卜包=1.5|糖包=1.5|花卷=0.6|三鲜包=1|黄馒头=1|豆腐包=1|黑馒头=1|双色馒头=1.5|茴香包=1.5|发糕=2|香菇肉包=2.5|酸菜粉条包=1.5|酱肉包=2.5|烧肉土豆包=3|麻辣鸡汁包=3|香辣牛肉包=4|回锅肉包=3|红糖红枣馒头=1.5|水晶蒸饺=1|玉米火腿包=2|鱼香肉丝包=3|豆角烧肉包=3',2,note='包点按单件录入；原价目表除油条外未逐项印单位。土豆烧肉包与烧肉土豆包按同款合并。')
add('老豆腐=2',2,portion='一份',staple='none')
add('黑米粥=2.5|小米粥=2',2,'drink','一份','none')
add('茶叶蛋=1.5',2,staple='none')
add('油条=1.5',2,portion='一对');add('油条=0.8',2,portion='一根')
add('鸡爪=46|鸡胗=20|猪耳朵=50',3,portion='每斤',staple='none',available=False,note='按斤称重结算，非整份价格；暂不参与随机，不代表停售。')
add('鸭脖=3.5|鸭腿=7|鸡块=6|鸭翅=2.5|猪手=36',3,staple='none',note='熟食按菜单每个计价。')
add('桂花糕=3|麻辣龙虾尾包=3|紫薯芝士包=2|奥尔良鸡肉芝士包=3.5',4)
add('狗不理小笼包=9',4,'main','一笼','other',note='照片未注明每笼个数，不换算单个价格。')
add('馄饨丸子汤=6',4,'main','一份','dumplings')
db['offers'].extend(rows)
p.write_text(json.dumps(db,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
lines=['# 百特快客（传统中餐）核对','',f'新增{len(rows)}个售卖规格。照片1门头、2价目表、3熟食、4补充包点。','', '按独立门头区分中西餐；旧西餐ID btk不变，中餐ID btz。两店是否统一管理未作判断。','', '- 油条：一根0.8元、一对1.5元；小笼包一笼9元，不推算数量。','- 鸡爪46元/斤、鸡胗20元/斤、猪耳朵50元/斤不参与整份随机。','- 土豆烧肉包与烧肉土豆包3元按同款合并；玉米火腿包、鱼香肉丝包、豆角烧肉包重复牌只计一次。','- 包点按单件录入；价目表没有逐项印单位，此处为按品类理解。粥与老豆腐份量未注明。','- 展示牛奶无清晰售价，不录入。','', '## 已关闭事项（2026-10-22）','- 用户要求包点单位、份量、小笼包数量及展示奶售价不再追查；保留现有录入，不补猜数量或价格。','', '## 重建','在食悦、文瀛、西餐导入之后运行 import_baite_chinese.py；按店铺ID替换，保留其他店铺。','', '|名称|规格|元|备注|','|---|---|---:|---|']
lines += [f'|{o["name"]}|{o["portion"]}|{o["priceCents"]/100:g}|{o["notes"]}|' for o in rows]
(r/'docs/baite-chinese-menu-audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(len(rows),len(db['offers']),len(db['places']))
