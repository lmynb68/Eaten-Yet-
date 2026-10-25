import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/rice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
  final plan=db.ricePlans.single;
  test('32 priced dishes include separate egg and chicken, rice costs one yuan', () {
    expect(plan.dishPrices.length,32);
    expect(plan.priceCents,100); expect(plan.riceRefill,isTrue);
    expect(plan.totalPrice(['卤鸡蛋','烤肠','港式烧肉']),1500);
    expect(plan.totalPrice(['土豆丝',null,null]),300);
    expect(plan.dishPrices['鸡腿'],500);
    expect(plan.dishPhotos.values.toSet().length,31);
    expect(plan.dishPhotos.containsKey('卤鸡蛋'),isFalse);
    expect(jsonDecode(db.encode())['schemaVersion'],4);
    for (final path in plan.dishPhotos.values) { expect(File(path).existsSync(),isTrue); }
    expect(RicePlan.fromJson(plan.toJson()).totalPrice(['鱼排（无刺）']),800);
  });
  test('random respects variable prices, locks and remaining budget after snacks', () {
    for (var seed=0;seed<20;seed++) {
      final result=randomRice(plan,900-150,['糖醋里脊',null,null],{},Random(seed));
      expect(result.dishes,isNotNull);
      expect(plan.totalPrice(result.dishes!),lessThanOrEqualTo(750));
      expect(result.dishes!.toSet().length,3);
      final locked=randomRice(plan,1200,['糖醋里脊',null,null],{0},Random(seed));
      expect(locked.dishes![0],'糖醋里脊');
      expect(plan.totalPrice(locked.dishes!),lessThanOrEqualTo(1200));
    }
    expect(randomRice(plan,500,[null,null,null],{},Random(1)).dishes,isNull);
  });
  test('v4 upgrade preserves personal data and removed stores', () async {
    final old=MenuDb.decode(File('assets/official-v4.json').readAsStringSync(),Source.official);
    final personal=MenuDb.empty(Source.personal).encode();
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey:jsonEncode({
      'official':old.encode(),'personal':personal,'installedStores':['jml'],
    })});
    final r=await MenuRepository.load();
    expect(r.official.revision,9); expect(r.personal.encode(),personal);
    expect(r.activeOfficial.ricePlans,isEmpty);
    await r.setStoreInstalled('sf',true);
    expect(r.activeOfficial.ricePlans.single.dishPrices.length,32);
  });
  test('modified imported v4 is never silently replaced', () async {
    final old=jsonDecode(File('assets/official-v4.json').readAsStringSync()) as Map<String,dynamic>;
    old['offers'][0]['priceCents']=12345;
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey:jsonEncode({
      'official':jsonEncode(old),'personal':MenuDb.empty(Source.personal).encode(),
    })});
    final r=await MenuRepository.load();
    expect(r.official.revision,4); expect(r.official.offers.first.priceCents,12345);
  });
}
