import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eat_what/domain.dart';
import 'package:eat_what/repository.dart';

class RecordingMenuBundle extends CachingAssetBundle {
  RecordingMenuBundle({this.current, this.missingLegacy = false});
  final String? current;
  final bool missingLegacy;
  final paths = <String>[];
  @override
  Future<ByteData> load(String key) async {
    paths.add(key);
    if (key == 'assets/official.json' && current != null) {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(current!)));
    }
    if (missingLegacy && key.contains('official-v')) throw StateError('missing legacy asset');
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db=MenuDb.decode(File('assets/official.json').readAsStringSync(),Source.official);
  final old=MenuDb.decode(File('assets/official-v6.json').readAsStringSync(),Source.official);
  test('every supported revision has a known digest, including the current release', () {
    for (var version = 4; version <= db.revision; version++) {
      final reference = version == db.revision ? db : MenuDb.decode(
        File('assets/official-v$version.json').readAsStringSync(), Source.official);
      expect(reference.revision, version);
      expect(shippedMenuDigests[version], sha256.convert(utf8.encode(reference.encode())).toString(),
        reason: 'Catalog revision $version must match its shipped digest');
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/official-v4.json'));
  });
  for (final edited in [false, true]) {
    test('next built-in revision upgrades only unedited previous catalog: edited=$edited', () async {
      final saved = jsonDecode(db.encode());
      if (edited) saved['offers'][0]['priceCents'] = 12345;
      final next = jsonDecode(db.encode())..['revision'] = db.revision + 1;
      SharedPreferences.setMockInitialValues({MenuRepository.storageKey: jsonEncode({
        'official':jsonEncode(saved), 'personal': MenuDb.empty(Source.personal).encode(), 'installedStores':['sf'],
      })});
      final bundle = RecordingMenuBundle(current: jsonEncode(next));
      final restored = await MenuRepository.load(assets: bundle);
      expect(restored.official.encode(), MenuDb.decode(jsonEncode(edited ? saved : next), Source.official).encode());
      expect(restored.installedStoreIds, {'sf'});
      expect(bundle.paths, ['assets/official.json']);
    });
  }
  test('missing v3 comparison asset preserves the saved official and personal catalogs', () async {
    final saved = jsonDecode(old.encode())..['revision'] = 3;
    final personal = MenuDb.empty(Source.personal);
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey: jsonEncode({
      'official':jsonEncode(saved), 'personal':personal.encode(), 'installedStores':['sf'],
    })});
    final restored = await MenuRepository.load(assets: RecordingMenuBundle(missingLegacy:true));
    expect(restored.official.encode(), MenuDb.decode(jsonEncode(saved), Source.official).encode());
    expect(restored.personal.encode(), personal.encode());
    expect(restored.installedStoreIds, {'sf'});
  });
  for (final revision in [db.revision, db.revision + 1]) {
    test('saved revision $revision reads only current asset and restores user choices', () async {
      final saved = jsonDecode(db.encode()) as Map<String, dynamic>;
      saved['revision'] = revision;
      final personal = MenuDb(source: Source.personal, revision: 3, places: old.places, foods: old.foods, offers: old.offers);
      SharedPreferences.setMockInitialValues({MenuRepository.storageKey: jsonEncode({
        'official': jsonEncode(saved), 'personal': personal.encode(), 'installedStores': ['sf'],
      })});
      final bundle = RecordingMenuBundle();
      final restored = await MenuRepository.load(assets: bundle);
      expect(bundle.paths, ['assets/official.json']);
      expect(restored.official.revision, revision);
      expect(restored.personal.encode(), personal.encode());
      expect(restored.installedStoreIds, {'sf'});
    });
  }
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
  });
  test('v6 migration preserves personal dishes and installed store selection', () async {
    final personal=MenuDb(source:Source.personal,revision:3,places:old.places,foods:old.foods,offers:old.offers);
    SharedPreferences.setMockInitialValues({MenuRepository.storageKey:jsonEncode({'official':old.encode(),'personal':personal.encode(),'installedStores':['sf']})});
    final bundle = RecordingMenuBundle();
    final repo=await MenuRepository.load(assets: bundle);
    expect(bundle.paths, ['assets/official.json']);
    expect(repo.official.revision,db.revision);
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
    final bundle = RecordingMenuBundle();
    final repo=await MenuRepository.load(assets: bundle);
    expect(bundle.paths, ['assets/official.json']);
    expect(repo.official.encode(),edited.encode());
  });
}
