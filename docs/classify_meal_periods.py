"""Apply reviewed meal-period categories after the restaurant import scripts."""
import json
from pathlib import Path
r=Path(__file__).resolve().parents[1];p=r/'assets/official.json';db=json.loads(p.read_text(encoding='utf-8'))
all_meals=['breakfast','lunch','dinner'];later=['lunch','dinner'];breakfast=['breakfast']
report=['# 餐次分类依据','', '用户规则：食味坊、金面郎、社区、食悦仅中晚；文瀛、百特中西餐支持早中晚。','分类用于推荐，不代表已核实营业时间。文瀛明确早餐招牌按早餐分类，包点及粥汤按早餐/跨餐品类人工复核；未见明确早餐依据的饭面炒菜按中晚。','百特普通菜单按用户早中晚规则处理，仅明确早餐套餐限制为早餐。个人菜品未标餐次默认全餐次。','', '|店铺|窗口|菜品|餐次|依据|','|---|---|---|---|---|']
for o in db['offers']:
 reason='用户指定其他餐厅仅中晚';periods=later
 if o['placeId'] in ['btk','btz']:
  periods=all_meals;reason='用户确认百特早中晚；普通单品未印餐次限制'
  if o['placeId']=='btk' and o['name'] in ['早餐汉堡＋牛奶','双层蛋堡＋热牛奶']:
   periods=breakfast;reason='早餐/活力早餐海报'
   # Keep the 7:00–8:30 offer excluded: generic breakfast is broader than this promotion.
 elif o['placeId']=='wy':
  ev=o['evidence'];w=o['window'];n=o['name'];reason='饭面、单点菜或午晚餐招牌；无明确早餐依据'
  if w=='25号窗口' or (w in ['23号窗口','24号窗口'] and o['kind']=='side'):
   periods=breakfast;reason='包点、馒头、油条及早餐豆浆/老豆腐'
  elif w=='24号窗口' and o['kind']=='main':
   periods=all_meals;reason='馄饨、水饺，可跨餐次；未见限时'
  elif w=='21—22号窗口' or w=='17号窗口':
   periods=all_meals;reason='汤粥/饼类，照片摄于晚间，保留早中晚'
  elif '用户照片33，' in ev or '用户照片39，' in ev and o['staple']!='rice':
   periods=breakfast;reason='营养早餐/早餐系列招牌'
  elif '用户照片17，' in ev:
   if n in ['牛肉丸子汤','茴香小油条']:
    periods=breakfast;reason='台牌明确标为早点'
   elif w=='13号窗口':
    periods=all_meals;reason='粥汤油条台牌，晚间拍摄，按跨餐次分类'
  elif n in ['鸡蛋灌饼','杂粮煎饼'] or o['addonOnly'] and '用户照片30，' in ev:
   periods=all_meals;reason='饼类与同档加料，按跨餐次分类'
 o['mealPeriods']=list(periods)
 report.append('|'+ '|'.join([o['placeId'],o.get('window',''),o['name'],'/'.join(periods),reason])+'|')
p.write_text(json.dumps(db,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(r/'docs/meal-period-audit.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
print({k:sum(k in o['mealPeriods'] for o in db['offers']) for k in all_meals})
