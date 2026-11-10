import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:eat_what/favorites.dart';
import 'package:eat_what/history.dart';
import 'package:eat_what/rice.dart';
import 'package:eat_what/language.dart';
import 'save_failure_test.dart' show FailingPreferences;

FavoriteMeal meal({int quantity=2}) => FavoriteMeal(storeKey:'personal:s',storeName:'小店',kind:'整份餐品',savedAt:'2026-11-10T12:00:00',ricePrice:100,baseQuantity:2,items:[FavoriteItem('a','菜',500,quantity:quantity)]);
const plan=RicePlan(id:'p',name:'选菜',location:'窗口',priceCents:100,labels:['一','二','三'],options:[['A','B'],['C'],['D']],dishPrices:{'A':200,'B':300,'C':400,'D':500});
void main(){
  test('old favorites default to one and preserve identity; quantities change totals and identity',(){
    final json=meal().toJson()..remove('baseQuantity');
    for(final item in json['items']){item.remove('quantity');}
    final old=FavoriteMeal.fromJson(json);
    expect(old.baseQuantity,1);expect(old.items.single.quantity,1);expect(old.total,600);
    expect(old.id,jsonEncode(['personal:s','整份餐品',['a']]));
    expect(meal().total,1200);expect(meal().id,isNot(meal(quantity:3).id));
    expect(FavoriteMeal.fromJson(meal().toJson()).total,1200);
  });
  test('history survives reload, reviews edit without changing meal; import is idempotent',()async{
    final prefs=FailingPreferences();final store=await HistoryStore.load(prefs);
    final original=meal();await store.add(original,stars:4,review:'好吃');
    original.items.clear(); // Saved snapshots do not retain the input list.
    final loaded=await HistoryStore.load(prefs);final row=loaded.records.single;
    expect(row.meal.total,1200);expect(row.stars,4);expect(row.review,'好吃');
    await loaded.edit(row.id,5,'再来一次');
    await loaded.import(loaded.export());expect(loaded.records.length,1);
    final other=await HistoryStore.load(FailingPreferences());await other.import(loaded.export());
    expect(other.records.single.stars,5);expect(other.records.single.meal.total,1200);
    expect(prefs.disk.containsKey(FavoriteStore.storageKey),isFalse);
    await other.remove(row.id);expect(other.records,isEmpty);
  });
  for(final throws in [false,true]){
    test('history failed write ($throws) retains durable data and recovers queue',()async{
      final prefs=FailingPreferences()..throwOnFailure=throws;
      final store=await HistoryStore.load(prefs);await store.add(meal());
      final raw=prefs.disk[HistoryStore.storageKey];final id=store.records.single.id;
      prefs.failNext=true;await expectLater(store.edit(id,3,'失败'),throwsStateError);
      expect(prefs.disk[HistoryStore.storageKey],raw);expect(store.records.single.stars,0);
      await Future.wait([store.edit(id,4,'成功'),store.add(meal(quantity:3))]);
      expect((await HistoryStore.load(prefs)).records.length,2);
      expect(store.records.singleWhere((r)=>r.id==id).stars,4);
    });
  }
  test('corrupt history is isolated; each independent reset keeps its original',()async{
    final prefs=FailingPreferences();
    for(final raw in ['broken-A','broken-B']){
      prefs.disk[HistoryStore.storageKey]=raw;final store=await HistoryStore.load(prefs);
      expect(store.recoveryRequired,isTrue);expect(store.export(),raw);
      await expectLater(store.add(meal()),throwsStateError);
      prefs.failNext=true;await expectLater(store.resetAfterBackup(),throwsStateError);
      expect(prefs.disk[HistoryStore.storageKey],raw);
      await store.resetAfterBackup();expect(store.recoveryRequired,isFalse);
      expect(prefs.disk.values,contains(raw));
    }
    expect(prefs.disk.values,containsAll(['broken-A','broken-B']));
  });
  test('invalid history import and invalid review preserve previous records',()async{
    final prefs=FailingPreferences();final store=await HistoryStore.load(prefs);await store.add(meal());
    final raw=store.export();await expectLater(store.edit(store.records.single.id,6,''),throwsFormatException);
    await expectLater(store.import('{}'),throwsFormatException);
    final bad=jsonDecode(raw);bad['records'][0]['meal']['items'][0]['quantity']=0;
    await expectLater(store.import(jsonEncode(bad)),throwsFormatException);expect(store.export(),raw);
  });
  test('free rice random respects variable dish count, quantities, rice count and locks',(){
    for(var seed=0;seed<20;seed++){
      final one=randomRice(plan,800,[null],{},Random(seed),freeSelection:true,quantities:[2],baseQuantity:2);
      expect(one.dishes,hasLength(1));expect(plan.totalPrice(one.dishes!,quantities:[2],baseQuantity:2),lessThanOrEqualTo(800));
      final two=randomRice(plan,1500,['A',null],{0},Random(seed),freeSelection:true,quantities:[3,2],baseQuantity:2);
      expect(two.dishes,hasLength(2));expect(two.dishes![0],'A');
      expect(plan.totalPrice(two.dishes!,quantities:[3,2],baseQuantity:2),lessThanOrEqualTo(1500));
    }
    expect(randomRice(plan,599,[null],{},Random(1),freeSelection:true,quantities:[2],baseQuantity:2).dishes,isNull);
    expect(()=>plan.totalPrice(['A'],quantities:[0]),throwsArgumentError);
  });
  test('fixed rice price multiplies whole sets only',(){
    const fixed=RicePlan(id:'f',name:'套餐',location:'窗口',priceCents:900,labels:['一','二','三'],options:[['A'],['B'],['C']]);
    expect(fixed.totalPrice(['A','B','C'],baseQuantity:2),1800);
    expect(randomRice(fixed,1799,[null,null,null],{},Random(1),baseQuantity:2).dishes,isNull);
  });
  test('new history and quantity interface has English copy',(){
    for(final text in ['用餐历史','记录这一顿','评价这一顿','星级和评价可以稍后再填','份数','增加一份','减少一份','米饭份数','套餐份数','添加一道菜','移除这道菜','导出用餐历史','导入用餐历史']){
      expect(translateText(text,'en'),isNot(text));
    }
  });
}
