import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
  test('fourth canteen prices retain window, portion and weight distinctions', () {
    db.validate();
    final rows=db.offers.where((o)=>o.placeId=='sy').toList();
    expect(rows.length,352);
    expect(rows.where((o)=>!o.available).length,4);
    expect(rows.where((o)=>o.name=='烤鸭饭').map((o)=>o.priceCents).toSet(),{1200,1400});
    expect(rows.singleWhere((o)=>o.name=='木桶饭（三荤一素）').priceCents,1500);
    expect(rows.where((o)=>o.name=='米饭套餐（三荤）').map((o)=>o.window).toSet(),{'5号窗口','9号窗口'});
    expect(rows.every((o)=>o.evidence.isNotEmpty && !o.ingredientsKnown),isTrue);
    final weighted=entries(db,MenuDb.empty(Source.personal),Scope.official)
      .where((e)=>e.offer.placeId=='sy' && !e.offer.available).toList();
    expect(recommend(weighted,const MealRequest(budget:2000,mode:MealMode.mainWithSides),Random(1)).meal,isNull);
  });
  test('shipped v5 upgrades without installing new store or altering personal data', () async {
    final old=MenuDb.decode(File('assets/official-v5.json').readAsStringSync(),Source.official);
    final personal=MenuDb.empty(Source.personal).encode();
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey:jsonEncode({
      'official':old.encode(),'personal':personal,'installedStores':['sf','jml'],
    })});
    final repo=await MenuRepository.load();
    expect(repo.official.revision,9);
    expect(repo.official.places.any((p)=>p.id=='sy'),isTrue);
    expect(repo.installedStoreIds,{'sf','jml'});
    expect(repo.personal.encode(),personal);
    await repo.setStoreInstalled('sy',true);
    expect(repo.activeOfficial.offers.where((o)=>o.placeId=='sy').length,352);
  });
  test('customized v5 library is not replaced', () async {
    final old=jsonDecode(File('assets/official-v5.json').readAsStringSync()) as Map<String,dynamic>;
    old['offers'][0]['priceCents']=12345;
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey:jsonEncode({
      'official':jsonEncode(old),'personal':MenuDb.empty(Source.personal).encode(),
    })});
    final repo=await MenuRepository.load();
    expect(repo.official.revision,5);
    expect(repo.official.offers.first.priceCents,12345);
  });
}
