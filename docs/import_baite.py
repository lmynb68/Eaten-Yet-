"""Import the three 百特快客 photographs without changing other restaurants."""
import json
from pathlib import Path
from decimal import Decimal
r=Path(__file__).resolve().parents[1]
p=r/'assets/official.json'
db=json.loads(p.read_text(encoding='utf-8'))
db['places']=[x for x in db['places'] if x['id']!='btk']
db['offers']=[x for x in db['offers'] if x['placeId']!='btk']
db['places'].append(dict(id='btk',name='百特快客（美味西餐）',area='用户提供门头照片，具体位置待补充',photo=''))
rows=[]
def add(text,photo,kind='main',portion='一份',staple='other',note='',available=True):
 for x in text.split('|'):
  n,v=x.rsplit('=',1)
  rows.append(dict(id=f'btk_{len(rows)+1:03}',placeId='btk',name=n,portion=portion,priceCents=int(Decimal(v)*100),roles=['staple'] if kind=='main' else [],foodIds=[],available=available,ingredientsKnown=False,example=False,kind=kind,window='',channel='regular',notes=note,evidence=f'百特快客用户照片{photo}，2026-10-21',observedAt='2026-10-21',updatedAt='2026-10-21',photo='',staple=staple,addonOnly=False,alcohol=False))
add('新奥尔良鸡腿堡=7.5|香辣鸡腿堡=7.5|全虾堡=10.5|劲脆堡=7.5|牛肉堡=7|麦香鸡肉卷=7.5|鳕鱼堡=9.5|双层蛋堡=6',3)
add('鸡扒饭=10|沙拉炸鸡饭=10',3,staple='rice')
add('脆皮鸡腿=6.5|香辣鸡翅=7|奥尔良风味烤翅=7|黑椒鸡块=6|鸡米花=6.5|薯条=6|金丝鸡柳=3|红豆派=5|黄金大鸡排=10.5',3,'side',staple='none')
add('可乐=6|七喜=6|美年达=6',2,'drink','大杯','none')
add('橙汁=5|芒果汁=5|蓝莓汁=5',2,'drink','中杯','none')
add('牛奶（热）=5.5|咖啡（热）=5.5|奶茶（热）=5.5|美禄（热）=5.5',2,'drink','一杯','none')
add('橙C（热，上方菜单）=5.5',2,'drink','一杯','none',note='下方热饮牌标4元，价格冲突待确认，暂不参与随机。',available=False)
add('冰激凌=3|草莓圣代=5.5|朱古力圣代=5.5',2,'side',staple='none')
add('早餐汉堡＋牛奶=5.8',3,note='限早7:00—8:30；汉堡品种未明确。当前无营业时段筛选，暂不参与随机，不代表停售。',available=False)
add('超值双人餐=38.9',2,portion='双人份',note='劲脆鸡腿堡、麦香鸡肉卷、薯条、劲爆鸡米花、黑椒鸡块及可乐2杯；双人餐不纳入单人随机。',available=False)
add('劲脆鸡腿堡＋薯条＋可乐=14.5|全虾堡＋薯条＋可乐=17.9|麦香鸡肉卷＋黑椒鸡块＋可乐=14.9',2,note='套餐按组合总价，不拆成单品折扣价。')
add('双层蛋堡＋热牛奶=11|双堡＋可乐=10|双汉堡＋可乐套餐=16.9',3,note='海报套餐；10元和16.9元海报中的汉堡品种小字未完全辨清，分别保留套餐价格，内容现场确认。')
add('黑椒鸡块＋薯条=10|鸡米花＋可乐=10.9|圣代＋薯条=9.9',3,'side',staple='none',note='小吃组合，不当作主餐。')
add('热巧克力=5.5',3,'drink','一杯','none',note='下方热饮牌。')
add('橙C（热，下方菜单）=4',3,'drink','一杯','none',note='上方菜单标5.5元，价格冲突待确认，暂不参与随机。',available=False)
# Withdraw two unverified poster combinations, preserving all other IDs.
rows=[o for o in rows if o['name'] not in {'双堡＋可乐','双汉堡＋可乐套餐'}]
for o in rows:
 if '橙C' in o['name']:o['notes']='两张菜单价格不同，用户要求不再追查；保留原标价并不参与随机。'
 if o['name']=='双层蛋堡＋热牛奶':o['notes']='海报标价11元。'
db['offers'].extend(rows)
p.write_text(json.dumps(db,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
lines=['# 百特快客菜单核对','',f'新增{len(rows)}项；照片1门头，照片2冷饮/热饮/甜品及套餐，照片3主餐/配餐及套餐。','', '## 处理结果（2026-10-22）','- 早餐5.8元限7:00—8:30；双人餐38.9元供两人，均不参与普通单人随机。','- 热橙C上牌5.5元、下牌4元，用户要求不再追查；两条保留来源但均暂停随机。','- 此前把10元套餐误写为双堡，海报为汉堡＋可乐；具体品种不清，连同16.9元不确定套餐撤下，不再要求用户确认。','- 下方补充小吃牌、左下粉色纸及门外黑板文字/单位不够清晰，按用户要求关闭，不猜填。','- 具体地址尚未提供，不推定为文瀛餐厅内窗口。','', '## 重建','在食悦、文瀛更新后最后运行 import_baite.py。按店铺ID替换本店，保留其他店铺；重复运行结果一致。','', '|名称|规格|元|说明|','|---|---|---:|---|']
lines += [f'|{o["name"]}|{o["portion"]}|{o["priceCents"]/100:g}|{o["notes"]}|' for o in rows]
(r/'docs/baite-menu-audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(f'{len(rows)} new, {len(db["offers"])} offers, {len(db["places"])} stores')
