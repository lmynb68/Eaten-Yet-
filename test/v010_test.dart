import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';
import 'package:eat_what/updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',}));
  final catalog=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
  test('community menu contains seven noodle meals, two dumpling meals and one optional snack',() {
    final items=catalog.offers.where((o)=>o.placeId=='community').toList();
    expect(items.length,10);
    expect(items.where((o)=>o.stapleType=='noodles').length,7);
    expect(items.where((o)=>o.stapleType=='dumplings').length,2);
    expect(items.singleWhere((o)=>o.kind=='side').priceCents,150);
    expect(catalog.offers.where((o)=>o.kind=='main' && o.name.startsWith('自选套餐')).every((o)=>o.stapleType=='rice'),isTrue);
  });
  test('removed stores and rice sets stay excluded across restart and catalog update',() async {
    final r=await MenuRepository.load();
    await r.setStoreInstalled('sf',false);
    expect(r.activeOfficial.places.any((p)=>p.id=='sf'),isFalse);
    expect(r.activeOfficial.offers.any((o)=>o.placeId=='sf'),isFalse);
    expect(r.activeOfficial.ricePlans,isEmpty);
    final personal=r.personal.encode();
    final next=MenuDb(source:Source.official,revision:5,
      places:[...catalog.places,const Place('new-store','New','')],foods:catalog.foods,
      offers:catalog.offers,ricePlans:catalog.ricePlans);
    await r.replace(next);
    final loaded=await MenuRepository.load();
    expect(loaded.official.places.any((p)=>p.id=='new-store'),isTrue);
    expect(loaded.activeOfficial.places.map((p)=>p.id),isNot(contains('new-store')));
    expect(loaded.activeOfficial.places.map((p)=>p.id),isNot(contains('sf')));
    expect(loaded.personal.encode(),personal);
    await loaded.setStoreInstalled('sf',true);
    expect(loaded.activeOfficial.offers.where((o)=>o.placeId=='sf').length,196);
  });
  test('known shipped v3 migrates without losing personal data',() async {
    final catalog=MenuDb.decode(File('assets/official-v4.json').readAsStringSync(),Source.official);
    final old=MenuDb(source:Source.official,revision:3,
      places:catalog.places.where((p)=>p.id!='community').toList(),foods:catalog.foods,
      offers:catalog.offers.where((o)=>o.placeId!='community').toList(),ricePlans:catalog.ricePlans);
    SharedPreferences.setMockInitialValues({'eat_what.meal_period':'lunch',MenuRepository.storageKey:jsonEncode({
      'official':old.encode(),'personal':MenuDb.empty(Source.personal).encode(),
    })});
    final r=await MenuRepository.load();
    expect(r.official.revision,9);
    expect(r.activeOfficial.places.map((p)=>p.id),contains('community'));
  });
  test('store photo and explicit staple survive export',() {
    final db=MenuDb(source:Source.personal,revision:1,
      places:[Place('p','Store','',photo:base64Encode([1,2,3]))],foods:[],
      offers:[const Offer(id:'o',placeId:'p',name:'My bowl',portion:'1',priceCents:100,
        roles:{},foodIds:{},updatedAt:'2026-10-16',kind:'main',staple:'noodles')]);
    final decoded=MenuDb.decode(db.encode(),Source.personal);
    expect(decoded.places.single.photo,db.places.single.photo);
    expect(decoded.offers.single.stapleType,'noodles');
  });
  test('numeric versions, drafts and unrelated release links are handled',() {
    expect(compareVersions('v0.10.0','0.9.9'),greaterThan(0));
    expect(compareVersions('v0.10.0','0.10.0'),0);
    expect(compareVersions('0.11.0-beta','0.11.0'),lessThan(0));
    final latest=AppRelease.latest(jsonEncode([
      {'tag_name':'v9.0.0','draft':true,'html_url':'$releasesUrl/tag/v9.0.0'},
      {'tag_name':'v8.0.0','html_url':'https://example.com/release'},
      {'tag_name':'v0.9.0','html_url':'$releasesUrl/tag/v0.9.0'},
      {'tag_name':'v0.11.0','html_url':'$releasesUrl/tag/v0.11.0'},
    ]));
    expect(latest!.version,'v0.11.0');
    expect(AppRelease.latest('[]'),isNull);
    expect(File('pubspec.yaml').readAsStringSync(),contains('version: $appVersion+$appBuild'));
  });
}
