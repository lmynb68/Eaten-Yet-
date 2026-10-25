import json
from decimal import Decimal
from pathlib import Path
r=Path(__file__).resolve().parents[1];p=r/'assets/official.json'
db=json.loads(p.read_text(encoding='utf-8'))
bak=r/'assets/official-v7.json'
if not bak.exists():bak.write_bytes(p.read_bytes())
db['places']=[x for x in db['places'] if x['id']!='zxb'];db['offers']=[x for x in db['offers'] if x['placeId']!='zxb']
db['places'].append(dict(id='zxb',name='钟小北蛋糕店',area='食味坊内',photo=''))
rows=[]
def add(ph,text,portion='一个',available=True,note=''):
 for x in text.split('|'):
  n,v=x.rsplit('=',1)
  rows.append(dict(id=f'zxb_{len(rows)+1:03}',placeId='zxb',name=n,portion=portion,priceCents=int(Decimal(v)*100),roles=[],foodIds=[],available=available,ingredientsKnown=False,example=False,kind='side',window='',channel='regular',notes=note,evidence=f'钟小北用户照片{ph}，2026-10-23',observedAt='2026-10-23',updatedAt='2026-10-23',photo='',staple='other',addonOnly=False,alcohol=False,mealPeriods=['lunch','dinner']))
add(1,'维多利亚=9.9|乳酪面包=6.9')
add(2,'蓝莓乳酪包=8.8')
add(3,'蓝莓巴蒂=4.9|法式奶油棒=6.8')
add(4,'肉松卷=8.8');add(5,'焗烤三明治=8.8');add(6,'猪扒包=8.8');add(7,'培根披萨=7.9');add(8,'奶香蔓越莓=6.9');add(9,'小鸡腿=4',note='面包商品名，不作为鸡肉菜录入。');add(10,'牛角=3.8')
add(11,'肉松小贝=5|酸奶小贝=5');add(12,'黄金蛋糕=5|乳酪蛋糕=9.9');add(13,'宫廷桃酥=3|枣糕=4.5')
add(14,'奥利奥魔法棒=8.8',note='名称价格取自用户在照片上的补充标注。')
add(15,'肉松小贝=14.8','一盒',note='与单个5元分开保留；不推算盒内数量。')
add(17,'黑森林=9.9|瑞士卷=6.5|大泡芙=6')
add(18,'半熟芝士（奥巧）=15.9|半熟芝士（原味）=13.9|柏林爆蛋糕=14.8','一盒')
add(18,'欧培拉=19.9|梦龙卷=12.8')
add(19,'蓝莓慕斯蛋糕=11.8','一盒')
add(20,'酸奶蜜包=4',note='按照片补充文字原名录入；标注未写单位，暂按一个。')
add(21,'黑核奶昔=8.8',note='按照片补充文字原名；实物为烘焙点心，不归饮料。')
add(22,'鲜奶包=8.8',note='名称价格来自照片补充文字。');add(23,'迪拜巧克力脆=9.9',note='名称价格来自照片补充文字。');add(24,'蛋挞=3',note='价格来自照片补充文字。')
add(25,'莲蓉蛋黄酥=6');add(25,'莲蓉蛋黄酥=10','2个');add(26,'空心月饼=2',note='价格来自照片补充文字。')
for size,price in [(6,118),(8,138),(10,168),(12,198)]:add(27,f'动物奶油新鲜水果夹层生日蛋糕={price}',f'{size}寸',False,'预订整蛋糕；不参与单人随机，不代表停售。')
# 用户确认补充
add(17,'樱桃抹茶卷=14.8',note='用户确认名称及价格。')
add(19,'榴莲千层=16.8',note='用户确认价格。')
for row in rows:
 if row['notes'].startswith(('用户确认','手写加菜')):
  row['updatedAt']='2026-10-24'
  row['evidence']+='；用户后续核对'

db['offers'].extend(rows);db['revision']=max(db['revision'],9)
p.write_text(json.dumps(db,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
lines=['# 钟小北蛋糕店（食味坊内）','',f'已录入{len(rows)}个规格。独立店铺zxb；甜点面包均归小食，不作为完整正餐。餐次暂沿用食味坊中晚规则，早餐需用户确认。','', '## 用户核对结果及剩余不确定项','- 照片6、15、16未标价商品：用户要求忽略。','- 樱桃抹茶卷14.8元；榴莲千层16.8元。','- 泡芙12.8元单位仍不清，暂不录入。','', '|名称|规格|元|证据|备注|','|---|---|---:|---|---|']
lines += [f'|{o["name"]}|{o["portion"]}|{o["priceCents"]/100:g}|{o["evidence"]}|{o["notes"]}|' for o in rows]
(r/'docs/zhongxiaobei-menu-audit.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(len(rows),len(db['offers']),len(db['places']))
