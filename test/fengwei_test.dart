import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
  final old=MenuDb.decode(File('assets/official-v6.json').readAsStringSync(),Source.official);
  test('Fengwei keeps windows and portion prices and excludes uncertain prices', () {
    db.validate();
    final rows=db.offers.where((o)=>o.placeId=='fw').toList();
    expect(rows.length,433);
    expect(rows.singleWhere((o)=>o.name=='鸡腿饭').priceCents,1200);
    expect(rows.singleWhere((o)=>o.name=='肉茸面').priceCents,300);
    expect(rows.where((o)=>o.name=='猪脚饭').map((o)=>o.priceCents).toSet(),{1800,2500});
    expect(rows.where((o)=>o.name=='鱼香肉丝').map((o)=>o.priceCents).toSet(),{1200,2800});
    expect(rows.singleWhere((o)=>o.name=='鸡腿饭').available,isTrue);
    expect(rows.where((o)=>o.portion.startsWith('每')).every((o)=>!o.available),isTrue);
    expect(rows.singleWhere((o)=>o.name=='优质双人鱼椒面').available,isFalse);
    expect(rows.where((o)=>o.addonOnly).every((o)=>o.kind=='side'),isTrue);
    expect(rows.every((o)=>o.mealPeriods.toSet().containsAll({'lunch','dinner'}) && !o.mealPeriods.contains('breakfast')),isTrue);
    expect(db.offers.where((o)=>o.placeId!='fw' && o.placeId!='zxb').map((o)=>jsonEncode(o.toJson())).toList(),old.offers.map((o)=>jsonEncode(o.toJson())).toList());
  });
  test('v6 migration preserves personal dishes and installed store selection', () async {
    final personal=MenuDb(source:Source.personal,revision:3,places:old.places,foods:old.foods,offers:old.offers);
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey:jsonEncode({'official':old.encode(),'personal':personal.encode(),'installedStores':['sf']})});
    final repo=await MenuRepository.load();
    expect(repo.official.revision,9);
    expect(repo.official.places.any((p)=>p.id=='fw'),isTrue);
    expect(repo.personal.encode(),personal.encode());
    expect(repo.installedStoreIds,{'sf'});
    await repo.setStoreInstalled('fw',true);
    expect(repo.activeOfficial.offers.any((o)=>o.placeId=='fw'),isTrue);
  });
  test('edited v6 official catalog is not overwritten', () async {
    final custom=jsonDecode(old.encode()) as Map<String,dynamic>;
    custom['offers'][0]['priceCents']=12345;
    final edited=MenuDb.decode(jsonEncode(custom),Source.official);
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey:jsonEncode({'official':edited.encode(),'personal':MenuDb.empty(Source.personal).encode()})});
    final repo=await MenuRepository.load();
    expect(repo.official.encode(),edited.encode());
  });
}
